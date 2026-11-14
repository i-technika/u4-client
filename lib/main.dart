import 'package:material_ui/material_ui.dart';

import 'config/app_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final config = await AppConfig.load(Flavor.current);
  runApp(U4App(config: config));
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
