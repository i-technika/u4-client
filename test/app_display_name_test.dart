import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:u4/config/app_config.dart';

import 'helpers.dart';

/// 앱 표시 이름(런처·홈 화면)이 설정 JSON의 `app.name`과 어긋나지 않는지 검사한다 (#9).
///
/// - Android: `android/app/build.gradle.kts`가 빌드 시 flavor별 JSON을 읽는다.
///   여기서는 그 경로가 끊기지 않았는지(매니페스트·Gradle)를 본다.
/// - iOS: Xcode flavor가 아직 없어 `ios/Flutter/AppInfo.xcconfig`에 prod 이름을 손으로 적고,
///   Info.plist는 `$(APP_DISPLAY_NAME)`을 참조한다. 이 값이 JSON과 어긋나면 실패한다.
void main() {
  String appNameOf(Flavor flavor) =>
      (readConfigJson(flavor)['app'] as Map<String, Object?>)['name'] as String;

  group('Android', () {
    test('모든 매니페스트의 android:label은 \${appName}뿐이다', () {
      final manifests = Directory('android/app/src')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('AndroidManifest.xml'));
      final labels = [
        for (final f in manifests)
          ...RegExp(r'android:label="([^"]*)"')
              .allMatches(f.readAsStringSync())
              .map((m) => m.group(1)),
      ];
      expect(labels, [r'${appName}']);
    });

    test('build.gradle.kts는 appName을 JSON에서 읽은 값으로 한 번만 넣는다', () {
      final gradle = File('android/app/build.gradle.kts').readAsStringSync();
      // put("appName", ...), mapOf("appName" to ...), buildType 쪽 placeholder도 함께 막는다.
      expect('"appName"'.allMatches(gradle), hasLength(1));
      expect(
        gradle,
        matches(RegExp(r'manifestPlaceholders\["appName"\]\s*=\s*appNameOf\(')),
      );
    });

    for (final flavor in Flavor.values) {
      test('${flavor.name}의 app.name을 android:label로 쓸 수 있다', () {
        // build.gradle.kts의 appNameOf와 같은 규칙이다.
        final name = appNameOf(flavor);
        final trimmed = name.trim();
        expect(trimmed, isNot(startsWith('@')));
        expect(trimmed, isNot(startsWith('?')));
        expect(name, isNot(contains(r'\')));
        expect(name, isNot(contains(r'${')));
        expect(name, contains(RegExp(r'[\p{L}\p{N}]', unicode: true)));
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
      test('$config.xcconfig는 AppInfo.xcconfig를 포함하고 값을 덮어쓰지 않는다', () {
        final path = 'ios/Flutter/$config.xcconfig';
        final lines = File(path).readAsLinesSync().map((l) => l.trim());
        expect(lines, contains('#include "AppInfo.xcconfig"'));
        // APP_DISPLAY_NAME[sdk=...] 같은 조건부 정의도 막는다.
        final definitions = lines
            .map((l) => l.split('//').first.trim())
            .where((l) => l.startsWith('APP_DISPLAY_NAME'));
        expect(definitions, isEmpty);
      });
    }

    test('Xcode 프로젝트 설정이 APP_DISPLAY_NAME을 덮어쓰지 않는다', () {
      final pbxproj = File('ios/Runner.xcodeproj/project.pbxproj')
          .readAsStringSync();
      expect(pbxproj, isNot(contains('APP_DISPLAY_NAME')));
    });
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
