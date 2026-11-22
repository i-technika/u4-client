import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart' show ThemeMode;

/// `config/app_config.<flavor>.json`을 읽어 만든 앱 설정.
///
/// 구조와 기본값은 `config/app_config.schema.json`을 따른다. 스키마 검증은
/// 에디터와 CI(`tool/validate_config.sh`)에서 하고, 여기서는 모르는 키 거부·
/// 기본값 채우기·타입과 enum 변환·prod 제약 등을 다시 검사한다
/// (항목은 docs/phase-1-setup.md 5장).
@immutable
class AppConfig {
  const AppConfig({
    required this.flavor,
    required this.app,
    required this.splash,
    required this.systemUi,
    required this.theme,
    required this.screen,
    required this.navigation,
    required this.popup,
    required this.dialog,
    required this.permissions,
    required this.network,
    required this.extras,
  });

  factory AppConfig.fromJson(Map<String, Object?> json) {
    // 값을 읽기 전에 모르는 키부터 검사한다. 그래야 필수 키 오타(startURL)가
    // "startUrl이 필요합니다"나 다른 값의 타입 오류에 가려지지 않는다.
    _rejectUnknownKeys(json);
    final config = _read(_Reader(json, r'$'));
    config._validate();
    return config;
  }

  /// 모델이 읽는 키를 object 경로별로 모은 표 (예: `$.network` → `{secureScreen, ...}`).
  ///
  /// 최소 설정으로 모델을 한 번 만들며 [_Reader]가 읽은 키를 기록해 얻는다.
  /// 모델은 모든 키를 조건 없이 읽으므로 입력과 상관없이 같은 표가 나온다.
  /// 스키마와 정확히 같은지는 테스트가 확인한다.
  ///
  /// 최소 설정은 모델이 읽기 단계에서 하는 검사(필수 키, 타입, 형식)를 모두
  /// 통과해야 한다. 필수 키를 늘리거나 읽기 단계에 범위 검사를 넣으면(#5)
  /// 최소 설정도 함께 고친다. 어긋나면 사용자 설정 오류가 아닌 코드 버그로
  /// [StateError]를 던진다.
  @visibleForTesting
  static final Map<String, Set<String>> knownKeys = () {
    final keys = <String, Set<String>>{};
    try {
      _read(
        _Reader(
          const {
            'flavor': 'dev',
            'app': {
              'name': 'x',
              'startUrl': 'https://example.com/',
              'allowedHosts': ['example.com'],
            },
          },
          r'$',
          keys,
        ),
      );
    } on AppConfigException catch (e) {
      throw StateError('knownKeys용 최소 설정이 모델과 맞지 않습니다: ${e.message}');
    }
    return Map<String, Set<String>>.unmodifiable(
      keys.map((path, set) => MapEntry(path, Set<String>.unmodifiable(set))),
    );
  }();

  static final _identifier = RegExp(r'^[A-Za-z_$][A-Za-z0-9_$]*$');

  /// [knownKeys]에 없는 키(오타, 스키마에 없는 키)를 하위 object까지 모아 실패한다.
  static void _rejectUnknownKeys(Map<String, Object?> json) {
    final unknown = <String>[];
    void walk(Map<String, Object?> map, String path) {
      final known = knownKeys[path]!;
      for (final MapEntry(:key, :value) in map.entries) {
        final childPath = '$path.$key';
        if (!known.contains(key)) {
          // 아는 키는 모두 식별자라 '.'이 없다. 다른 키는 `$["a.b"]`로 적어
          // 스키마에 있는 경로(`$.a.b`)와 헷갈리지 않게 한다.
          unknown.add(
            _identifier.hasMatch(key) ? childPath : '$path[${jsonEncode(key)}]',
          );
        } else if (value is Map<String, Object?> &&
            knownKeys.containsKey(childPath)) {
          walk(value, childPath);
        }
        // object가 아닌 값이 object 자리에 오면 읽을 때 타입 오류로 알린다.
      }
    }

    walk(json, r'$');
    if (unknown.isNotEmpty) {
      // 목록 구분자는 ', '. 괄호 표기 키는 JSON 문자열이라 구분자와 섞이지 않는다.
      throw AppConfigException('스키마에 없는 키: ${unknown.join(', ')}');
    }
  }

