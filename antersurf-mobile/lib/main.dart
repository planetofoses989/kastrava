import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'services/settings_service.dart';
import 'services/anterget_service.dart';
import 'screens/browser_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SettingsService.instance.load();
  try {
    await AnterGetService.instance.init();
  } catch (_) {}
  runApp(const AnterSurfApp());
}

class AnterSurfApp extends StatelessWidget {
  const AnterSurfApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: SettingsService.instance,
      builder: (context, _) {
        return MaterialApp(
          title: 'AnterSurf',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.build(),
          home: const BrowserScreen(),
        );
      },
    );
  }
}
