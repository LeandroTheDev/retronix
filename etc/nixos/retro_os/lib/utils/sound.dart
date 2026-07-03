import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'debug_logger.dart';

const _swapSound = 'sounds/swap-sound-effect-512211-freesounds-community.wav';

/// Every UI sound effect played anywhere in the app (kept in sync with the
/// asset path constants in gamepad_service.dart, snackbar.dart and
/// system_settings_page.dart) — warmed up together so the first real trigger
/// of each one doesn't pay the audioplayers asset-extraction latency.
const _allSoundAssets = [
  _swapSound,
  'sounds/connect-sound-effect-3045-freesounds-community.wav',
  'sounds/disconnect-sound-effect-270300-freesounds-community.wav',
  'sounds/error-sound-effect-3287-freesounds-community.wav',
  'sounds/change-sound-effect-402322-freesounds-community.wav',
  'sounds/change2-sound-effect-188167-freesounds-community.wav',
];

/// Warms the audio cache for every UI sound effect — call once, early
/// (e.g. from SplashPage), so navigation/connect/error sounds don't stutter
/// on their first play.
Future<void> preloadAllSounds() async {
  try {
    await AudioCache.instance.loadAll(_allSoundAssets);
  } catch (e) {
    DebugLogger.log('[sound] preloadAllSounds failed: $e');
  }
}

/// Clamps [current + delta] to [0, max], plays the navigation sound only
/// when the index actually changes, and returns the new index.
int navigateIndex(int current, int delta, int max) {
  final next = (current + delta).clamp(0, max);
  if (next != current) playSound(_swapSound);
  return next;
}

/// Plays a one-shot sound effect from `assets/<assetPath>`.
///
/// Always spins up a fresh [AudioPlayer] instead of reusing a shared one:
/// calling play() on a player that's still playing a previous sound can
/// silently no-op instead of layering on top, so back-to-back triggers
/// (e.g. two controllers connecting at once, or two errors in a row) would
/// otherwise go silent for every call after the first.
Future<void> playSound(String assetPath) async {
  final player = AudioPlayer();
  Timer? safety;
  var cleaned = false;
  void cleanup() {
    if (cleaned) return;
    cleaned = true;
    safety?.cancel();
    player.dispose();
  }

  try {
    player.onPlayerComplete.listen((_) => cleanup());
    // Safety net in case the backend never fires onPlayerComplete — don't
    // leak the player indefinitely.
    safety = Timer(const Duration(seconds: 5), cleanup);
    await player.play(AssetSource(assetPath));
  } catch (e) {
    DebugLogger.log('[sound] failed to play $assetPath: $e');
    cleanup();
  }
}
