import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../main.dart';

/// A toast-style banner that slides in from the TOP of the screen and
/// auto-dismisses. Used for connection errors and quick confirmations,
/// instead of the bottom snackbar.
class TopNotification {
  static OverlayEntry? _current;

  static void show(
    BuildContext context, {
    required String message,
    Color color = kRedD,
    IconData icon = Icons.wifi_off_rounded,
    Duration duration = const Duration(seconds: 4),
  }) {
    final overlay = Overlay.of(context);
    // Replace any banner already on screen.
    _current?.remove();
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _Banner(
        message: message,
        color: color,
        icon: icon,
        duration: duration,
        onDismiss: () {
          if (_current == entry) _current = null;
          entry.remove();
        },
      ),
    );
    _current = entry;
    overlay.insert(entry);
  }
}

class _Banner extends StatefulWidget {
  final String message;
  final Color color;
  final IconData icon;
  final Duration duration;
  final VoidCallback onDismiss;

  const _Banner({
    required this.message,
    required this.color,
    required this.icon,
    required this.duration,
    required this.onDismiss,
  });

  @override
  State<_Banner> createState() => _BannerState();
}

class _BannerState extends State<_Banner> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 280));
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _c.forward();
    _timer = Timer(widget.duration, _close);
  }

  Future<void> _close() async {
    _timer?.cancel();
    if (!mounted) return;
    await _c.reverse();
    widget.onDismiss();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final slide = Tween<Offset>(begin: const Offset(0, -1.2), end: Offset.zero)
        .animate(CurvedAnimation(parent: _c, curve: Curves.easeOutCubic));
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: SlideTransition(
            position: slide,
            child: FadeTransition(
              opacity: _c,
              child: Material(
                color: Colors.transparent,
                child: GestureDetector(
                  onTap: _close,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: widget.color,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                            color: widget.color.withValues(alpha: 0.4),
                            blurRadius: 18,
                            offset: const Offset(0, 6)),
                      ],
                    ),
                    child: Row(
                      children: [
                        Icon(widget.icon, color: Colors.white),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(widget.message,
                              style: GoogleFonts.fredoka(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
