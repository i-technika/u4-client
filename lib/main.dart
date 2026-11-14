import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import 'config/app_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(await buildApp(() => AppConfig.load(Flavor.current)));
}

/// 설정을 읽어 띄울 앱을 만든다.
///
/// 설정을 읽지 못하면 [ConfigErrorApp]을 돌려준다. `runApp` 전에 예외가 나면
/// 네이티브 런치 화면에 멈춘 채 아무것도 보이지 않기 때문이다.
Future<Widget> buildApp(Future<AppConfig> Function() loadConfig) async {
  try {
    return U4App(config: await loadConfig());
  } catch (error, stack) {
    // AppConfigException 외에 JSON 형식 오류, 타입 캐스트 실패, asset 누락도 여기로 온다.
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'u4',
        context: ErrorDescription('앱 설정을 읽는 중'),
      ),
    );
    return ConfigErrorApp(error: error);
  }
}

class U4App extends StatelessWidget {
  const U4App({super.key, required this.config});

  final AppConfig config;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: config.app.name,
      debugShowCheckedModeBanner: false,
      themeMode: config.theme.themeMode,
      theme: ThemeData(colorSchemeSeed: Colors.indigo),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.dark,
      ),
      home: SetupCheckScreen(config: config),
    );
  }
}

/// 설정을 읽지 못했을 때 띄우는 앱.
///
/// 설정이 없으므로 앱 이름·테마도 쓸 수 없다. release에서는 안내 문구만,
/// 그 밖에는 원인을 바로 볼 수 있게 예외 내용도 보여 준다.
class ConfigErrorApp extends StatelessWidget {
  const ConfigErrorApp({
    super.key,
    required this.error,
    this.showDetails = !kReleaseMode,
  });

  final Object error;
  final bool showDetails;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.error_outline, size: 48),
                const SizedBox(height: 16),
                const Text(
                  '앱을 시작하지 못했습니다',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  '앱을 최신 버전으로 업데이트한 뒤 다시 실행해 주세요.',
                  textAlign: TextAlign.center,
                ),
                if (showDetails) ...[
                  const SizedBox(height: 24),
                  SelectableText('$error'),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 1단계 확인용 화면: 설정이 flavor에 맞게 로딩됐는지 보여 준다.
/// 2단계에서 `AppWebView`로 바꾼다.
class SetupCheckScreen extends StatelessWidget {
  const SetupCheckScreen({super.key, required this.config});

  final AppConfig config;

  @override
  Widget build(BuildContext context) {
    final rows = <(String, String)>[
      ('flavor', config.flavor.name),
      ('startUrl', config.app.startUrl.toString()),
      ('allowedHosts', config.app.allowedHosts.join(', ')),
      ('safeAreaHandling', config.systemUi.safeAreaHandling.name),
      ('allowHttp', '${config.network.allowHttp}'),
      ('debuggable', '${config.network.debuggable}'),
    ];
    return Scaffold(
      appBar: AppBar(title: Text(config.app.name)),
      body: ListView(
        children: [
          for (final (label, value) in rows)
            ListTile(title: Text(label), subtitle: Text(value)),
        ],
      ),
    );
  }
}
