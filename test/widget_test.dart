import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:u4/config/app_config.dart';
import 'package:u4/main.dart';

Map<String, Object?> _read(Flavor flavor) =>
    jsonDecode(File(flavor.assetPath).readAsStringSync())
        as Map<String, Object?>;

/// 어떤 키를 요청하든 [text]를 돌려주는 asset bundle.
class _StringBundle extends CachingAssetBundle {
  _StringBundle(this.text);

  final String text;

  @override
  Future<ByteData> load(String key) async =>
      ByteData.sublistView(utf8.encode(text));
}

void main() {
  testWidgets('설정 확인 화면에 flavor와 앱 이름이 보인다', (tester) async {
    final config = AppConfig.fromJson(_read(Flavor.dev));
    await tester.pumpWidget(U4App(config: config));

    expect(find.text('U4 DEV'), findsOneWidget);
    expect(find.text('dev'), findsOneWidget);
  });

  group('buildApp', () {
    testWidgets('설정을 읽으면 U4App을 띄운다', (tester) async {
      final devJson = File(Flavor.dev.assetPath).readAsStringSync();
      final app = await buildApp(
        () => AppConfig.load(Flavor.dev, bundle: _StringBundle(devJson)),
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

    final cases = <String, (Flavor, String, Matcher)>{
      '설정 파일의 flavor가 다르면': (
        Flavor.prod,
        File(Flavor.dev.assetPath).readAsStringSync(),
        isA<AppConfigException>(),
      ),
      'JSON 형식이 깨지면': (Flavor.dev, '{"flavor": ', isA<FormatException>()),
      'JSON 최상위가 객체가 아니면': (Flavor.dev, '[]', isA<TypeError>()),
    };
    cases.forEach((name, c) {
      final (flavor, text, matcher) = c;
      testWidgets('$name 오류 화면을 띄운다', (tester) async {
        final app = await buildApp(
          () => AppConfig.load(flavor, bundle: _StringBundle(text)),
        );
        expect(tester.takeException(), matcher);

        await tester.pumpWidget(app);
        expect(app, isA<ConfigErrorApp>());
        expect(find.text('앱을 시작하지 못했습니다'), findsOneWidget);
      });
    });
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
