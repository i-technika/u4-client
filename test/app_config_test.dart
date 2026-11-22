import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' show ThemeMode;

import 'package:u4/config/app_config.dart';

import 'helpers.dart';

void main() {
  group('번들 설정 파일', () {
    for (final flavor in Flavor.values) {
      test('${flavor.name} 설정을 읽는다', () {
        final config = AppConfig.fromJson(readConfigJson(flavor));
        expect(config.flavor, flavor);
        expect(config.app.allowedHosts, isNotEmpty);
      });
    }

    test('prod는 개발용 옵션이 꺼져 있다', () {
      final config = AppConfig.fromJson(readConfigJson(Flavor.prod));
      expect(config.app.startUrl.scheme, 'https');
      expect(config.network.allowHttp, isFalse);
      expect(config.network.ignoreSslErrors, isFalse);
      expect(config.network.debuggable, isFalse);
    });
  });

  group('기본값', () {
    final minimal = {
      'flavor': 'dev',
      'app': {
        'name': 'Test',
        'startUrl': 'https://example.com/',
        'allowedHosts': ['example.com'],
      },
    };

    test('생략한 그룹은 스키마 기본값으로 채운다', () {
      final config = AppConfig.fromJson(minimal);
      expect(config.splash.minDisplay, const Duration(seconds: 1));
      expect(config.splash.closeTrigger, SplashCloseTrigger.onLoadStop);
      expect(config.splash.bgColor.light, isNotNull);
      expect(config.systemUi.safeAreaHandling, SafeAreaHandling.css);
      expect(config.theme.themeMode, ThemeMode.system);
      expect(
        config.navigation.androidBackMode,
        AndroidBackMode.historyThenExit,
      );
      expect(config.popup.maxDepth, 5);
      expect(config.network.cacheMode, CacheMode.standard);
      expect(config.app.userAgentSuffix, 'U4App/{version} ({platform})');
    });

    test('cacheMode의 JSON 값 default를 읽는다', () {
      final config = AppConfig.fromJson({
        ...minimal,
        'network': {'cacheMode': 'default'},
      });
      expect(config.network.cacheMode, CacheMode.standard);
    });

    test('cacheMode의 JSON 값 noCache를 읽는다', () {
      final config = AppConfig.fromJson({
        ...minimal,
        'network': {'cacheMode': 'noCache'},
      });
      expect(config.network.cacheMode, CacheMode.noCache);
    });
  });

  group('검증', () {
    Map<String, Object?> prod({Map<String, Object?> network = const {}}) => {
      'flavor': 'prod',
      'app': {
        'name': 'Test',
        'startUrl': 'https://example.com/',
        'allowedHosts': ['example.com'],
      },
      'network': network,
    };

    test('prod에서 debuggable을 켜면 실패한다', () {
      expect(
        () => AppConfig.fromJson(prod(network: {'debuggable': true})),
        _throwsConfigError(
          'prod에서는 allowHttp, ignoreSslErrors, debuggable을 켤 수 없습니다',
        ),
      );
    });

    test('prod의 startUrl이 http면 실패한다', () {
      final json = prod();
      (json['app']! as Map<String, Object?>)['startUrl'] =
          'http://example.com/';
      expect(
        () => AppConfig.fromJson(json),
        _throwsConfigError('prod의 startUrl은 https여야 합니다'),
      );
    });

    test('알 수 없는 enum 값은 경로와 함께 실패한다', () {
      final json = prod();
      json['splash'] = {'closeTrigger': 'onDomReady'};
      expect(
        () => AppConfig.fromJson(json),
        throwsA(
          isA<AppConfigException>().having(
            (e) => e.message,
            'message',
            contains(r'$.splash.closeTrigger'),
          ),
        ),
      );
    });

    test('타입이 틀리면 실패한다', () {
      final json = prod();
      json['popup'] = {'maxDepth': '5'};
      expect(
        () => AppConfig.fromJson(json),
        _throwsConfigError(r'$.popup.maxDepth는 integer이어야 합니다'),
      );
    });

    test('강제 업데이트를 켜면 checkUrl이 필요하다', () {
      final json = prod();
      json['extras'] = {
        'forceUpdate': {'enabled': true},
      };
      expect(
        () => AppConfig.fromJson(json),
        _throwsConfigError(r'$.extras.forceUpdate.checkUrl이 필요합니다'),
      );
    });
  });

  group('권한 (#3)', () {
    PermissionsConfig permissions(List<String> requestOnLaunch) =>
        AppConfig.fromJson({
          'flavor': 'dev',
          'app': {
            'name': 'Test',
            'startUrl': 'https://example.com/',
            'allowedHosts': ['example.com'],
          },
          'permissions': {'requestOnLaunch': requestOnLaunch},
        }).permissions;

    test('photos는 설정 검증을 통과하고 iOS에서는 설정 순서대로 요청한다', () {
      final config = permissions(['camera', 'photos', 'location']);
      expect(config.requestOnLaunchOn(TargetPlatform.iOS), [
        AppPermission.camera,
        AppPermission.photos,
        AppPermission.location,
      ]);
    });

    test('Android에서는 photos를 건너뛰고 순서를 유지한다', () {
      final config = permissions(['camera', 'photos', 'location']);
      expect(config.requestOnLaunchOn(TargetPlatform.android), [
        AppPermission.camera,
        AppPermission.location,
      ]);
    });

    test('Android에서 photos만 있으면 요청할 권한이 없다', () {
      expect(
        permissions(['photos']).requestOnLaunchOn(TargetPlatform.android),
        isEmpty,
      );
    });

    test('돌려준 목록은 수정할 수 없다', () {
      final list = permissions(['camera'])
          .requestOnLaunchOn(TargetPlatform.android);
      expect(() => list.add(AppPermission.photos), throwsUnsupportedError);
    });

    test('photos는 iOS에서만 요청할 수 있다', () {
      for (final platform in TargetPlatform.values) {
        expect(
          AppPermission.photos.isRequestableOn(platform),
          platform == TargetPlatform.iOS,
          reason: platform.name,
        );
      }
    });

    test('photos 외 권한은 Android와 iOS에서 모두 요청할 수 있다', () {
      for (final p in AppPermission.values.where(
        (p) => p != AppPermission.photos,
      )) {
        for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
          expect(p.isRequestableOn(platform), isTrue, reason: '$p $platform');
        }
      }
    });

    group('Android 매니페스트', () {
      // open_filex가 추가하는 미디어·저장소 권한. Play 사진·동영상 권한 정책 때문에 제거한다.
      // READ_MEDIA_IMAGES 제거는 Android에서 photos를 요청하지 않는 근거다. 제거를 풀면
      // photos의 Android 동작(API 33+ READ_MEDIA_IMAGES, 32 이하는 READ_EXTERNAL_STORAGE
      // 제거도 풀고 storage로 매핑)을 함께 정한다.
      const removed = [
        'READ_MEDIA_IMAGES',
        'READ_MEDIA_VIDEO',
        'READ_MEDIA_AUDIO',
        'READ_EXTERNAL_STORAGE',
        'WRITE_EXTERNAL_STORAGE',
      ];

      /// 주석을 뺀 뒤 `<uses-permission>`·`<uses-permission-sdk-23>` 선언을
      /// 권한 이름 → 선언 목록으로 읽는다. 같은 권한을 여러 번 선언해도 모두 남긴다.
      Map<String, List<({String tag, Map<String, String> attrs})>> declarations(
        File manifest,
      ) {
        final xml = manifest.readAsStringSync().replaceAll(
          RegExp('<!--.*?-->', dotAll: true),
          '',
        );
        final result =
            <String, List<({String tag, Map<String, String> attrs})>>{};
        for (final m in RegExp(
          r'<(uses-permission(?:-sdk-23|-sdk-m)?)(?=[\s/>])([^>]*)>',
        ).allMatches(xml)) {
          final attrs = {
            for (final a in RegExp(
              r'''([\w:.-]+)\s*=\s*(["'])(.*?)\2''',
            ).allMatches(m.group(2)!))
              a.group(1)!: a.group(3)!,
          };
          final name = attrs['android:name'];
          if (name == null) {
            fail('${manifest.path}: android:name이 없는 선언 ${m.group(0)}');
          }
          result
              .putIfAbsent(
                name.replaceFirst('android.permission.', ''),
                () => [],
              )
              .add((tag: m.group(1)!, attrs: attrs));
        }
        return result;
      }

      /// [decls]가 모두 selector 없는 `<uses-permission tools:node="remove">`인지 확인한다.
      /// `tools:node="remove"`는 같은 요소 타입만 지우고, selector가 있으면 그 라이브러리 것만 지운다.
      void expectOnlyRemoval(
        String where,
        List<({String tag, Map<String, String> attrs})> decls,
      ) {
        for (final d in decls) {
          expect(d.tag, 'uses-permission', reason: where);
          expect(d.attrs['tools:node'], 'remove', reason: where);
          expect(d.attrs.containsKey('tools:selector'), isFalse, reason: where);
        }
      }

      test('main 매니페스트가 미디어·저장소 권한을 제거한다', () {
        final declared = declarations(
          File('android/app/src/main/AndroidManifest.xml'),
        );
        for (final name in removed) {
          expect(declared[name], isNotEmpty, reason: name);
          expectOnlyRemoval('main: $name', declared[name]!);
        }
        expect(
          AppPermission.photos.isRequestableOn(TargetPlatform.android),
          isFalse,
        );
      });

      test('다른 source set이 제거한 권한을 다시 선언하지 않는다', () {
        final manifests = Directory('android/app/src')
            .listSync()
            .whereType<Directory>()
            .map((d) => File('${d.path}/AndroidManifest.xml'))
            .where((f) => f.existsSync());
        expect(manifests, isNotEmpty);
        for (final manifest in manifests) {
          final declared = declarations(manifest);
          for (final name in removed) {
            expectOnlyRemoval('${manifest.path}: $name', declared[name] ?? []);
          }
        }
      });
    });
  });

  group('모르는 키 (#4)', () {
    /// 보고된 경로 목록이 정확히 [paths]인지 본다 (정상 키가 함께 보고되는 회귀 방지).
    Matcher unknownKeys(List<String> paths) =>
        _throwsConfigError('스키마에 없는 키: ${paths.join(', ')}');

    Map<String, Object?> sub(Map<String, Object?> json, String key) =>
        json[key]! as Map<String, Object?>;

    test('prod 설정의 secureScreen 오타는 무시되지 않고 실패한다', () {
      final json = readConfigJson(Flavor.prod);
      final network = sub(json, 'network');
      network['secureScren'] = network.remove('secureScreen');
      expect(
        () => AppConfig.fromJson(json),
        unknownKeys([r'$.network.secureScren']),
      );
    });

    test('필수 키 오타는 "필요합니다"가 아니라 오타 위치를 알린다', () {
      final json = readConfigJson(Flavor.dev);
      final app = sub(json, 'app');
      app['startURL'] = app.remove('startUrl');
      json['flavr'] = json.remove('flavor');
      expect(
        () => AppConfig.fromJson(json),
        unknownKeys([r'$.app.startURL', r'$.flavr']),
      );
    });

    test('같은 설정의 타입·형식 오류보다 오타를 먼저 알린다', () {
      final json = readConfigJson(Flavor.dev);
      sub(json, 'popup')['maxDepth'] = '5';
      sub(json, 'splash')['bgColor'] = {'light': 'white', 'drak': '#000000'};
      sub(json, 'network')['secureScren'] = true;
      expect(
        () => AppConfig.fromJson(json),
        unknownKeys([r'$.splash.bgColor.drak', r'$.network.secureScren']),
      );
    });

    test('강제 업데이트 checkUrl 오타는 checkUrl 누락보다 먼저 알린다', () {
      final json = readConfigJson(Flavor.dev);
      json['extras'] = {
        'forceUpdate': {'enabled': true, 'chekUrl': 'https://example.com/'},
      };
      expect(
        () => AppConfig.fromJson(json),
        unknownKeys([r'$.extras.forceUpdate.chekUrl']),
      );
    });

    test('강제 업데이트를 켜고 checkUrl을 주면 읽는다', () {
      final json = readConfigJson(Flavor.dev);
      json['extras'] = {
        'forceUpdate': {'enabled': true, 'checkUrl': 'https://example.com/v'},
      };
      final config = AppConfig.fromJson(json);
      expect(config.extras.forceUpdate.enabled, isTrue);
      expect(
        config.extras.forceUpdate.checkUrl,
        Uri.parse('https://example.com/v'),
      );
    });

    test('생략한 object 안의 키도 검사한다', () {
      final json = readConfigJson(Flavor.dev)
        ..['dialog'] = {
          'labels': {'okay': '확인'},
        };
      expect(
        () => AppConfig.fromJson(json),
        unknownKeys([r'$.dialog.labels.okay']),
      );
    });

    test('값이 null인 모르는 키도 실패한다', () {
      final json = readConfigJson(Flavor.dev)..['popups'] = null;
      expect(() => AppConfig.fromJson(json), unknownKeys([r'$.popups']));
    });

    test('아는 키에 null을 적으면 기본값을 쓰지 않고 실패한다', () {
      for (final (group, key) in [
        ('network', 'secureScreen'),
        (null, 'splash'),
      ]) {
        final json = readConfigJson(Flavor.prod);
        (group == null ? json : sub(json, group))[key] = null;
        final path = group == null ? '\$.$key' : '\$.$group.$key';
        expect(
          () => AppConfig.fromJson(json),
          _throwsConfigError('$path: null은 쓸 수 없습니다 (생략하면 기본값을 씁니다)'),
          reason: path,
        );
      }
    });

    test(r'$schema 키는 허용하고 타입은 검사한다', () {
      final json = readConfigJson(Flavor.dev);
      expect(json[r'$schema'], isNotNull);
      expect(() => AppConfig.fromJson(json), returnsNormally);
      json[r'$schema'] = 1;
      expect(
        () => AppConfig.fromJson(json),
        _throwsConfigError(r'$.$schema는 string이어야 합니다'),
      );
    });

    test("'.'이 든 모르는 키는 괄호 표기로 알린다", () {
      final json = readConfigJson(Flavor.dev)..['app.name'] = 'U4';
      expect(() => AppConfig.fromJson(json), unknownKeys([r'$["app.name"]']));
    });

    test('모델이 읽는 키와 스키마의 키가 object마다 정확히 같다', () {
      final schema = jsonDecode(
        File('config/app_config.schema.json').readAsStringSync(),
      ) as Map<String, Object?>;
      expect(AppConfig.knownKeys, equals(_schemaKeys(schema)));
    });

    test('config/의 설정 파일이 Flavor와 일치한다 (CI 스키마 검증 대상)', () {
      final files = Directory('config')
          .listSync()
          .map((f) => f.uri.pathSegments.last)
          .where((n) => n.startsWith('app_config.') && n.endsWith('.json'))
          .where((n) => n != 'app_config.schema.json')
          .map((n) => 'config/$n')
          .toSet();
      expect(files, Flavor.values.map((f) => f.assetPath).toSet());
    });
  });
}

