import 'dart:convert';
import 'dart:io';

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

  group('모르는 키 (#4)', () {
    Matcher unknownKeys(List<String> paths) => throwsA(
      isA<AppConfigException>().having(
        (e) => e.message,
        'message',
        allOf([contains('스키마에 없는 키'), ...paths.map(contains)]),
      ),
    );

    test('prod 설정의 secureScreen 오타는 무시되지 않고 실패한다', () {
      final json = readConfigJson(Flavor.prod);
      final network = json['network']! as Map<String, Object?>;
      network['secureScren'] = network.remove('secureScreen');
      expect(
        () => AppConfig.fromJson(json),
        unknownKeys([r'$.network.secureScren']),
      );
    });

    test('최상위와 깊은 object의 모르는 키를 경로와 함께 모두 알린다', () {
      final json = readConfigJson(Flavor.dev);
      json['flavr'] = 'dev';
      json['splash'] = {
        'bgColor': {'lite': '#FFFFFF'},
      };
      json['network'] = {
        'retry': {'maxAttemps': 1},
      };
      expect(
        () => AppConfig.fromJson(json),
        unknownKeys([
          r'$.flavr',
          r'$.splash.bgColor.lite',
          r'$.network.retry.maxAttemps',
        ]),
      );
    });

    test('값이 null인 모르는 키도 실패한다', () {
      final json = readConfigJson(Flavor.dev)..['popups'] = null;
      expect(() => AppConfig.fromJson(json), unknownKeys([r'$.popups']));
    });

    test('다른 검증 오류보다 오타를 먼저 알린다', () {
      final json = readConfigJson(Flavor.dev);
      json['extras'] = {
        'forceUpdate': {'enabled': true, 'chekUrl': 'https://example.com/'},
      };
      expect(
        () => AppConfig.fromJson(json),
        unknownKeys([r'$.extras.forceUpdate.chekUrl']),
      );
    });

    test(r'$schema 키는 허용하고 타입은 검사한다', () {
      final json = readConfigJson(Flavor.dev);
      expect(json[r'$schema'], isNotNull);
      expect(() => AppConfig.fromJson(json), returnsNormally);
      json[r'$schema'] = 1;
      expect(
        () => AppConfig.fromJson(json),
        throwsA(isA<AppConfigException>()),
      );
    });

    test('스키마에 정의된 키는 모델이 모두 읽는다 (스키마와 모델 일치)', () {
      final schema = jsonDecode(
        File('config/app_config.schema.json').readAsStringSync(),
      ) as Map<String, Object?>;
      final full = _sampleOf(schema, schema)! as Map<String, Object?>;
      // 샘플이 생략 없이 모든 그룹을 담았는지 확인한다.
      expect(
        full.keys.toSet(),
        (schema['properties']! as Map<String, Object?>).keys.toSet(),
      );
      expect(() => AppConfig.fromJson(full), returnsNormally);
    });
  });
}

/// 스키마 [s]의 모든 속성을 채운 유효한 샘플 값을 만든다.
///
/// 이 프로젝트 스키마가 쓰는 키워드만 다룬다. `default`가 스칼라면 그 값을 쓴다.
Object? _sampleOf(Map<String, Object?> s, Map<String, Object?> root) {
  final ref = s[r'$ref'];
  if (ref is String) {
    const prefix = r'#/$defs/';
    expect(ref, startsWith(prefix));
    final name = ref.substring(prefix.length);
    switch (name) {
      case 'hostPattern':
        return 'example.com';
      case 'color':
        return '#FFFFFF';
    }
    final defs = root[r'$defs']! as Map<String, Object?>;
    return _sampleOf(defs[name]! as Map<String, Object?>, root);
  }
  final defaultValue = s['default'];
  if (defaultValue != null && defaultValue is! Map && defaultValue is! List) {
    return defaultValue;
  }
  if (s['const'] case final Object value) return value;
  if (s['enum'] case final List<Object?> values) return values.first;
  switch (s['type']) {
    case 'object':
      final props = (s['properties'] ?? const {}) as Map<String, Object?>;
      return {
        for (final e in props.entries)
          e.key: _sampleOf(e.value! as Map<String, Object?>, root),
      };
    case 'array':
      final items = s['items'] as Map<String, Object?>?;
      return items == null ? const [] : [_sampleOf(items, root)];
    case 'boolean':
      return false;
    case 'integer':
      return s['minimum'] ?? 0;
    case 'string':
      return s['format'] == 'uri' ? 'https://example.com/' : 'x';
  }
  fail('샘플을 만들 수 없는 스키마: $s');
}