  static AppConfig _read(_Reader r) {
    // 에디터용 스키마 참조. 값은 쓰지 않지만 아는 키로 기록한다.
    r.optString(r'$schema');
    return AppConfig(
      flavor: r.choice('flavor', Flavor.values),
      app: AppInfo._(r.child('app')),
      splash: SplashConfig._(r.child('splash')),
      systemUi: SystemUiConfig._(r.child('systemUi')),
      theme: ThemeConfig._(r.child('theme')),
      screen: ScreenConfig._(r.child('screen')),
      navigation: NavigationConfig._(r.child('navigation')),
      popup: PopupConfig._(r.child('popup')),
      dialog: DialogConfig._(r.child('dialog')),
      permissions: PermissionsConfig._(r.child('permissions')),
      network: NetworkConfig._(r.child('network')),
      extras: ExtrasConfig._(r.child('extras')),
    );
  }

  /// 번들된 flavor 설정 파일을 읽는다.
  ///
  /// asset 누락, JSON 형식 오류, 최상위 타입 오류를 포함해 모든 설정 오류에
  /// 파일 경로를 붙여 [AppConfigException]으로 던진다.
  static Future<AppConfig> load(Flavor flavor, {AssetBundle? bundle}) async {
    final path = flavor.assetPath;
    final String text;
    try {
      text = await (bundle ?? rootBundle).loadString(path);
    } on FlutterError catch (e) {
      throw AppConfigException('$path: asset을 읽지 못함 (${e.message})');
    }
    final Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException catch (e) {
      throw AppConfigException('$path: JSON 형식 오류 (${e.message})');
    }
    if (json is! Map<String, Object?>) {
      throw AppConfigException('$path: 최상위가 object가 아닙니다');
    }
    final AppConfig config;
    try {
      config = AppConfig.fromJson(json);
    } on AppConfigException catch (e) {
      throw AppConfigException('$path: ${e.message}');
    }
    if (config.flavor != flavor) {
      throw AppConfigException('$path의 flavor가 ${config.flavor.name}입니다');
    }
    return config;
  }

  final Flavor flavor;
  final AppInfo app;
  final SplashConfig splash;
  final SystemUiConfig systemUi;
  final ThemeConfig theme;
  final ScreenConfig screen;
  final NavigationConfig navigation;
  final PopupConfig popup;
  final DialogConfig dialog;
  final PermissionsConfig permissions;
  final NetworkConfig network;
  final ExtrasConfig extras;

  void _validate() {
    if (app.allowedHosts.isEmpty) {
      throw const AppConfigException(r'$.app.allowedHosts가 비어 있습니다');
    }
    if (extras.forceUpdate.enabled && extras.forceUpdate.checkUrl == null) {
      throw const AppConfigException(r'$.extras.forceUpdate.checkUrl이 필요합니다');
    }
    if (flavor != Flavor.prod) return;
    // 스키마 검증을 거치지 않은 빌드 대비
    if (app.startUrl.scheme != 'https') {
      throw const AppConfigException('prod의 startUrl은 https여야 합니다');
    }
    if (network.allowHttp || network.ignoreSslErrors || network.debuggable) {
      throw const AppConfigException(
        'prod에서는 allowHttp, ignoreSslErrors, debuggable을 켤 수 없습니다',
      );
    }
  }
}

enum Flavor {
  dev,
  stg,
  prod;

  String get assetPath => 'config/app_config.$name.json';

  /// 현재 빌드의 flavor.
  ///
  /// Android는 `--flavor`(appFlavor), iOS는 아직 Xcode scheme이 없으므로
  /// `--dart-define=FLAVOR=`로 정한다. release 빌드에서 둘 다 없으면 실패한다.
  static Flavor get current {
    const defined = String.fromEnvironment('FLAVOR');
    final name = appFlavor ?? (defined.isEmpty ? null : defined);
    if (name == null) {
      if (kReleaseMode) {
        throw const AppConfigException(
          'release 빌드는 --flavor 또는 --dart-define=FLAVOR가 필요합니다',
        );
      }
      return Flavor.dev;
    }
    return Flavor.values.firstWhere(
      (f) => f.name == name,
      orElse: () => throw AppConfigException('알 수 없는 flavor: $name'),
    );
  }
}

