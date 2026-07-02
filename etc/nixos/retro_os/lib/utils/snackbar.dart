import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'debug_logger.dart';

const _errorSound = 'sounds/error-sound-effect-3287-freesounds-community.wav';
final _errorSoundPlayer = AudioPlayer();

Future<void> _playErrorSound() async {
  try {
    await _errorSoundPlayer.play(AssetSource(_errorSound));
  } catch (e) {
    DebugLogger.log('[snackbar] failed to play error sound: $e');
  }
}

/// Shows the app's standard error SnackBar (red, 5s) and plays the error
/// sound effect. Use this instead of ScaffoldMessenger directly for any
/// error feedback so the sound stays consistent everywhere.
void showErrorSnackBar(BuildContext context, String message) {
  _playErrorSound();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message, style: const TextStyle(color: Colors.white)),
      backgroundColor: Colors.red[900],
      duration: const Duration(seconds: 5),
    ),
  );
}
