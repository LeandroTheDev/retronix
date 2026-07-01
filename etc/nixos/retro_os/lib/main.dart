import 'package:flutter/material.dart';
import 'services/gamepad_service.dart';
import 'pages/console_selector_page.dart';
import 'utils/locale_service.dart';
import 'utils/app_localizations.dart';
import 'widgets/gamepad_status_overlay.dart';

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
        theme: ThemeData.dark(useMaterial3: false).copyWith(
          textTheme: ThemeData.dark(useMaterial3: false).textTheme.apply(fontFamily: 'PressStart'),
          snackBarTheme: const SnackBarThemeData(
            contentTextStyle: TextStyle(fontFamily: 'PressStart', color: Colors.white),
          ),
        ),
        home: const ConsoleSelectorPage(),
        builder: (context, child) => Stack(children: [?child, const GamepadStatusOverlay()]),
      ),
    );
  }
}
