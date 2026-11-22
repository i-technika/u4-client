import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:u4/config/app_config.dart';
import 'package:u4/main.dart';

import 'helpers.dart';

/// [path]를 요청하면 [text]를 돌려주는 asset bundle.
///
/// 다른 키는 실제 bundle처럼 `FlutterError`로 실패하므로, `load`가 엉뚱한
/// 경로를 읽으면 테스트가 실패한다.
class _StringBundle extends CachingAssetBundle {
  _StringBundle(this.path, this.text);

  final String path;
  final String text;

  @override
  Future<ByteData> load(String key) async {
    if (key != path) throw FlutterError('Unable to load asset: "$key".');
    return ByteData.sublistView(utf8.encode(text));
  }
}

Matcher _configError(String message) => isA<AppConfigException>().having(
  (e) => e.message,
  'message',
  contains(message),
);

Matcher _configErrorExact(String message) =>
    isA<AppConfigException>().having((e) => e.message, 'message', message);

/// dev 설정을 [edit]로 고쳐 dev 경로로 돌려주는 bundle.
_StringBundle _bundleWith(void Function(Map<String, Object?> json) edit) {
  final json = readConfigJson(Flavor.dev);
  edit(json);
  return _StringBundle(Flavor.dev.assetPath, jsonEncode(json));
}

void main() {
  testWidgets('설정 확인 화면에 flavor와 앱 이름이 보인다', (tester) async {
    final config = AppConfig.fromJson(readConfigJson(Flavor.dev));
    await tester.pumpWidget(U4App(config: config));

    expect(find.text('U4 DEV'), findsOneWidget);
    expect(find.text('dev'), findsOneWidget);
  });

  group('buildApp', () {
    testWidgets('설정을 읽으면 U4App을 띄운다', (tester) async {
      final devJson = File(Flavor.dev.assetPath).readAsStringSync();
      final app = await buildApp(
        () => AppConfig.load(
          Flavor.dev,
          bundle: _StringBundle(Flavor.dev.assetPath, devJson),
        ),
      );
      await tester.pumpWidget(app);

      expect(app, isA<U4App>());
      expect(find.text('U4 DEV'), findsOneWidget);
    });

    testWidgets('flavor를 정하지 못하면 오류 화면을 띄우고 예외를 보고한다', (tester) async {
      // Flavor.current처럼 load 호출 전에 동기적으로 던지는 경우
      const error = AppConfigException(
        'release 빌드는 --flavor 또는 --dart-define=FLAVOR가 필요합니다',
      );
      final app = await buildApp(() => throw error);
      expect(tester.takeException(), same(error));

      await tester.pumpWidget(app);
      expect(app, isA<ConfigErrorApp>());
      expect(find.text('앱을 시작하지 못했습니다'), findsOneWidget);
      expect(find.text('$error'), findsOneWidget);
    });

    final dev = Flavor.dev.assetPath;
    final cases = <String, (Flavor, _StringBundle, Matcher)>{
      '설정 파일의 flavor가 다르면': (
        Flavor.prod,
        _StringBundle(
          Flavor.prod.assetPath,
          File(Flavor.dev.assetPath).readAsStringSync(),
        ),
        _configError('${Flavor.prod.assetPath}의 flavor가 dev입니다'),
      ),
      'asset이 없으면': (
        Flavor.dev,
        _StringBundle('other.json', '{}'),
        _configError('$dev: asset을 읽지 못함'),
      ),
      'JSON 형식이 깨지면': (
        Flavor.dev,
        _StringBundle(dev, '{"flavor": '),
        _configError('$dev: JSON 형식 오류'),
      ),
      'JSON 최상위가 객체가 아니면': (
        Flavor.dev,
        _StringBundle(dev, '[]'),
        _configError('$dev: 최상위가 object가 아닙니다'),
      ),
      // fromJson의 각 단계(키 검사, 값 읽기, _validate) 오류에 파일 경로가 붙는다.
      '설정에 모르는 키가 있으면': (
        Flavor.dev,
        _bundleWith((json) => json['typo'] = true),
        _configErrorExact('$dev: 스키마에 없는 키: \$.typo'),
      ),
      '설정 값의 타입이 틀리면': (
        Flavor.dev,
        _bundleWith((json) => json['popup'] = {'maxDepth': '5'}),
        _configErrorExact('$dev: \$.popup.maxDepth는 integer이어야 합니다'),
      ),
      '설정 값이 검증을 통과하지 못하면': (
        Flavor.dev,
        _bundleWith(
          (json) => (json['app']! as Map<String, Object?>)['allowedHosts'] = [],
        ),
        _configErrorExact('$dev: \$.app.allowedHosts가 비어 있습니다'),
      ),
    };
    cases.forEach((name, c) {
      final (flavor, bundle, matcher) = c;
      testWidgets('$name 오류 화면을 띄운다', (tester) async {
        final app = await buildApp(
          () => AppConfig.load(flavor, bundle: bundle),
        );
        expect(tester.takeException(), matcher);

        await tester.pumpWidget(app);
        expect(app, isA<ConfigErrorApp>());
        expect(find.text('앱을 시작하지 못했습니다'), findsOneWidget);
      });
    });

    test('AppConfigException이 아닌 예외(코드 버그)는 그대로 던진다', () async {
      await expectLater(
        buildApp(() => throw StateError('bug')),
        throwsStateError,
      );
    });
  });

  testWidgets('오류 화면은 예외 내용이 길어도 넘치지 않는다', (tester) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final error = AppConfigException(List.filled(100, '긴 오류 내용').join('\n'));
    await tester.pumpWidget(ConfigErrorApp(error: error, showDetails: true));

    expect(tester.takeException(), isNull);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
  });

  testWidgets('release용 오류 화면은 예외 내용을 숨긴다', (tester) async {
    const error = AppConfigException('내부 정보');
    await tester.pumpWidget(
      const ConfigErrorApp(error: error, showDetails: false),
    );

    expect(find.text('앱을 시작하지 못했습니다'), findsOneWidget);
    expect(find.textContaining('내부 정보'), findsNothing);
  });
}
