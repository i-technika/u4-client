import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart' show ThemeMode;

/// `config/app_config.<flavor>.json`을 읽어 만든 앱 설정.
///
/// 구조와 기본값은 `config/app_config.schema.json`을 따른다. 스키마 검증은
/// 에디터와 CI에서 하고, 여기서는 기본값 채우기·enum 변환·prod 제약만 다시 검사한다.
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
    final r = _Reader(json, r'$');
    final config = AppConfig(
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
    config._validate();
    return config;
  }

  /// 번들된 flavor 설정 파일을 읽는다.
  ///
  /// asset 누락, JSON 형식 오류, 최상위 타입 오류도 파일 경로를 붙여
  /// [AppConfigException]으로 던진다.
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
    final config = AppConfig.fromJson(json);
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

/// 설정에서 고를 수 있는 런타임 권한.
///
/// 플랫폼마다 요청할 수 있는 권한이 다르다. [isRequestableOn]으로 확인한다.
enum AppPermission {
  location,
  camera,
  microphone,

  /// 사진 보관함. iOS에서만 요청하고 Android에서는 건너뛴다.
  ///
  /// 웹 파일 업로드(`<input type=file>`)에는 두 플랫폼 모두 이 권한이 필요 없다.
  /// Android 웹뷰는 시스템 파일 선택기(`ACTION_GET_CONTENT`)로 고르고 임시 URI 권한을 받으며,
  /// iOS 웹뷰도 시스템 피커를 쓴다. iOS에서는 네이티브로 보관함을 직접 읽는 기능에만 쓴다.
  ///
  /// Android는 Play 사진·동영상 권한 정책 때문에 매니페스트에서 `READ_MEDIA_IMAGES`를
  /// 제거했다. permission_handler는 매니페스트에 없는 권한을 다이얼로그 없이 항상
  /// `denied`(영구 거부가 아님)로 돌려준다. 요청하면 기능이 늘 실패하고, 영구 거부가
  /// 아니라 설정 앱 안내로도 이어지지 않는다.
  /// Android 12(API 32) 이하는 permission_handler가 photos를 아예 지원하지 않아
  /// 매니페스트와 상관없이 `denied`다. 이 버전에서 필요해지면 `READ_EXTERNAL_STORAGE`
  /// (maxSdkVersion 32) 제거를 풀고 `storage`로 따로 매핑해야 한다.
  photos,
  notification;

  /// 매니페스트·플러그인 제약 때문에 [platform]에서 이 권한 요청을 건너뛰어야 하면 false.
  ///
  /// 플랫폼 단위 판단이다. API 레벨에 따른 실제 상태(예: Android 12 이하의 알림)는
  /// permission_handler가 돌려준다. [platform]에는 `defaultTargetPlatform`을 넘긴다.
  /// 앱 대상이 아닌 플랫폼(linux, windows 등)의 값은 의미가 없다.
  ///
  /// 새 권한을 추가하면 플랫폼별 지원 여부를 정하도록 와일드카드 없이 모두 나열한다.
  bool isRequestableOn(TargetPlatform platform) => switch (this) {
    location || camera || microphone || notification => true,
    photos => platform == TargetPlatform.iOS,
  };
}

@immutable
class PermissionsConfig {
  PermissionsConfig._(_Reader r)
    : _requestOnLaunch = r.choices('requestOnLaunch', AppPermission.values),
      deniedGuide = r.boolean('deniedGuide', true);

  /// 설정에 적힌 그대로의 목록. 설정 파일은 플랫폼 공통이라 어떤 플랫폼에서는
  /// 요청할 수 없는 권한이 섞여 있을 수 있다. 잘못 쓰지 않도록 공개하지 않고
  /// [requestOnLaunchOn]으로만 내보낸다.
  final List<AppPermission> _requestOnLaunch;

  /// 영구 거부(`isPermanentlyDenied`) 시 설정 앱 이동 안내.
  final bool deniedGuide;

  /// [platform]에서 앱 시작 시 요청할 권한(설정 순서 유지, 수정 불가).
  /// [AppPermission.isRequestableOn]이 false인 권한(Android의 [AppPermission.photos])은 뺀다.
  /// [platform]에는 `defaultTargetPlatform`을 넘긴다.
  ///
  /// 기능을 쓸 때 요청하는 경로도 [AppPermission.isRequestableOn]을 먼저 확인한다.
  List<AppPermission> requestOnLaunchOn(TargetPlatform platform) =>
      List.unmodifiable(
        _requestOnLaunch.where((p) => p.isRequestableOn(platform)),
      );
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
class _Reader {
  _Reader(this._map, this._path);

  final Map<String, Object?> _map;
  final String _path;

  /// 하위 object를 읽는 reader. JSON object 하나는 reader 하나로 읽도록
  /// 같은 [key]로는 한 번만 부른다.
  _Reader child(String key) {
    final v = _map[key];
    if (v == null) return _Reader(const {}, '$_path.$key');
    if (v is! Map<String, Object?>) throw _type(key, 'object');
    return _Reader(v, '$_path.$key');
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
    final v = _map[key];
    if (v == null) return null;
    if (v is! T) throw _type(key, typeName);
    return v as T;
  }

  AppConfigException _type(String key, String typeName) =>
      AppConfigException('$_path.$key는 $typeName이어야 합니다');
}