class AppConfigException implements Exception {
  const AppConfigException(this.message);

  final String message;

  @override
  String toString() => 'AppConfigException: $message';
}

// ---- app ----

@immutable
class AppInfo {
  AppInfo._(_Reader r)
    : name = r.string('name'),
      startUrl = r.uri('startUrl'),
      allowedHosts = r.strings('allowedHosts'),
      externalHosts = r.strings('externalHosts'),
      userAgentSuffix = r.string(
        'userAgentSuffix',
        'U4App/{version} ({platform})',
      );

  final String name;
  final Uri startUrl;
  final List<String> allowedHosts;
  final List<String> externalHosts;
  final String userAgentSuffix;
}

// ---- splash ----

enum SplashCloseTrigger { onLoadStop, onFirstPaint, webSignal }

@immutable
class SplashConfig {
  SplashConfig._(_Reader r)
    : minDisplay = r.millis('minDisplayMs', 1000),
      closeTrigger = r.choice(
        'closeTrigger',
        SplashCloseTrigger.values,
        SplashCloseTrigger.onLoadStop,
      ),
      delayAfterLoad = r.millis('delayAfterLoadMs', 0),
      maxWait = r.millis('maxWaitMs', 10000),
      fadeOut = r.millis('fadeOutMs', 300),
      bgColor = ThemedColor._(
        r.child('bgColor'),
        light: const Color(0xFFFFFFFF),
        dark: const Color(0xFF000000),
      ),
      image = r.optString('image'),
      showProgress = r.boolean('showProgress', false);

  final Duration minDisplay;
  final SplashCloseTrigger closeTrigger;
  final Duration delayAfterLoad;
  final Duration maxWait;
  final Duration fadeOut;
  final ThemedColor bgColor;
  final String? image;
  final bool showProgress;
}

// ---- systemUi ----

enum BarMode { visible, overlay, hidden }

enum BarStyle { auto, light, dark }

enum SafeAreaHandling { native, css }

@immutable
class BarConfig {
  BarConfig._(_Reader r)
    : mode = r.choice('mode', BarMode.values, BarMode.visible),
      style = r.choice('style', BarStyle.values, BarStyle.auto),
      color = ThemedColor._(r.child('color'));

  final BarMode mode;
  final BarStyle style;
  final ThemedColor color;
}

@immutable
class SystemUiConfig {
  SystemUiConfig._(_Reader r)
    : statusBar = BarConfig._(r.child('statusBar')),
      navigationBar = BarConfig._(r.child('navigationBar')),
      safeAreaHandling = r.choice(
        'safeAreaHandling',
        SafeAreaHandling.values,
        SafeAreaHandling.css,
      ),
      immersive = r.boolean('immersive', false),
      allowWebControl = r.boolean('allowWebControl', false);

  final BarConfig statusBar;
  final BarConfig navigationBar;
  final SafeAreaHandling safeAreaHandling;
  final bool immersive;
  final bool allowWebControl;
}

// ---- theme ----

@immutable
class ThemeConfig {
  ThemeConfig._(_Reader r)
    : themeMode = r.choice('themeMode', ThemeMode.values, ThemeMode.system),
      propagateToWeb = r.boolean('propagateToWeb', true),
      allowWebOverride = r.boolean('allowWebOverride', false);

  final ThemeMode themeMode;
  final bool propagateToWeb;
  final bool allowWebOverride;
}

// ---- screen ----

enum ScreenOrientation { portrait, landscape, auto }

