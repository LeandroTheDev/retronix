import 'dart:async';
import 'package:flutter/material.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:window_manager/window_manager.dart';
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

  final windowController = await WindowController.fromCurrentEngine();
  if (windowController.arguments == 'achievement_test') {
    await windowManager.ensureInitialized();

    final displays = WidgetsBinding.instance.platformDispatcher.displays;
    final display = displays.isEmpty ? null : displays.first;
    final dpr = display?.devicePixelRatio ?? 1.0;
    final screenW = display != null ? display.size.width / dpr : 1920.0;
    final scale = (screenW / 1920.0).clamp(0.5, 2.0);
    final winW = (220.0 * scale).roundToDouble();
    final winH = (80.0 * scale).roundToDouble();

    windowManager.waitUntilReadyToShow(
      WindowOptions(
        size: Size(winW, winH),
        center: true,
        backgroundColor: Colors.black,
        skipTaskbar: true,
        titleBarStyle: TitleBarStyle.hidden,
      ),
      () async {
        await windowManager.show();
      },
    );
    runApp(const _AchievementTestWindow());
    return;
  }

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
    try {
      final controller = await WindowController.create(
        const WindowConfiguration(hiddenAtLaunch: true, arguments: 'achievement_test'),
      );
      await controller.show();
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
        builder: (context, child) => Stack(children: [?child, const GamepadStatusOverlay(), const AchievementNotificationOverlay()]),
      ),
    );
  }
}

class _AchievementTestWindow extends StatelessWidget {
  const _AchievementTestWindow();

  static const _gold = Color(0xFFFFB300);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF111111),
        body: Container(
          decoration: BoxDecoration(border: Border.all(color: const Color(0x55FFB300), width: 1)),
          child: Column(
            children: [
              Container(height: 2, color: _gold),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(color: const Color(0x22FFB300), borderRadius: BorderRadius.circular(4)),
                        child: const Icon(Icons.emoji_events, color: _gold, size: 20),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text(
                              'CONQUISTA DESBLOQUEADA',
                              style: TextStyle(color: _gold, fontSize: 6, fontWeight: FontWeight.bold, letterSpacing: 0.8),
                            ),
                            const SizedBox(height: 3),
                            const Text(
                              'Conquista de Teste',
                              style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            const Text(
                              '+25 pts',
                              style: TextStyle(color: _gold, fontSize: 9, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
