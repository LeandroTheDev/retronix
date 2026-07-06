import 'package:flutter/material.dart';
import 'services/gamepad_service.dart';
import 'pages/splash_page.dart';
import 'utils/debug_logger.dart';
import 'utils/locale_service.dart';
import 'utils/app_localizations.dart';
import 'utils/settings_service.dart';
import 'utils/system_info.dart';
import 'widgets/gamepad_status_overlay.dart';
import 'widgets/achievement_notification_overlay.dart';
import 'services/achievement_window_service.dart';
import 'services/update_checker_service.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  DebugLogger.cleanIfOld();
  GamepadService.instance.init();
  UpdateCheckerService.instance.init();
  AchievementWindowService.instance.init();
  await LocaleService.instance.load();
  final savedVol = await SettingsService.instance.savedVolume();
  final savedDevice = await SettingsService.instance.audioDevice();
  DebugLogger.log('[main] savedVolume=$savedVol savedDevice=$savedDevice — applying...');
  if (savedDevice.isNotEmpty) {
    final devices = await getAudioDevices();
    final exists = devices.any((d) => d.name == savedDevice);
    if (exists) {
      await setDefaultAudioDevice(savedDevice);
    } else {
      DebugLogger.log('[main] savedDevice=$savedDevice not found in sinks, skipping');
    }
  }
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
        builder: (context, child) => Stack(children: [
          ?child,
          ValueListenableBuilder<bool>(
            valueListenable: GamepadService.instance.splashDone,
            builder: (_, done, _) => done ? const GamepadStatusOverlay() : const SizedBox.shrink(),
          ),
          const AchievementNotificationOverlay(),
        ]),
      ),
    );
  }
}
