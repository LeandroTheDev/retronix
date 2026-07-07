import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Renders a console or game image from [path], supporting PNG/JPG/WebP and SVG.
/// Falls back to [placeholder] if [path] is null.
class ConsoleImage extends StatelessWidget {
  const ConsoleImage({
    super.key,
    required this.path,
    required this.width,
    required this.height,
    this.fit = BoxFit.contain,
    required this.placeholder,
  });

  final String? path;
  final double width;
  final double height;
  final BoxFit fit;
  final Widget placeholder;

  @override
  Widget build(BuildContext context) {
    final p = path;
    if (p == null) return placeholder;

    if (p.toLowerCase().endsWith('.svg')) {
      return SvgPicture.file(
        File(p),
        width: width,
        height: height,
        fit: fit,
      );
    }

    return Image.file(
      File(p),
      width: width,
      height: height,
      fit: fit,
    );
  }
}