@immutable
class ScreenConfig {
  ScreenConfig._(_Reader r)
    : orientation = r.choice(
        'orientation',
        ScreenOrientation.values,
        ScreenOrientation.portrait,
      ),
      allowWebOrientationChange = r.boolean('allowWebOrientationChange', false),
      textZoomFixed = r.boolean('textZoomFixed', true),
      pinchZoom = r.boolean('pinchZoom', false),
      textSelection = r.boolean('textSelection', true),
      longPressMenu = r.boolean('longPressMenu', false),
      overscroll = r.boolean('overscroll', false),
      pullToRefresh = r.boolean('pullToRefresh', true);

  final ScreenOrientation orientation;
  final bool allowWebOrientationChange;
  final bool textZoomFixed;
  final bool pinchZoom;
  final bool textSelection;
  final bool longPressMenu;
  final bool overscroll;
  final bool pullToRefresh;
}

// ---- navigation ----

enum AndroidBackMode { historyThenExit, exitOnly }

enum ExitConfirm { doubleTap, dialog }

enum ExternalLinkMode { system, inAppBrowser, block }

@immutable
class NavigationConfig {
  factory NavigationConfig._(_Reader r) {
    final back = r.child('androidBack');
    return NavigationConfig._of(
      androidBackMode: back.choice(
        'mode',
        AndroidBackMode.values,
        AndroidBackMode.historyThenExit,
      ),
      exitConfirm: back.choice(
        'exitConfirm',
        ExitConfirm.values,
        ExitConfirm.doubleTap,
      ),
      iosSwipeBack: r.boolean('iosSwipeBack', true),
      externalLinkMode: r.choice(
        'externalLinkMode',
        ExternalLinkMode.values,
        ExternalLinkMode.system,
      ),
    );
  }

  const NavigationConfig._of({
    required this.androidBackMode,
    required this.exitConfirm,
    required this.iosSwipeBack,
    required this.externalLinkMode,
  });

  final AndroidBackMode androidBackMode;
  final ExitConfirm exitConfirm;
  final bool iosSwipeBack;
  final ExternalLinkMode externalLinkMode;
}

// ---- popup ----

enum PopupPresentation { push, modal, sheet }

@immutable
class PopupConfig {
  factory PopupConfig._(_Reader r) {
    final presentation = r.choice(
      'presentation',
      PopupPresentation.values,
      PopupPresentation.push,
    );
    final toolbar = r.child('toolbar');
    return PopupConfig._of(
      presentation: presentation,
      toolbarCloseButton: toolbar.boolean('closeButton', true),
      toolbarTitle: toolbar.boolean('title', true),
      toolbarProgressBar: toolbar.boolean('progressBar', true),
      maxDepth: r.integer('maxDepth', 5),
    );
  }

  const PopupConfig._of({
    required this.presentation,
    required this.toolbarCloseButton,
    required this.toolbarTitle,
    required this.toolbarProgressBar,
    required this.maxDepth,
  });

  final PopupPresentation presentation;
  final bool toolbarCloseButton;
  final bool toolbarTitle;
  final bool toolbarProgressBar;
  final int maxDepth;
}

// ---- dialog ----

enum DialogStyle { platform, material, cupertino }

@immutable
class DialogConfig {
  factory DialogConfig._(_Reader r) {
    final style = r.choice('style', DialogStyle.values, DialogStyle.platform);
    final labels = r.child('labels');
    return DialogConfig._of(
      style: style,
      okLabel: labels.optString('ok'),
      cancelLabel: labels.optString('cancel'),
      leavePageLabel: labels.optString('leavePage'),
    );
  }

  const DialogConfig._of({
    required this.style,
    required this.okLabel,
    required this.cancelLabel,
    required this.leavePageLabel,
  });

  final DialogStyle style;

  /// null이면 locale 기본 문구를 쓴다.
  final String? okLabel;
  final String? cancelLabel;
  final String? leavePageLabel;
}

// ---- permissions ----

enum AppPermission { location, camera, microphone, photos, notification }

@immutable
class PermissionsConfig {
  PermissionsConfig._(_Reader r)
    : requestOnLaunch = r.choices('requestOnLaunch', AppPermission.values),
      deniedGuide = r.boolean('deniedGuide', true);

