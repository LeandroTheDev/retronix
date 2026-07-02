import 'package:flutter/material.dart';
import 'services/gamepad_service.dart';
import 'pages/splash_page.dart';
import 'utils/debug_logger.dart';
import 'utils/locale_service.dart';
import 'utils/app_localizations.dart';
import 'utils/settings_service.dart';
import 'utils/system_info.dart';
import 'widgets/gamepad_status_overlay.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  GamepadService.instance.init();
  await LocaleService.instance.load();
  final savedVol = await SettingsService.instance.savedVolume();
  final savedDevice = await SettingsService.instance.audioDevice();
  DebugLogger.log('[main] savedVolume=$savedVol — applying...');
  await setVolumeLevel(savedVol, savedDevice);
  final readBack = await getVolumeLevel(savedDevice);
  DebugLogger.log('[main] volume after apply: readBack=$readBack');
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
        home: const SplashPage(),
        builder: (context, child) => Stack(children: [?child, const GamepadStatusOverlay()]),
      ),
    );
  }
}
