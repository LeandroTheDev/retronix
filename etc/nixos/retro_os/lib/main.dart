import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
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
  StreamSubscription<GamepadAction>? _gamepadSub;

  @override
  void initState() {
    super.initState();
    LocaleService.instance.addListener(_onLocaleChange);
    _gamepadSub = GamepadService.instance.actions.listen(_onGlobalAction);
  }

  @override
  void dispose() {
    _gamepadSub?.cancel();
    LocaleService.instance.removeListener(_onLocaleChange);
    super.dispose();
  }

  void _onLocaleChange() => setState(() {});

  void _onGlobalAction(GamepadAction action) {
    if (action == GamepadAction.l) _openTestNotification();
  }

  Future<void> _openTestNotification() async {
    const binary = kDebugMode
        ? '/home/leans/Templates/retronix/etc/nixos/retro_os_notification'
            '/build/linux/x64/release/bundle/retro_os_notification'
        : 'retro_os_notification';
    try {
      await Process.start(binary, ['Conquista de Teste', '25']);
    } catch (e) {
      DebugLogger.log('[RetroOsApp] test notification error: $e');
    }
  }

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
