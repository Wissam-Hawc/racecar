import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../main.dart';
import '../services/mqtt_service.dart';
import '../widgets/app_logo.dart';
import 'connect_screen.dart';

/// Launch splash: plays on open, then hands off to the Connect screen.
/// Gradient hero + decorative blobs, an animated badge (scale/rotate-in,
/// shine sweep, expanding rings), the brand, and pulsing loading dots.
class SplashScreen extends StatefulWidget {
  final MqttService mqtt;
  const SplashScreen({super.key, required this.mqtt});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _enter =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1000))
        ..forward();
  late final AnimationController _loop =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))
        ..repeat();
  Timer? _nav;

  @override
  void initState() {
    super.initState();
    _nav = Timer(const Duration(milliseconds: 2600), _goConnect);
  }

  void _goConnect() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 450),
      pageBuilder: (context, anim, secondary) => ConnectScreen(mqtt: widget.mqtt),
      transitionsBuilder: (context, anim, secondary, child) =>
          FadeTransition(opacity: anim, child: child),
    ));
  }

  @override
  void dispose() {
    _nav?.cancel();
    _enter.dispose();
    _loop.dispose();
    super.dispose();
  }

  double _interval(double v, double a, double b) {
    if (v <= a) return 0;
    if (v >= b) return 1;
    return (v - a) / (b - a);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GestureDetector(
        onTap: _goConnect, // tap to skip
        child: DecoratedBox(
          decoration: const BoxDecoration(gradient: kHeroGradient),
          child: Stack(
            children: [
              _blob(210, Colors.white.withValues(alpha: 0.12), top: -56, right: -54),
              _blob(140, const Color(0xFFF88E70).withValues(alpha: 0.42),
                  bottom: 46, left: -50),
              _dotlet(14, kCyan, top: 120, left: 40, glow: true),
              _dotlet(10, Colors.white.withValues(alpha: 0.55), top: 90, right: 54),
              _dotlet(8, Colors.white.withValues(alpha: 0.55), bottom: 160, right: 40),
              Center(
                child: AnimatedBuilder(
                  animation: Listenable.merge([_enter, _loop]),
                  builder: (context, _) => _content(),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 66,
                child: AnimatedBuilder(
                  animation: _loop,
                  builder: (context, _) => _loadingDots(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _content() {
    final e = _enter.value;
    final badgeIn = Curves.easeOutBack.transform(_interval(e, 0.0, 0.6));
    final scale = 0.4 + 0.6 * badgeIn;
    final rotation = (1 - badgeIn) * -0.35;
    final badgeOpacity = _interval(e, 0.0, 0.4);
    final textOpacity = _interval(e, 0.45, 0.85);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 180,
          height: 180,
          child: Stack(
            alignment: Alignment.center,
            children: [
              _ring(0.0),
              _ring(0.5),
              Opacity(
                opacity: badgeOpacity,
                child: Transform.rotate(
                  angle: rotation,
                  child: Transform.scale(
                    scale: scale,
                    child: _badge(),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        Opacity(
          opacity: textOpacity,
          child: Column(
            children: [
              Text('Car App',
                  style: GoogleFonts.fredoka(
                      color: Colors.white,
                      fontSize: 44,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.5)),
              const SizedBox(height: 6),
              Text('Control your robot cars',
                  style: GoogleFonts.fredoka(
                      color: Colors.white.withValues(alpha: 0.86),
                      fontSize: 16,
                      fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _badge() {
    return Container(
      width: 132,
      height: 132,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(40),
        boxShadow: [
          BoxShadow(
              color: const Color(0xFF281E78).withValues(alpha: 0.34),
              blurRadius: 50,
              offset: const Offset(0, 22)),
        ],
      ),
      child: const Padding(padding: EdgeInsets.all(20), child: AppLogo(size: 92)),
    );
  }

  // Expanding ring that fades out, looping. [phase] offsets the second ring.
  Widget _ring(double phase) {
    final t = (_loop.value + phase) % 1.0;
    final scale = 0.85 + t * 0.6;
    final opacity = (1 - t) * 0.5 * _interval(_enter.value, 0.5, 0.7);
    return Opacity(
      opacity: opacity.clamp(0.0, 1.0),
      child: Transform.scale(
        scale: scale,
        child: Container(
          width: 140,
          height: 140,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(46),
            border: Border.all(color: Colors.white.withValues(alpha: 0.55), width: 2),
          ),
        ),
      ),
    );
  }

  Widget _loadingDots() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(3, (i) {
        final t = (_loop.value + i * 0.16) % 1.0;
        final tri = t < 0.5 ? t * 2 : (1 - t) * 2; // triangle wave 0..1
        return Container(
          width: 11,
          height: 11,
          margin: const EdgeInsets.symmetric(horizontal: 5.5),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.4 + 0.55 * tri),
            shape: BoxShape.circle,
          ),
        );
      }),
    );
  }

  Widget _blob(double size, Color color,
      {double? top, double? bottom, double? left, double? right}) {
    return Positioned(
      top: top,
      bottom: bottom,
      left: left,
      right: right,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }

  Widget _dotlet(double size, Color color,
      {double? top, double? bottom, double? left, double? right, bool glow = false}) {
    return Positioned(
      top: top,
      bottom: bottom,
      left: left,
      right: right,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: glow
              ? [BoxShadow(color: color.withValues(alpha: 0.25), spreadRadius: 6)]
              : null,
        ),
      ),
    );
  }
}
