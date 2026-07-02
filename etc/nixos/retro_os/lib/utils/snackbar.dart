import 'package:flutter/material.dart';
import 'sound.dart';

const _errorSound = 'sounds/error-sound-effect-3287-freesounds-community.wav';

/// Shows the app's standard error SnackBar (red, 5s) and plays the error
/// sound effect. Use this instead of ScaffoldMessenger directly for any
/// error feedback so the sound stays consistent everywhere.
void showErrorSnackBar(BuildContext context, String message) {
  playSound(_errorSound);
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message, style: const TextStyle(color: Colors.white)),
      backgroundColor: Colors.red[900],
      duration: const Duration(seconds: 5),
    ),
  );
}
