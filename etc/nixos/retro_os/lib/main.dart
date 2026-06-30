import 'package:flutter/material.dart';
import 'services/gamepad_service.dart';
import 'pages/console_selector_page.dart';
import 'utils/locale_service.dart';
import 'utils/app_localizations.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  GamepadService.instance.init();
  await LocaleService.instance.load();
  runApp(const RetroOsApp());
}

class RetroOsApp extends StatefulWidget {
  const RetroOsApp({super.key});

  @override
  State<RetroOsApp> createState() => _RetroOsAppState();
}

class _RetroOsAppState extends State<RetroOsApp> {
  @override
  void initState() {
    super.initState();
    LocaleService.instance.addListener(_onLocaleChange);
  }

  @override
  void dispose() {
    LocaleService.instance.removeListener(_onLocaleChange);
    super.dispose();
  }

  void _onLocaleChange() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return AppLocalizationsScope(
      localizations: AppLocalizations(LocaleService.instance.locale),
      child: MaterialApp(
        title: 'RetroOS',
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark(),
        home: const ConsoleSelectorPage(),
      ),
    );
  }
}