  final List<AppPermission> requestOnLaunch;
  final bool deniedGuide;
}

// ---- network ----

enum CacheMode {
  standard('default'),
  noCache('noCache'),
  cacheElseNetwork('cacheElseNetwork');

  const CacheMode(this.wire);

  /// JSON 값. `default`는 Dart 예약어라 enum 이름과 따로 둔다.
  final String wire;
}

@immutable
class NetworkConfig {
  factory NetworkConfig._(_Reader r) {
    final offlinePage = r.optString('offlinePage');
    final errorPage = r.optString('errorPage');
    final retry = r.child('retry');
    return NetworkConfig._of(
      offlinePage: offlinePage,
      errorPage: errorPage,
      retryAutoOnReconnect: retry.boolean('autoOnReconnect', true),
      retryMaxAttempts: retry.integer('maxAttempts', 3),
      allowHttp: r.boolean('allowHttp', false),
      ignoreSslErrors: r.boolean('ignoreSslErrors', false),
      debuggable: r.boolean('debuggable', false),
      secureScreen: r.boolean('secureScreen', false),
      clearCacheOnLaunch: r.boolean('clearCacheOnLaunch', false),
      cacheMode: r.choiceBy(
        'cacheMode',
        CacheMode.values,
        CacheMode.standard,
        (m) => m.wire,
      ),
    );
  }

  const NetworkConfig._of({
    required this.offlinePage,
    required this.errorPage,
    required this.retryAutoOnReconnect,
    required this.retryMaxAttempts,
    required this.allowHttp,
    required this.ignoreSslErrors,
    required this.debuggable,
    required this.secureScreen,
    required this.clearCacheOnLaunch,
    required this.cacheMode,
  });

  final String? offlinePage;
  final String? errorPage;
  final bool retryAutoOnReconnect;
  final int retryMaxAttempts;
  final bool allowHttp;
  final bool ignoreSslErrors;
  final bool debuggable;
  final bool secureScreen;
  final bool clearCacheOnLaunch;
  final CacheMode cacheMode;
}

// ---- extras ----

@immutable
class ForceUpdateConfig {
  ForceUpdateConfig._(_Reader r)
    : enabled = r.boolean('enabled', false),
      checkUrl = r.optUri('checkUrl');

  final bool enabled;
  final Uri? checkUrl;
}

@immutable
class ExtrasConfig {
  ExtrasConfig._(_Reader r)
    : pushEnabled = r.child('push').boolean('enabled', false),
      deeplinkDomains = r.child('deeplink').strings('domains'),
      forceUpdate = ForceUpdateConfig._(r.child('forceUpdate')),
      locale = r.string('locale', 'system');

  final bool pushEnabled;
  final List<String> deeplinkDomains;
  final ForceUpdateConfig forceUpdate;

  /// `system`이면 OS 설정을 따른다.
  final String locale;
}

// ---- 공통 ----

@immutable
class ThemedColor {
  ThemedColor._(_Reader r, {Color? light, Color? dark})
    : light = r.color('light') ?? light,
      dark = r.color('dark') ?? dark;

  final Color? light;
  final Color? dark;

  Color? resolve(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;
}

/// 경로를 붙여 에러를 알려 주는 JSON 읽기 도우미.
///
/// [AppConfig.knownKeys]는 이 reader가 읽은 키를 기록해 만든다. 그래서 모델은
/// 스키마의 모든 키를 값과 상관없이 **조건 없이** 읽어야 한다
/// (예: `enabled`가 true일 때만 `checkUrl`을 읽으면 `checkUrl`이 모르는 키가 된다).
///
/// 키를 생략하면 기본값을 쓰지만, `null`을 직접 적으면 실패한다.
/// 스키마도 `null`을 허용하지 않는다.
class _Reader {
  _Reader(this._map, this._path, [this._recorder]);

  final Map<String, Object?> _map;
  final String _path;

  /// object 경로별로 읽은 키를 기록할 곳. [AppConfig.knownKeys]를 만들 때만 쓴다.
  final Map<String, Set<String>>? _recorder;

