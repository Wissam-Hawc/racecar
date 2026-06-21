import 'package:flutter/material.dart';

import '../main.dart' show kBrandSeed;

/// The Car App logo, used across all screens for a consistent identity.
/// Loads `assets/images/logo.png`; if it's missing, falls back to the
/// built-in robot icon so the UI never breaks.
class AppLogo extends StatelessWidget {
  final double size;
  final Color fallbackColor;

  const AppLogo({super.key, this.size = 32, this.fallbackColor = kBrandSeed});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/logo.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stack) =>
          Icon(Icons.smart_toy, size: size * 0.86, color: fallbackColor),
    );
  }
}
