import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:u4/config/app_config.dart';
import 'package:u4/main.dart';

Map<String, Object?> _read(Flavor flavor) =>
    jsonDecode(File(flavor.assetPath).readAsStringSync())
        as Map<String, Object?>;

void main() {
  testWidgets('설정 확인 화면에 flavor와 앱 이름이 보인다', (tester) async {
    final config = AppConfig.fromJson(_read(Flavor.dev));
    await tester.pumpWidget(U4App(config: config));

    expect(find.text('U4 DEV'), findsOneWidget);
    expect(find.text('dev'), findsOneWidget);
  });
}