/// 스키마의 object 경로별 속성 이름 (예: `$.network` → `{secureScreen, ...}`).
///
/// `properties`로 이어지는 모든 object가 `additionalProperties: false`인지도 확인한다. 로더는 모르는
/// 키를 항상 거부하므로, 자유 키를 허용하는 object가 생기면 둘이 어긋난다.
Map<String, Set<String>> _schemaKeys(Map<String, Object?> root) {
  final defs = root[r'$defs']! as Map<String, Object?>;
  Map<String, Object?> resolve(Map<String, Object?> s) {
    final ref = s[r'$ref'];
    if (ref is! String) return s;
    const prefix = r'#/$defs/';
    expect(ref, startsWith(prefix));
    return resolve(defs[ref.substring(prefix.length)]! as Map<String, Object?>);
  }

  final out = <String, Set<String>>{};
  void walk(Map<String, Object?> s, String path) {
    s = resolve(s);
    // 로더와 이 순회는 properties로 이어지는 object만 다룬다. 배열 원소 object나
    // 조합 키워드로 키를 정의하면 둘 다 놓치므로 테스트에서 막는다.
    for (final k in ['allOf', 'anyOf', 'oneOf']) {
      expect(s.containsKey(k), isFalse, reason: '$path: $k 미지원');
    }
    final items = s['items'];
    if (items is Map<String, Object?>) {
      expect(resolve(items)['type'], isNot('object'), reason: '$path[]');
    }
    if (s['type'] != 'object') return;
    expect(s['additionalProperties'], isFalse, reason: path);
    final props = (s['properties'] ?? const {}) as Map<String, Object?>;
    out[path] = props.keys.toSet();
    for (final e in props.entries) {
      walk(e.value! as Map<String, Object?>, '$path.${e.key}');
    }
  }

  walk(root, r'$');
  return out;
}

/// 메시지가 정확히 [message]인 [AppConfigException]을 던지는지 본다.
Matcher _throwsConfigError(String message) => throwsA(
  isA<AppConfigException>().having((e) => e.message, 'message', message),
);