  void _record(String key) => _recorder?.putIfAbsent(_path, () => {}).add(key);

  /// 하위 object를 읽는 reader. 생략한 object는 빈 object로 읽어 기본값을 채운다.
  _Reader child(String key) {
    _record(key);
    final path = '$_path.$key';
    _recorder?.putIfAbsent(path, () => {});
    final v = _map[key];
    if (v == null) {
      if (_map.containsKey(key)) throw _null(key);
      return _Reader(const {}, path, _recorder);
    }
    if (v is! Map<String, Object?>) throw _type(key, 'object');
    return _Reader(v, path, _recorder);
  }

  bool boolean(String key, bool fallback) =>
      _get<bool>(key, 'boolean') ?? fallback;

  int integer(String key, int fallback) =>
      _get<int>(key, 'integer') ?? fallback;

  Duration millis(String key, int fallback) =>
      Duration(milliseconds: integer(key, fallback));

  /// [fallback]이 없으면 필수 값이다.
  String string(String key, [String? fallback]) {
    final v = _get<String>(key, 'string') ?? fallback;
    if (v == null) throw AppConfigException('$_path.$key가 필요합니다');
    return v;
  }

  String? optString(String key) => _get<String>(key, 'string');

  Uri uri(String key) => _parseUri(key, string(key));

  Uri? optUri(String key) {
    final v = optString(key);
    return v == null ? null : _parseUri(key, v);
  }

  List<String> strings(String key) {
    final v = _get<List<Object?>>(key, 'array');
    if (v == null) return const [];
    return List.unmodifiable(
      v.map((e) {
        if (e is! String) throw _type(key, 'string 배열');
        return e;
      }),
    );
  }

  T choice<T extends Enum>(String key, List<T> values, [T? fallback]) =>
      choiceBy(key, values, fallback, null);

  /// JSON 값이 enum 이름과 다를 때 [nameOf]로 매핑한다.
  T choiceBy<T extends Enum>(
    String key,
    List<T> values,
    T? fallback,
    String Function(T)? nameOf,
  ) {
    final raw = _get<String>(key, 'string');
    if (raw == null) {
      if (fallback == null) throw AppConfigException('$_path.$key가 필요합니다');
      return fallback;
    }
    return _match(key, values, raw, nameOf);
  }

  List<T> choices<T extends Enum>(String key, List<T> values) {
    return List.unmodifiable(
      strings(key).map((s) => _match(key, values, s, null)),
    );
  }

  Color? color(String key) {
    final v = optString(key);
    if (v == null) return null;
    final hex = RegExp(r'^#([0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$')
        .firstMatch(v)
        ?.group(1);
    if (hex == null) throw AppConfigException('$_path.$key: 색상 형식 오류 ($v)');
    return Color(int.parse(hex.length == 6 ? 'FF$hex' : hex, radix: 16));
  }

  T _match<T extends Enum>(
    String key,
    List<T> values,
    String raw,
    String Function(T)? nameOf,
  ) {
    final name = nameOf ?? (T v) => v.name;
    for (final v in values) {
      if (name(v) == raw) return v;
    }
    throw AppConfigException(
      '$_path.$key: 알 수 없는 값 "$raw" (${values.map(name).join(' / ')})',
    );
  }

  Uri _parseUri(String key, String v) {
    final u = Uri.tryParse(v);
    if (u == null || !u.hasScheme || u.host.isEmpty) {
      throw AppConfigException('$_path.$key: URL 형식 오류 ($v)');
    }
    return u;
  }

  T? _get<T>(String key, String typeName) {
    _record(key);
    final v = _map[key];
    if (v == null) {
      if (_map.containsKey(key)) throw _null(key);
      return null;
    }
    if (v is! T) throw _type(key, typeName);
    return v as T;
  }

  AppConfigException _null(String key) =>
      AppConfigException('$_path.$key: null은 쓸 수 없습니다 (생략하면 기본값을 씁니다)');

  AppConfigException _type(String key, String typeName) =>
      AppConfigException('$_path.$key는 $typeName이어야 합니다');
}
