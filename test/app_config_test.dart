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

    test('photos는 설정 검증을 통과하고 원래 목록에 남는다', () {
      final config = permissions(['camera', 'photos', 'location']);
      expect(config.requestOnLaunch, [
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

    test('iOS에서는 설정한 권한을 모두 요청한다', () {
      final config = permissions(['camera', 'photos', 'location']);
      expect(
        config.requestOnLaunchOn(TargetPlatform.iOS),
        config.requestOnLaunch,
      );
    });

    test('Android에서 photos만 있으면 요청할 권한이 없다', () {
      expect(
        permissions(['photos']).requestOnLaunchOn(TargetPlatform.android),
        isEmpty,
      );
    });

    test('iOS에서는 모든 권한을 요청할 수 있다', () {
      for (final p in AppPermission.values) {
        expect(p.isRequestableOn(TargetPlatform.iOS), isTrue, reason: p.name);
      }
    });

    test('Android에서 요청할 수 없는 권한은 photos뿐이다', () {
      expect(
        AppPermission.values.where(
          (p) => !p.isRequestableOn(TargetPlatform.android),
        ),
        [AppPermission.photos],
      );
    });

    test('Android 매니페스트가 사진 권한을 제거하는 것과 일치한다', () {
      // 매니페스트에서 제거를 풀면 photos를 Android에서도 요청하도록 함께 바꿔야 한다.
      final manifest = File('android/app/src/main/AndroidManifest.xml')
          .readAsStringSync();
      for (final name in ['READ_MEDIA_IMAGES', 'READ_EXTERNAL_STORAGE']) {
        expect(
          manifest,
          matches(
            RegExp(
              'android:name="android\\.permission\\.$name"\\s+'
              'tools:node="remove"',
            ),
          ),
          reason: name,
        );
      }
      expect(
        AppPermission.photos.isRequestableOn(TargetPlatform.android),
        isFalse,
      );
    });
  });
}
