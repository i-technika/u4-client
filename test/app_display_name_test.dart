import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:u4/config/app_config.dart';

import 'helpers.dart';

/// 앱 표시 이름(런처·홈 화면)이 설정 JSON의 `app.name`과 어긋나지 않는지 검사한다 (#9).
///
/// - Android: `android/app/build.gradle.kts`가 빌드 시 flavor별 JSON을 읽는다.
///   여기서는 그 경로가 끊기지 않았는지(매니페스트·Gradle)를 본다.
/// - iOS: flavor마다 `ios/Flutter/AppInfo-<flavor>.xcconfig`에 이름과 bundle ID를 손으로 적고,
///   Info.plist는 `$(APP_DISPLAY_NAME)`을 참조한다 (#38). 이 값이 JSON과 어긋나거나
///   build configuration·scheme이 다른 flavor의 xcconfig를 쓰면 실패한다.
void main() {
  String appNameOf(Flavor flavor) =>
      (readConfigJson(flavor)['app'] as Map<String, Object?>)['name'] as String;

  group('Android', () {
    test('모든 매니페스트의 android:label은 \${appName}뿐이다', () {
      final manifests = Directory('android/app/src')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('AndroidManifest.xml'));
      // activity·activity-alias의 label도 런처 이름을 덮으므로 전부 센다.
      // 작은따옴표와 = 앞뒤 공백도 XML 문법이므로 함께 잡는다.
      final labels = [
        for (final f in manifests)
          ...RegExp(r'''android:label\s*=\s*(["'])(.*?)\1''')
              .allMatches(f.readAsStringSync())
              .map((m) => m.group(2)),
      ];
      expect(labels, [r'${appName}']);
    });

    test('build.gradle.kts는 flavor마다 그 flavor JSON의 이름을 한 번만 넣는다', () {
      final gradle = File('android/app/build.gradle.kts').readAsStringSync();
      // put("appName", ...), mapOf("appName" to ...), buildType 쪽 placeholder도 함께 막는다.
      expect('"appName"'.allMatches(gradle), hasLength(1));
      // appNameOf("prod")처럼 한 flavor 값을 모든 flavor에 넣는 실수도 막는다.
      // appNameOf가 실제로 JSON 값을 돌려주는지는 이 테스트로 보지 않는다 (CI가 APK로 확인: tool/check_android_app_label.sh, #39).
      expect(
        gradle,
        matches(
          RegExp(
            r'productFlavors\.configureEach\s*\{\s*'
            r'manifestPlaceholders\["appName"\]\s*=\s*appNameOf\(name\)\s*\}',
          ),
        ),
      );
    });

    for (final flavor in Flavor.values) {
      test('${flavor.name}의 app.name을 android:label로 쓸 수 있다', () {
        // build.gradle.kts의 appNameOf와 같은 규칙이다. 한쪽을 고치면 다른 쪽도 고친다.
        // Kotlin trimStart { ' ' || '\t'..'\r' }, Character.isLetterOrDigit(code point)와 맞춘다.
        final name = appNameOf(flavor);
        final head = name.replaceFirst(RegExp(r'^[ \t\n\v\f\r]+'), '');
        expect(head, isNot(startsWith('@')));
        expect(head, isNot(startsWith('?')));
        expect(name, isNot(contains(r'\')));
        expect(name, isNot(contains(r'${')));
        expect(name, contains(RegExp(r'[\p{L}\p{Nd}]', unicode: true)));
      });
    }
  });

  group('iOS', () {
    const modes = ['Debug', 'Release', 'Profile'];

    test('Info.plist의 CFBundleDisplayName은 \$(APP_DISPLAY_NAME)을 참조한다', () {
      final plist = File('ios/Runner/Info.plist').readAsStringSync();
      final match = RegExp(
        r'<key>CFBundleDisplayName</key>\s*<string>([^<]*)</string>',
      ).firstMatch(plist);
      expect(match, isNotNull, reason: 'CFBundleDisplayName 키가 없습니다');
      expect(match!.group(1), r'$(APP_DISPLAY_NAME)');
    });

    for (final flavor in Flavor.values) {
      final f = flavor.name;

      test('AppInfo-$f.xcconfig의 APP_DISPLAY_NAME은 $f의 app.name과 같다', () {
        final settings = _readXcconfig('ios/Flutter/AppInfo-$f.xcconfig');
        expect(settings['APP_DISPLAY_NAME'], appNameOf(flavor));
      });

      test('AppInfo-$f.xcconfig의 bundle ID는 Android $f applicationId와 같다', () {
        final settings = _readXcconfig('ios/Flutter/AppInfo-$f.xcconfig');
        expect(settings['PRODUCT_BUNDLE_IDENTIFIER'], _androidApplicationId(f));
      });

      test('AppInfo-$f.xcconfig는 두 값만 정한다 (include·조건부 키 없음)', () {
        // #include로 다른 flavor 값을 끌어오거나 APP_DISPLAY_NAME[sdk=iphoneos*]처럼
        // 실기기에서만 다른 값을 쓰는 것을 막는다.
        final lines = File('ios/Flutter/AppInfo-$f.xcconfig')
            .readAsLinesSync()
            .map((l) => l.split('//').first.trim())
            .where((l) => l.isNotEmpty)
            .map((l) => l.split('=').first.trim());
        expect(
          lines,
          unorderedEquals(['PRODUCT_BUNDLE_IDENTIFIER', 'APP_DISPLAY_NAME']),
        );
      });

      for (final mode in modes) {
        test('$mode-$f.xcconfig는 Generated·$f AppInfo만 이 순서로 포함한다', () {
          // 값을 직접 정하지 않는다(조건부 키 포함). AppInfo를 마지막에 두어 앞의 설정이 덮지 못하게 한다.
          // CocoaPods를 쓰지 않으므로 Pods xcconfig도 포함하지 않는다 (#52).
          final lines = File('ios/Flutter/$mode-$f.xcconfig')
              .readAsLinesSync()
              .map((l) => l.split('//').first.trim())
              .where((l) => l.isNotEmpty);
          expect(lines, [
            '#include "Generated.xcconfig"',
            '#include "AppInfo-$f.xcconfig"',
          ]);
        });
      }

      test('scheme $f는 $f build configuration만 쓴다', () {
        final scheme = File(
          'ios/Runner.xcodeproj/xcshareddata/xcschemes/$f.xcscheme',
        ).readAsStringSync();
        final used = RegExp(r'<(\w+)\s+buildConfiguration\s*=\s*"([^"]*)"')
            .allMatches(scheme)
            .map((m) => '${m[1]}=${m[2]}');
        expect(
          used,
          unorderedEquals([
            'TestAction=Debug-$f',
            'LaunchAction=Debug-$f',
            'ProfileAction=Profile-$f',
            'AnalyzeAction=Debug-$f',
            'ArchiveAction=Release-$f',
          ]),
        );
      });
    }

    test('scheme은 dev·stg·prod뿐이다 (flavor 없는 Runner scheme을 두지 않는다)', () {
      final schemes = Directory('ios/Runner.xcodeproj/xcshareddata/xcschemes')
          .listSync()
          .map((e) => e.uri.pathSegments.last)
          // Finder가 만드는 .DS_Store 등은 scheme이 아니다.
          .where((name) => name.endsWith('.xcscheme'));
      expect(
        schemes,
        unorderedEquals(['dev.xcscheme', 'stg.xcscheme', 'prod.xcscheme']),
      );
    });

    group('Xcode 프로젝트', () {
      final pbxproj = File('ios/Runner.xcodeproj/project.pbxproj')
          .readAsStringSync();
      final expected = [
        for (final mode in modes)
          for (final flavor in Flavor.values) '$mode-${flavor.name}',
      ];

      test('build configuration 목록은 모드×flavor 9개다', () {
        final lists = RegExp(
          r'isa = XCConfigurationList;\s*buildConfigurations = \(([^)]*)\);',
        ).allMatches(pbxproj);
        expect(lists, hasLength(3)); // 프로젝트, Runner, RunnerTests
        for (final list in lists) {
          final names = RegExp(r'/\* (\S+) \*/')
              .allMatches(list[1]!)
              .map((m) => m[1]);
          expect(names, unorderedEquals(expected));
        }
      });

      test('Runner build configuration은 같은 이름의 xcconfig를 쓴다', () {
        // Runner 타깃만 INFOPLIST_FILE = Runner/Info.plist를 가진다.
        final runner = RegExp(
          r'/\* (\S+) \*/ = \{\s*isa = XCBuildConfiguration;\s*'
          r'baseConfigurationReference = \w+ /\* (\S+) \*/;'
          r'[^}]*INFOPLIST_FILE = Runner/Info\.plist;',
        ).allMatches(pbxproj);
        expect(
          {for (final m in runner) m[1]: m[2]},
          {for (final name in expected) name: '$name.xcconfig'},
        );
      });

      test('APP_DISPLAY_NAME과 앱 bundle ID를 덮어쓰지 않는다', () {
        expect(pbxproj, isNot(contains('APP_DISPLAY_NAME')));
        // RunnerTests의 bundle ID만 남는다. Xcode가 쓰는 조건부 키
        // ("PRODUCT_BUNDLE_IDENTIFIER[sdk=iphoneos*]" = ...)도 함께 센다.
        final settings = RegExp(
          r'"?PRODUCT_BUNDLE_IDENTIFIER(\[[^\]]*\])?"?\s*=\s*([^;]+);',
        ).allMatches(pbxproj).toList();
        // 기기·시뮬레이터 SDK별 조건부 값은 두지 않는다.
        expect(settings.map((m) => m[1]).nonNulls, isEmpty);
        expect(settings, hasLength(9)); // RunnerTests configuration 9개
        expect(
          settings.map((m) => m[2]!.trim()),
          everyElement('com.itechnika.u4.RunnerTests'),
        );
      });

      test('CocoaPods 연동이 없다 (플러그인은 모두 SwiftPM으로 연결, #52)', () {
        // CocoaPods가 필요한 플러그인을 추가하면 Flutter가 Podfile을 만들고 pod install이
        // 프로젝트에 Pods 설정을 다시 넣는다. 그때는 이 테스트와 docs/phase-1-setup.md 4장을 함께 고친다.
        expect(File('ios/Podfile').existsSync(), isFalse);
        expect(File('ios/Podfile.lock').existsSync(), isFalse);
        expect(pbxproj, isNot(contains('Pods')));
        expect(pbxproj, isNot(contains('[CP]')));
        expect(
          File('ios/Runner.xcworkspace/contents.xcworkspacedata')
              .readAsStringSync(),
          isNot(contains('Pods')),
        );
      });
    });

    test('지역화 InfoPlist.strings가 CFBundleDisplayName을 덮어쓰지 않는다', () {
      // ko.lproj/InfoPlist.strings 등에 값이 있으면 그 언어 기기에서 홈 화면 이름이 바뀐다.
      final overrides = Directory('ios/Runner')
          .listSync(recursive: true)
          .whereType<File>()
          .where(
            (f) =>
                f.path.endsWith('InfoPlist.strings') ||
                f.path.endsWith('.xcstrings'),
          )
          // .strings는 UTF-16일 수 있다. 키는 ASCII이므로 0 바이트를 빼고 찾는다.
          .where(
            (f) =>
                String.fromCharCodes(f.readAsBytesSync().where((b) => b != 0))
                    .contains('CFBundleDisplayName'),
          )
          .map((f) => f.path);
      expect(overrides, isEmpty);
    });
  });
}

/// `android/app/build.gradle.kts`에서 [flavor]의 applicationId(+ applicationIdSuffix)를 읽는다.
String _androidApplicationId(String flavor) {
  final gradle = File('android/app/build.gradle.kts').readAsStringSync();
  final base = RegExp(r'applicationId = "([^"]+)"').firstMatch(gradle)![1]!;
  final block = RegExp('create\\("$flavor"\\) \\{([^}]*)\\}')
      .firstMatch(gradle);
  expect(block, isNotNull, reason: 'productFlavors에 $flavor가 없습니다');
  final suffix = RegExp(r'applicationIdSuffix = "([^"]*)"')
      .firstMatch(block![1]!);
  return base + (suffix?[1] ?? '');
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
