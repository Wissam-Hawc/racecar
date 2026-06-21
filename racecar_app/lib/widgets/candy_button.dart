import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../main.dart';

/// The "candy" button: indigo gradient with a solid 3D bottom edge and a glow,
/// and a press-down animation. Used as the primary action across the app.
class CandyButton extends StatefulWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool loading;
  final double height;
  final double radius;

  const CandyButton({
    super.key,
    required this.label,
    this.icon,
    this.onTap,
    this.loading = false,
    this.height = 60,
    this.radius = 19,
  });

  @override
  State<CandyButton> createState() => _CandyButtonState();
}

class _CandyButtonState extends State<CandyButton> {
  bool _down = false;

  bool get _enabled => widget.onTap != null && !widget.loading;

  @override
  Widget build(BuildContext context) {
    final pressed = _down && _enabled;
    return Opacity(
      opacity: _enabled ? 1 : 0.65,
      child: GestureDetector(
        onTapDown: _enabled ? (_) => setState(() => _down = true) : null,
        onTapUp: _enabled ? (_) => setState(() => _down = false) : null,
        onTapCancel: _enabled ? () => setState(() => _down = false) : null,
        onTap: _enabled ? widget.onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          transform: Matrix4.translationValues(0, pressed ? 4 : 0, 0),
          height: widget.height,
          decoration: BoxDecoration(
            gradient: kCandyGradient,
            borderRadius: BorderRadius.circular(widget.radius),
            boxShadow: [
              BoxShadow(
                color: kIndigoDD,
                offset: Offset(0, pressed ? 3 : 7),
                blurRadius: 0,
              ),
              BoxShadow(
                color: kIndigo.withValues(alpha: 0.42),
                offset: Offset(0, pressed ? 8 : 16),
                blurRadius: pressed ? 16 : 26,
              ),
            ],
          ),
          child: Center(
            child: widget.loading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.6, color: Colors.white))
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.icon != null) ...[
                        Icon(widget.icon, color: Colors.white, size: 22),
                        const SizedBox(width: 10),
                      ],
                      Text(
                        widget.label,
                        style: GoogleFonts.fredoka(
                          color: Colors.white,
                          fontSize: 19,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

/// A green dot with an outward pulsing ring — the "Connected" indicator.
class PulseDot extends StatefulWidget {
  final Color color;
  final double size;
  const PulseDot({super.key, this.color = kGreen, this.size = 11});

  @override
  State<PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))
        ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, child) {
          final t = _c.value;
          return Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              Transform.scale(
                scale: 1 + t * 1.6,
                child: Opacity(
                  opacity: (1 - t) * 0.6,
                  child: Container(
                    decoration: BoxDecoration(
                        color: widget.color, shape: BoxShape.circle),
                  ),
                ),
              ),
              Container(
                decoration:
                    BoxDecoration(color: widget.color, shape: BoxShape.circle),
              ),
            ],
          );
        },
      ),
    );
  }
}
