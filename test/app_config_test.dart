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
        throwsA(isA<AppConfigException>()),
      );
    });

    test('prod의 startUrl이 http면 실패한다', () {
      final json = prod();
      (json['app']! as Map<String, Object?>)['startUrl'] =
          'http://example.com/';
      expect(
        () => AppConfig.fromJson(json),
        throwsA(isA<AppConfigException>()),
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
        throwsA(isA<AppConfigException>()),
      );
    });

    test('강제 업데이트를 켜면 checkUrl이 필요하다', () {
      final json = prod();
      json['extras'] = {
        'forceUpdate': {'enabled': true},
      };
      expect(
        () => AppConfig.fromJson(json),
        throwsA(isA<AppConfigException>()),
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
}
