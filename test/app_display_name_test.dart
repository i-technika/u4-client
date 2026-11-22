import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:u4/config/app_config.dart';

import 'helpers.dart';

/// 앱 표시 이름(런처·홈 화면)의 원본이 설정 JSON의 `app.name` 한 곳인지 검사한다 (#9).
///
/// - Android: `android/app/build.gradle.kts`가 빌드 시 flavor별 JSON을 읽는다.
/// - iOS: Xcode flavor가 아직 없어 `ios/Flutter/AppInfo.xcconfig`에 prod 이름을 적고,
///   Info.plist는 `$(APP_DISPLAY_NAME)`을 참조한다. 이 값이 JSON과 어긋나면 실패한다.
void main() {
  String appNameOf(Flavor flavor) =>
      (readConfigJson(flavor)['app'] as Map<String, Object?>)['name'] as String;

  group('Android', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();

    test('build.gradle.kts에 앱 이름을 직접 적지 않는다', () {
      expect(
        gradle,
        isNot(
          matches(RegExp(r'''manifestPlaceholders\["appName"\]\s*=\s*"''')),
        ),
      );
      expect(
        gradle,
        contains('manifestPlaceholders["appName"] = appNameOf(name)'),
      );
    });

    for (final flavor in Flavor.values) {
      test('${flavor.name}의 app.name을 android:label로 쓸 수 있다', () {
        final name = appNameOf(flavor);
        expect(name.trim(), isNotEmpty);
        // @ 또는 ?로 시작하면 aapt가 리소스 참조로 해석한다. Gradle도 같은 검사를 한다.
        expect(name, isNot(startsWith('@')));
        expect(name, isNot(startsWith('?')));
      });
    }
  });

  group('iOS', () {
    test('Info.plist의 CFBundleDisplayName은 \$(APP_DISPLAY_NAME)을 참조한다', () {
      final plist = File('ios/Runner/Info.plist').readAsStringSync();
      final match = RegExp(
        r'<key>CFBundleDisplayName</key>\s*<string>([^<]*)</string>',
      ).firstMatch(plist);
      expect(match, isNotNull, reason: 'CFBundleDisplayName 키가 없습니다');
      expect(match!.group(1), r'$(APP_DISPLAY_NAME)');
    });

    test('AppInfo.xcconfig의 APP_DISPLAY_NAME은 prod app.name과 같다', () {
      final settings = _readXcconfig('ios/Flutter/AppInfo.xcconfig');
      expect(settings['APP_DISPLAY_NAME'], appNameOf(Flavor.prod));
    });

    for (final config in ['Debug', 'Release']) {
      test('$config.xcconfig가 AppInfo.xcconfig를 포함한다', () {
        final lines = File('ios/Flutter/$config.xcconfig')
            .readAsLinesSync()
            .map((l) => l.trim());
        expect(lines, contains('#include "AppInfo.xcconfig"'));
      });
    }
  });
}

/// xcconfig의 `KEY = value` 줄을 읽는다. `//` 뒤는 주석이다.
Map<String, String> _readXcconfig(String path) {
  final settings = <String, String>{};
  for (final raw in File(path).readAsLinesSync()) {
    final line = raw.split('//').first.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    final eq = line.indexOf('=');
    if (eq < 0) continue;
    settings[line.substring(0, eq).trim()] = line.substring(eq + 1).trim();
  }
  return settings;
}
