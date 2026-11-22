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
      // 목록 원본은 tool/android_forbidden_permissions.txt이고 APK 권한 검사
      // (tool/check_android_permissions.sh, #36)와 함께 쓴다. 파일이 없어도 이 그룹만
      // 실패하도록 테스트 안에서 읽는다.
      List<String> forbidden() =>
          File('tool/android_forbidden_permissions.txt')
              .readAsLinesSync()
              .map((l) => l.replaceFirst(RegExp('#.*'), '').trim())
              .where((l) => l.isNotEmpty)
              .toList();

      // 파일에서 항목이 빠지면 두 검사가 함께 조용히 약해지므로 내용을 여기서 고정한다.
      test('금지 권한 목록이 미디어·저장소 권한 5개다', () {
        expect(forbidden(), [
          'READ_MEDIA_IMAGES',
          'READ_MEDIA_VIDEO',
          'READ_MEDIA_AUDIO',
          'READ_EXTERNAL_STORAGE',
          'WRITE_EXTERNAL_STORAGE',
        ]);
      });

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

      /// [decls]가 모두 selector 없는 `tools:node="remove"` 선언인지 확인한다.
      /// `tools:node="remove"`는 같은 요소 타입만 지우고, selector가 있으면 그 라이브러리 것만 지운다.
      /// 그래서 라이브러리가 `<uses-permission-sdk-23>`으로 넣으면 같은 태그로 제거해야 한다 (#36).
      void expectOnlyRemoval(
        String where,
        List<({String tag, Map<String, String> attrs})> decls,
      ) {
        for (final d in decls) {
          expect(
            d.tag,
            isIn(['uses-permission', 'uses-permission-sdk-23']),
            reason: where,
          );
          expect(d.attrs['tools:node'], 'remove', reason: where);
          expect(d.attrs.containsKey('tools:selector'), isFalse, reason: where);
        }
      }

      test('main 매니페스트가 미디어·저장소 권한을 제거한다', () {
        final declared = declarations(
          File('android/app/src/main/AndroidManifest.xml'),
        );
        for (final name in forbidden()) {
          final decls = declared[name] ?? [];
          expect(
            decls.where((d) => d.tag == 'uses-permission'),
            isNotEmpty,
            reason: name,
          );
          expectOnlyRemoval('main: $name', decls);
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
        final names = forbidden();
        for (final manifest in manifests) {
          final declared = declarations(manifest);
          for (final name in names) {
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

  group('범위·형식 (#5)', () {
    final schema = jsonDecode(
      File('config/app_config.schema.json').readAsStringSync(),
    ) as Map<String, Object?>;
    // 순회 안의 expect가 테스트 안에서 돌도록 처음 쓸 때 만든다.
    late final fields = _schemaFields(schema);

    /// 최소 dev 설정에서 [path](`$` 다음 키들)의 값만 [value]로 바꾼다.
    Map<String, Object?> withValue(List<String> path, Object? value) {
      final json = jsonDecode(
        jsonEncode({
          'flavor': 'dev',
          'app': {
            'name': 'Test',
            'startUrl': 'https://example.com/',
            'allowedHosts': ['example.com'],
          },
        }),
      ) as Map<String, Object?>;
      var map = json;
      for (final k in path.take(path.length - 1)) {
        map =
            map.putIfAbsent(k, () => <String, Object?>{})!
                as Map<String, Object?>;
      }
      map[path.last] = value;
      return json;
    }

    String pathOf(List<String> path) => '\$.${path.join('.')}';

    Matcher throwsAt(String path) => throwsA(
      isA<AppConfigException>().having(
        (e) => e.message,
        'message',
        startsWith('$path: '),
      ),
    );

    test('이슈 재현: maxDepth 0과 maxWaitMs -1은 로딩 단계에서 실패한다', () {
      expect(
        () => AppConfig.fromJson(withValue(['popup', 'maxDepth'], 0)),
        _throwsConfigError(r'$.popup.maxDepth: 1 이상 10 이하여야 합니다 (0)'),
      );
      expect(
        () => AppConfig.fromJson(withValue(['splash', 'maxWaitMs'], -1)),
        _throwsConfigError(r'$.splash.maxWaitMs: 0 이상 3600000 이하여야 합니다 (-1)'),
      );
    });

    test('스키마의 minimum·maximum 경계를 로더도 똑같이 검사한다', () {
      final ranged = fields.where(
        (f) =>
            f.schema.containsKey('minimum') || f.schema.containsKey('maximum'),
      );
      // ms 4개 + maxDepth + maxAttempts. 순회가 필드를 놓치는 회귀 방지.
      // ms 상한은 Duration 넘침(음수 지연) 방지용이다 (R1).
      expect(ranged.map((f) => pathOf(f.path)), hasLength(6));
      for (final f in ranged) {
        final where = pathOf(f.path);
        expect(f.schema['type'], 'integer', reason: where);
        for (final (bound, step) in [('minimum', -1), ('maximum', 1)]) {
          final limit = f.schema[bound] as int?;
          if (limit == null) {
            // 스키마에 경계가 없으면 로더도 막지 않아야 한다 (R2: 로더 쪽만
            // 상한을 넣는 드리프트).
            final far = step * (1 << 40);
            expect(
              () => AppConfig.fromJson(withValue(f.path, far)),
              returnsNormally,
              reason: '$where = $far',
            );
            continue;
          }
          expect(
            () => AppConfig.fromJson(withValue(f.path, limit)),
            returnsNormally,
            reason: '$where = $limit',
          );
          expect(
            () => AppConfig.fromJson(withValue(f.path, limit + step)),
            throwsAt(where),
            reason: '$where = ${limit + step}',
          );
        }
      }
    });

    test('uniqueItems 배열은 중복을 거부하고, 아닌 배열은 허용한다', () {
      final arrays = fields.where((f) => f.schema['type'] == 'array').toList();
      expect(arrays, hasLength(4));
      for (final f in arrays) {
        final where = pathOf(f.path);
        final items = f.items!;
        final sample = switch (items) {
          {'enum': [final first, ...]} => first,
          {'pattern': final _} => 'example.com',
          _ => fail('$where: 원소 샘플 값을 정할 수 없습니다'),
        };
        final json = withValue(f.path, [sample, sample]);
        if (f.schema['uniqueItems'] == true) {
          expect(
            () => AppConfig.fromJson(json),
            _throwsConfigError('$where[1]: 중복된 값 (${jsonEncode(sample)})'),
          );
        } else {
          expect(
            () => AppConfig.fromJson(json),
            returnsNormally,
            reason: where,
          );
        }
      }
    });

    test('requestOnLaunch 중복은 권한 목록을 만들기 전에 실패한다', () {
      expect(
        () => AppConfig.fromJson(
          withValue(['permissions', 'requestOnLaunch'], ['camera', 'camera']),
        ),
        _throwsConfigError(
          r'$.permissions.requestOnLaunch[1]: 중복된 값 ("camera")',
        ),
      );
    });

    test('중복보다 원소 오류를 먼저 알린다', () {
      expect(
        () => AppConfig.fromJson(
          withValue(['permissions', 'requestOnLaunch'], ['bogus', 'bogus']),
        ),
        _throwsConfigError(
          r'$.permissions.requestOnLaunch: 알 수 없는 값 "bogus" '
          '(location / camera / microphone / photos / notification)',
        ),
      );
      expect(
        () => AppConfig.fromJson(
          withValue(['app', 'allowedHosts'], ['BAD', 'BAD']),
        ),
        _throwsConfigError(r'$.app.allowedHosts[0]: 호스트 형식 오류 ("BAD")'),
      );
    });

    test('startUrl은 소문자 http·https로 시작해야 한다 (모든 flavor)', () {
      for (final url in [
        'ftp://example.com/',
        'file://example.com/a',
        'HTTPS://example.com/',
        'wss://example.com/',
      ]) {
        expect(
          () => AppConfig.fromJson(withValue(['app', 'startUrl'], url)),
          _throwsConfigError(
            '\$.app.startUrl: http 또는 https URL이어야 합니다 (${jsonEncode(url)})',
          ),
          reason: url,
        );
      }
      for (final (key, url) in [
        (['app', 'startUrl'], 'https://example.com:99999999999999999999/'),
        (['app', 'startUrl'], 'https://example.com:-1/'),
        (['extras', 'forceUpdate', 'checkUrl'], 'https://example.com:-1/'),
        (
          ['extras', 'forceUpdate', 'checkUrl'],
          'https://example.com:99999999999999999999/',
        ),
      ]) {
        // 포트가 int 범위를 넘으면 Uri.tryParse가 FormatException을 던진다 (R2).
        expect(
          () => AppConfig.fromJson(withValue(key, url)),
          _throwsConfigError('${pathOf(key)}: URL 형식 오류 (${jsonEncode(url)})'),
          reason: url,
        );
      }
      for (final url in ['http://localhost:8080/', 'https://example.com/a']) {
        expect(
          AppConfig.fromJson(withValue(['app', 'startUrl'], url)).app.startUrl,
          Uri.parse(url),
        );
      }
    });

    test('호스트 목록은 hostPattern을 따른다', () {
      final hostLists = fields.where(
        (f) => f.items?['pattern'] == AppConfig.schemaPatterns.host,
      );
      expect(hostLists, hasLength(3));
      for (final f in hostLists) {
        final where = pathOf(f.path);
        for (final ok in ['example.com', '*.example.com', 'localhost:8080']) {
          expect(
            () => AppConfig.fromJson(withValue(f.path, [ok])),
            returnsNormally,
            reason: '$where $ok',
          );
        }
        for (final bad in [
          'Example.com',
          'https://example.com',
          'example.com/',
          '*example.com',
          'a.*.example.com',
          '',
          'example..com',
          '-example.com',
          'example.com:123456',
        ]) {
          expect(
            () => AppConfig.fromJson(withValue(f.path, ['example.com', bad])),
            _throwsConfigError('$where[1]: 호스트 형식 오류 (${jsonEncode(bad)})'),
            reason: '$where "$bad"',
          );
        }
      }
    });

    test('제약 없는 문자열 필드는 빈 문자열을 받는다', () {
      // 로더 쪽에만 minLength 등을 넣는 드리프트 방지 (R2).
      const constraintKeys = {
        'minLength',
        'pattern',
        'format',
        'enum',
        'const',
      };
      final plain = fields.where(
        (f) =>
            f.schema['type'] == 'string' &&
            f.path.first != r'$schema' &&
            f.schema.keys.toSet().intersection(constraintKeys).isEmpty,
      );
      // userAgentSuffix, splash.image, dialog.labels 3개, offline·errorPage, locale
      expect(plain, hasLength(8));
      for (final f in plain) {
        expect(
          () => AppConfig.fromJson(withValue(f.path, '')),
          returnsNormally,
          reason: pathOf(f.path),
        );
      }
    });

    test('minLength 문자열에 빈 문자열을 넣으면 실패한다', () {
      final nonEmpty = fields.where((f) => f.schema.containsKey('minLength'));
      expect(nonEmpty.map((f) => pathOf(f.path)), [r'$.app.name']);
      for (final f in nonEmpty) {
        expect(f.schema['minLength'], 1);
        expect(
          () => AppConfig.fromJson(withValue(f.path, '')),
          _throwsConfigError('${pathOf(f.path)}: 빈 문자열은 쓸 수 없습니다'),
        );
      }
    });

    test('로더의 pattern 문자열이 스키마와 같다', () {
      final defs = schema[r'$defs']! as Map<String, Object?>;
      expect(
        (defs['hostPattern']! as Map)['pattern'],
        AppConfig.schemaPatterns.host,
      );
      expect(
        (defs['color']! as Map)['pattern'],
        AppConfig.schemaPatterns.color,
      );
      final startUrl = fields.singleWhere(
        (f) => pathOf(f.path) == r'$.app.startUrl',
      );
      expect(startUrl.schema['pattern'], AppConfig.schemaPatterns.httpUrl);
    });

    test('스키마는 로더가 검사하는 키워드만 쓴다', () {
      // 새 키워드(maxLength, exclusiveMinimum 등)를 쓰면 로더 검사를 함께 넣고
      // 이 목록과 docs/phase-1-setup.md 5장을 고친다.
      const supported = {
        // 주석·메타데이터
        r'$schema', r'$id', 'title', 'description', 'default',
        // 구조
        r'$defs', r'$ref', 'type', 'properties', 'additionalProperties',
        'required', 'items', 'if', 'then',
        // 값 제약
        'enum', 'const', 'minimum', 'maximum', 'minLength', 'minItems',
        'uniqueItems', 'pattern', 'format',
      };
      final used = <String>{};
      void walk(Object? node) {
        if (node is! Map<String, Object?>) return;
        used.addAll(node.keys);
        for (final k in ['items', 'if', 'then']) {
          walk(node[k]);
        }
        for (final k in ['properties', r'$defs']) {
          (node[k] as Map<String, Object?>?)?.values.forEach(walk);
        }
      }

      walk(schema);
      expect(used.difference(supported), isEmpty);
    });

    test('enum 필드는 스키마의 값을 모두 받고 다른 값은 거부한다', () {
      final enums = [
        for (final f in fields)
          if (f.schema['enum'] case final List<Object?> values)
            (path: f.path, values: values, array: false)
          else if (f.items?['enum'] case final List<Object?> values)
            (path: f.path, values: values, array: true),
      ];
      // 순회가 필드를 놓치는 회귀 방지 (enum 필드 15개 + requestOnLaunch).
      expect(enums, hasLength(16));
      for (final e in enums) {
        final where = pathOf(e.path);
        for (final v in e.values) {
          expect(
            () => AppConfig.fromJson(withValue(e.path, e.array ? [v] : v)),
            returnsNormally,
            reason: '$where = $v',
          );
        }
        // 모르는 값 오류에 나오는 로더 허용값 목록이 스키마 enum과 같아야 한다.
        // 그래야 스키마에서 값을 빼거나 Dart enum에만 값을 더한 드리프트도 잡는다 (R2).
        const unknown = '__unknown__';
        Object? error;
        try {
          AppConfig.fromJson(withValue(e.path, e.array ? [unknown] : unknown));
        } on AppConfigException catch (x) {
          error = x.message;
        }
        final m = RegExp(
          '^${RegExp.escape(where)}: 알 수 없는 값 "$unknown" \\((.*)\\)\$',
        ).firstMatch('$error');
        expect(m, isNotNull, reason: '$where: $error');
        expect(
          m!.group(1)!.split(' / ').toSet(),
          e.values.toSet(),
          reason: where,
        );
      }
    });

    test('스키마 값 제약 스냅샷이 로더가 검사하도록 맞춘 목록과 같다', () {
      // 스키마에 값 제약을 더하거나 바꾸면 이 스냅샷이 어긋난다. 로더 검사를 함께
      // 넣고(옆 주석의 위치), 위의 경계·중복·형식 테스트가 새 항목을 다루는지 본다.
      // 손으로 적은 목록이라 로더 쪽만 바뀌는 것은 위의 동작 테스트가 잡는다.
      // enum은 위 테스트가 필드마다 확인하므로 조건부(if/then) 밖에서는 뺀다.
      // type·default는 이 스냅샷의 범위가 아니다.
      final host = AppConfig.schemaPatterns.host;
      final color = AppConfig.schemaPatterns.color;
      const ms = {'minimum': 0, 'maximum': 3600000}; // _Reader.millis
      expect(_schemaConstraints(schema), {
        // 필수 키: string()/choice()의 fallback 없음
        r'$ required': ['flavor', 'app'],
        r'$.app required': ['name', 'startUrl', 'allowedHosts'],
        r'$.app.name minLength': 1, // string(minLength:)
        r'$.app.startUrl format': 'uri', // _parseUri (scheme·host만)
        r'$.app.startUrl pattern': AppConfig.schemaPatterns.httpUrl, // httpUri
        r'$.app.allowedHosts minItems': 1, // AppConfig._validate
        r'$.app.allowedHosts uniqueItems': true, // hosts
        r'$.app.allowedHosts[] pattern': host, // hosts
        r'$.app.externalHosts uniqueItems': true,
        r'$.app.externalHosts[] pattern': host,
        for (final k in [
          'minDisplayMs',
          'delayAfterLoadMs',
          'maxWaitMs',
          'fadeOutMs',
        ])
          for (final MapEntry(:key, :value) in ms.entries)
            '\$.splash.$k $key': value,
        // ThemedColor → _Reader.color
        for (final c in [
          'splash.bgColor',
          'systemUi.statusBar.color',
          'systemUi.navigationBar.color',
        ])
          for (final t in ['light', 'dark']) '\$.$c.$t pattern': color,
        r'$.popup.maxDepth minimum': 1, // integer(min:, max:)
        r'$.popup.maxDepth maximum': 10,
        r'$.permissions.requestOnLaunch uniqueItems': true, // choices(unique:)
        r'$.network.retry.maxAttempts minimum': 0, // integer(min:)
        r'$.extras.deeplink.domains uniqueItems': true, // hosts
        r'$.extras.deeplink.domains[] pattern': host,
        r'$.extras.forceUpdate.checkUrl format': 'uri', // optUri
        // 강제 업데이트: AppConfig._validate
        r'if($.extras.forceUpdate) $.extras.forceUpdate required': ['enabled'],
        r'if($.extras.forceUpdate) $.extras.forceUpdate.enabled const': true,
        r'then($.extras.forceUpdate) $.extras.forceUpdate required': [
          'checkUrl',
        ],
        // prod 제약: AppConfig._validate
        r'if($) $ required': ['flavor'],
        r'if($) $.flavor const': 'prod',
        r'then($) $.app.startUrl pattern': '^https://',
        r'then($) $.network.allowHttp const': false,
        r'then($) $.network.ignoreSslErrors const': false,
        r'then($) $.network.debuggable const': false,
      });
    });
  });
}

/// 스키마의 값 필드(object가 아닌 속성)와 경로. `$ref`는 풀어 둔다.
List<
  ({
    List<String> path,
    Map<String, Object?> schema,
    Map<String, Object?>? items,
  })
>
_schemaFields(Map<String, Object?> root) {
  Map<String, Object?> resolve(Map<String, Object?> s) => _resolveRef(root, s);

  final out =
      <
        ({
          List<String> path,
          Map<String, Object?> schema,
          Map<String, Object?>? items,
        })
      >[];
  void walk(Map<String, Object?> s, List<String> path) {
    s = resolve(s);
    if (s['type'] == 'object') {
      final props = (s['properties'] ?? const {}) as Map<String, Object?>;
      for (final e in props.entries) {
        walk(e.value! as Map<String, Object?>, [...path, e.key]);
      }
      return;
    }
    final items = s['items'];
    out.add((
      path: path,
      schema: s,
      items: items is Map<String, Object?> ? resolve(items) : null,
    ));
  }

  walk(root, []);
  return out;
}

/// [s]의 `$ref`(`#/$defs/...`)를 풀어 참조 대상과 합친다.
///
/// 2020-12에서 `$ref`와 옆 키는 둘 다 적용된다(AND). 단순히 합치면 옆 키가
/// 참조 대상을 덮어써 의미가 달라지므로, 옆 키는 주석(description, default)만 허용한다.
Map<String, Object?> _resolveRef(
  Map<String, Object?> root,
  Map<String, Object?> s,
) {
  final ref = s[r'$ref'];
  if (ref is! String) return s;
  const prefix = r'#/$defs/';
  expect(ref, startsWith(prefix));
  expect(
    s.keys.toSet().difference({r'$ref', 'description', 'default'}),
    isEmpty,
    reason: '$ref 옆의 값 제약은 지원하지 않습니다',
  );
  final defs = root[r'$defs']! as Map<String, Object?>;
  final target = _resolveRef(
    root,
    defs[ref.substring(prefix.length)]! as Map<String, Object?>,
  );
  return {...target, ...s}..remove(r'$ref');
}

/// 스키마 전체의 값 제약을 `<위치> <키워드>` → 값으로 모은다.
///
/// - 위치는 `$.a.b`, 배열 원소는 `$.a.b[]`이다.
/// - `if`/`then` 안의 제약은 `if(<조건 위치>) `·`then(<조건 위치>) ` 접두사를 붙인다.
/// - 조건부 안에서는 구조 키워드를 뺀 모든 키를 모은다. 그 밖에서는 enum·type·
///   additionalProperties를 뺀 값 제약만 모은다 (additionalProperties는 #4 테스트가 본다).
Map<String, Object?> _schemaConstraints(Map<String, Object?> root) {
  const valueKeywords = {
    'required',
    'const',
    'minimum',
    'maximum',
    'minLength',
    'minItems',
    'uniqueItems',
    'pattern',
    'format',
  };
  // 조건부 안에서는 additionalProperties도 기록한다 (prod 키를 막는 의미 변화, R2).
  const structural = {'properties', 'items', 'if', 'then', 'description'};
  final out = <String, Object?>{};
  void walk(Map<String, Object?> s, String path, String ctx) {
    s = _resolveRef(root, s);
    for (final MapEntry(:key, :value) in s.entries) {
      final record = ctx.isEmpty
          ? valueKeywords.contains(key)
          : !structural.contains(key);
      if (record) out['$ctx$path $key'] = value;
    }
    if (s['properties'] case final Map<String, Object?> props) {
      for (final MapEntry(:key, :value) in props.entries) {
        walk(value! as Map<String, Object?>, '$path.$key', ctx);
      }
    }
    if (s['items'] case final Map<String, Object?> items) {
      walk(items, '$path[]', ctx);
    }
    for (final k in ['if', 'then']) {
      if (s[k] case final Map<String, Object?> branch) {
        expect(ctx, isEmpty, reason: '$path: 중첩된 if/then 미지원');
        walk(branch, path, '$k($path) ');
      }
    }
  }

  walk(root, r'$', '');
  return out;
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
