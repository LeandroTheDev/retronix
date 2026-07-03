import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'debug_logger.dart';

const _swapSound = 'sounds/swap-sound-effect-512211-freesounds-community.wav';

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
