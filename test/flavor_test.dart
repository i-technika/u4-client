import 'package:flutter_test/flutter_test.dart';

import 'package:u4/config/app_config.dart';

/// [Flavor.resolve]: `--flavor`(appFlavor)와 예전 `--dart-define=FLAVOR`로 flavor를 정하는 규칙 (#38).
void main() {
  Flavor resolve(
    String? appFlavor, {
    String legacy = '',
    bool release = true,
  }) => Flavor.resolve(
    appFlavor: appFlavor,
    legacyDefine: legacy,
    isRelease: release,
  );

  Matcher throwsConfigError(Pattern message) => throwsA(
    isA<AppConfigException>().having(
      (e) => e.message,
      'message',
      contains(message),
    ),
  );

  test('--flavor 값을 그대로 쓴다', () {
    for (final flavor in Flavor.values) {
      expect(resolve(flavor.name), flavor);
      expect(resolve(flavor.name, release: false), flavor);
    }
  });

  test('flavor가 없으면 release는 실패하고 debug는 dev를 쓴다', () {
    expect(
      () => resolve(null),
      throwsConfigError('release 빌드는 --flavor가 필요합니다'),
    );
    expect(resolve(null, release: false), Flavor.dev);
  });

  test('알 수 없는 flavor는 실패한다', () {
    expect(() => resolve('qa'), throwsConfigError('알 수 없는 flavor: qa'));
  });

  group('예전 --dart-define=FLAVOR', () {
    test('--flavor와 같으면 무시한다', () {
      expect(resolve('prod', legacy: 'prod'), Flavor.prod);
    });

    test('--flavor와 다르면 debug·release 모두 실패한다', () {
      for (final release in [true, false]) {
        expect(
          () => resolve('dev', legacy: 'prod', release: release),
          throwsConfigError('--flavor prod로 빌드하세요 (지금 --flavor: dev)'),
        );
      }
    });

    test('--flavor 없이 넘기면 debug에서도 dev로 뜨지 않고 실패한다', () {
      expect(
        () => resolve(null, legacy: 'prod', release: false),
        throwsConfigError('(지금 --flavor: 없음)'),
      );
    });
  });
}
