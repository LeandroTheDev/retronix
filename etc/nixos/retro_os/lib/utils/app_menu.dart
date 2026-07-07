import 'package:flutter/material.dart';
import '../pages/download_provider_page.dart';
import '../pages/nintendo64_settings_page.dart';
import '../pages/playstation1_settings_page.dart';
import '../pages/playstation2_settings_page.dart';
import '../pages/system_settings_page.dart';
import '../pages/update_system_page.dart';
import '../pages/about_system_page.dart';
import '../pages/bluetooth_page.dart';
import '../pages/shutdown_page.dart';
import '../pages/restart_page.dart';
import 'app_localizations.dart';
import 'dialogs.dart';
import '../services/update_checker_service.dart';

/// The Start-button settings menu — shared across every page so it can be
/// opened from anywhere, not just the console selector.
Future<void> showAppSettingsDialog(BuildContext context) {
  UpdateCheckerService.instance.checkNow();
  final l = AppLocalizations.of(context);
  return showSettingsDialog(
    context,
    title: l.settingsDialogTitle,
    options: [
      SettingsOption(
        label: l.settingsNintendo64,
        icon: Icons.sports_esports,
        onSelect: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const Nintendo64SettingsPage()),
        ),
      ),
      SettingsOption(
        label: l.settingsPlaystation2,
        icon: Icons.sports_esports,
        onSelect: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const Playstation2SettingsPage()),
        ),
      ),
      SettingsOption(
        label: l.settingsPlaystation1,
        icon: Icons.sports_esports,
        onSelect: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const Playstation1SettingsPage()),
        ),
      ),
      SettingsOption(
        label: l.systemSettingsTitle,
        icon: Icons.settings,
        onSelect: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SystemSettingsPage()),
        ),
      ),
      SettingsOption(
        label: l.downloadProvider,
        icon: Icons.cloud_download_outlined,
        onSelect: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const DownloadProviderPage()),
        ),
      ),
      SettingsOption(
        label: l.updateSystem,
        icon: Icons.system_update_alt,
        hasNotification: UpdateCheckerService.instance.hasUpdates,
        onSelect: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const UpdateSystemPage()),
        ),
      ),
      SettingsOption(
        label: l.aboutSystem,
        icon: Icons.info_outline,
        onSelect: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AboutSystemPage()),
        ),
      ),
      SettingsOption(
        label: l.bluetooth,
        icon: Icons.bluetooth,
        onSelect: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const BluetoothPage()),
        ),
      ),
      SettingsOption(
        label: l.restartSystem,
        icon: Icons.restart_alt,
        onSelect: () {
          Navigator.pop(context);
          showRestartConfirmDialog(context);
        },
      ),
      SettingsOption(
        label: l.shutdown,
        icon: Icons.power_settings_new,
        onSelect: () {
          Navigator.pop(context); // fecha o settings dialog antes
          showShutdownConfirmDialog(context);
        },
      ),
    ],
  );
}

Future<void> showRestartConfirmDialog(BuildContext context) async {
  final l = AppLocalizations.of(context);
  final confirmed = await showConfirmDialog(
    context,
    message: l.restartConfirm,
    labelYes: l.yes,
    labelNo: l.no,
  );

  if (!context.mounted) return;
  if (confirmed) {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const RestartPage()),
      (_) => false,
    );
  }
}

Future<void> showShutdownConfirmDialog(BuildContext context) async {
  final l = AppLocalizations.of(context);
  final confirmed = await showConfirmDialog(
    context,
    message: l.shutdownConfirm,
    labelYes: l.yes,
    labelNo: l.no,
  );

  if (!context.mounted) return;
  if (confirmed) {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const ShutdownPage()),
      (_) => false,
    );
  }
}
