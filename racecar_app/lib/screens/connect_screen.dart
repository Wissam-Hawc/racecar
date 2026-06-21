import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:google_fonts/google_fonts.dart';

import '../main.dart';
import '../services/mqtt_service.dart';
import '../widgets/app_logo.dart';
import '../widgets/candy_button.dart';
import '../widgets/top_notification.dart';
import 'car_select_screen.dart';

class ConnectScreen extends StatefulWidget {
  final MqttService mqtt;

  const ConnectScreen({super.key, required this.mqtt});

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  final _hostController = TextEditingController(text: '192.168.1.14');

  MqttService get _mqtt => widget.mqtt;

  @override
  void initState() {
    super.initState();
    _mqtt.addListener(_onServiceChanged);
  }

  void _onServiceChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _mqtt.removeListener(_onServiceChanged);
    _hostController.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    await _mqtt.connect(
      host: _hostController.text.trim(),
      clientId: 'flutter-${defaultTargetPlatform.name}-'
          '${DateTime.now().millisecondsSinceEpoch}',
    );
    if (!mounted) return;
    if (_mqtt.isConnected) {
      TopNotification.show(
        context,
        message: 'Connected to broker',
        color: kGreenD,
        icon: Icons.check_circle_rounded,
        duration: const Duration(seconds: 2),
      );
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => CarSelectScreen(mqtt: _mqtt),
      ));
    } else {
      // Don't fail silently — tell the user what went wrong.
      _showError(
        "Couldn't reach the broker at ${_hostController.text.trim()}.\n"
        'Check the IP, that the broker is running, and that the phone is '
        'on the same Wi-Fi.',
      );
    }
  }

  void _showError(String message) {
    TopNotification.show(context, message: message);
  }

  @override
  Widget build(BuildContext context) {
    // Screen orientation (stable), not OrientationBuilder: the latter keys off
    // its box size, which shrinks when the keyboard opens and would flip the
    // layout mid-typing, dropping focus on the broker IP field.
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    return Scaffold(
      backgroundColor: kBg,
      body: isLandscape ? _buildLandscape() : _buildPortrait(),
    );
  }

  // ---- Portrait: hero fills the top, white card overlaps the bottom -------
  Widget _buildPortrait() {
    return LayoutBuilder(
      builder: (context, c) {
        final h = c.maxHeight;
        final bottomInset = MediaQuery.of(context).padding.bottom;
        final cardTop = h * 0.43;
        return Stack(
          children: [
            // Gradient bleeds behind the card's rounded top corners.
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: h * 0.56,
              child: const _HeroBackdrop(),
            ),
            // Branding centered in the VISIBLE gradient area (above the card),
            // so the tagline never slips under the card.
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: cardTop,
              child: const SafeArea(
                bottom: false,
                child: Center(child: _Branding(large: false)),
              ),
            ),
            // White card overlapping the lower part, full width.
            Positioned(
              top: cardTop,
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(32)),
                  boxShadow: [
                    BoxShadow(
                        color: const Color(0xFF281E78).withValues(alpha: 0.16),
                        blurRadius: 34,
                        offset: const Offset(0, -10)),
                  ],
                ),
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(26, 28, 26, 28 + bottomInset),
                  child: _form(),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // ---- Landscape: split screen --------------------------------------------
  Widget _buildLandscape() {
    return Row(
      children: [
        Expanded(
          flex: 42,
          child: const _HeroBackdrop(
            landscape: true,
            child: _Branding(large: true),
          ),
        ),
        Expanded(
          flex: 58,
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 34),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 430),
                child: _form(),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // The white-area form, shared by both layouts.
  Widget _form() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Connect to broker',
            style: GoogleFonts.fredoka(
                fontSize: 25, fontWeight: FontWeight.w600, color: kInk)),
        const SizedBox(height: 4),
        Text('Enter your gateway address to start',
            style: const TextStyle(
                color: kMuted, fontWeight: FontWeight.w600, fontSize: 14.5)),
        const SizedBox(height: 22),
        Text('BROKER IP',
            style: GoogleFonts.fredoka(
                fontSize: 14, fontWeight: FontWeight.w600, color: kInkSoft)),
        const SizedBox(height: 9),
        _BrokerField(controller: _hostController),
        const SizedBox(height: 18),
        _StatusRow(status: _mqtt.status, error: _mqtt.lastError),
        const SizedBox(height: 24),
        CandyButton(
          label: _mqtt.status == BrokerStatus.connecting
              ? 'Connecting…'
              : 'Connect',
          icon: Icons.bolt_rounded,
          loading: _mqtt.status == BrokerStatus.connecting,
          onTap: _mqtt.status == BrokerStatus.connecting ? null : _connect,
        ),
      ],
    );
  }
}

/// Gradient backdrop with decorative blobs. Optionally centers [child].
class _HeroBackdrop extends StatelessWidget {
  final bool landscape;
  final Widget? child;
  const _HeroBackdrop({this.landscape = false, this.child});

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: DecoratedBox(
        decoration: BoxDecoration(
            gradient: landscape ? kHeroGradientLand : kHeroGradient),
        child: Stack(
          children: [
            _blob(200, 200, Colors.white.withValues(alpha: 0.10),
                top: -60, right: -50),
            _blob(130, 130, const Color(0xFFF88E70).withValues(alpha: 0.5),
                bottom: 0, left: -44),
            Positioned(
              top: 60,
              left: 34,
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: kAmber,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                        color: kAmber.withValues(alpha: 0.25),
                        spreadRadius: 6),
                  ],
                ),
              ),
            ),
            _blob(8, 8, Colors.white.withValues(alpha: 0.55),
                top: 130, right: 60),
            if (child != null)
              Positioned.fill(
                child: SafeArea(bottom: false, child: Center(child: child)),
              ),
          ],
        ),
      ),
    );
  }

  static Widget _blob(double w, double h, Color color,
      {double? top, double? bottom, double? left, double? right}) {
    return Positioned(
      top: top,
      bottom: bottom,
      left: left,
      right: right,
      child: Container(
        width: w,
        height: h,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}

/// Branding block: squircle badge + app name + tagline.
class _Branding extends StatelessWidget {
  final bool large;
  const _Branding({required this.large});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Badge(size: large ? 104 : 120),
        SizedBox(height: large ? 18 : 22),
        Text('Car App',
            style: GoogleFonts.fredoka(
                color: Colors.white,
                fontSize: large ? 38 : 42,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.5)),
        const SizedBox(height: 4),
        Text('Control your robot cars',
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.85),
                fontWeight: FontWeight.w600,
                fontSize: 16)),
      ],
    );
  }
}

/// White squircle badge holding the logo, tilted slightly.
class _Badge extends StatelessWidget {
  final double size;
  const _Badge({required this.size});

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: -0.07, // ~ -4 degrees
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(size * 0.31),
          boxShadow: [
            BoxShadow(
                color: const Color(0xFF281E78).withValues(alpha: 0.30),
                blurRadius: 40,
                offset: const Offset(0, 18)),
          ],
        ),
        child: Padding(
          padding: EdgeInsets.all(size * 0.2),
          child: Transform.rotate(angle: 0.07, child: AppLogo(size: size)),
        ),
      ),
    );
  }
}

/// Styled broker-IP input with a white icon chip.
class _BrokerField extends StatelessWidget {
  final TextEditingController controller;
  const _BrokerField({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: kIndigo50,
        border: Border.all(color: kIndigo100, width: 2),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(11),
              boxShadow: [
                BoxShadow(
                    color: kIndigo.withValues(alpha: 0.18),
                    blurRadius: 6,
                    offset: const Offset(0, 2)),
              ],
            ),
            child: const Icon(Icons.dns_rounded, size: 19, color: kIndigo),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: controller,
              cursorColor: kIndigo,
              style: GoogleFonts.fredoka(
                  fontSize: 19,
                  fontWeight: FontWeight.w500,
                  color: kInk,
                  letterSpacing: 0.4),
              decoration: const InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: '192.168.1.14',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Connection status line (pulsing dot when connected).
class _StatusRow extends StatelessWidget {
  final BrokerStatus status;
  final String? error;
  const _StatusRow({required this.status, this.error});

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (status) {
      BrokerStatus.disconnected => (kMuted, 'Not connected'),
      BrokerStatus.connecting => (kAmber, 'Connecting…'),
      BrokerStatus.connected => (kGreenD, 'Connected'),
      BrokerStatus.error => (kRedD, error ?? 'Connection failed'),
    };
    return Row(
      children: [
        if (status == BrokerStatus.connected)
          const PulseDot()
        else
          Container(
            width: 11,
            height: 11,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
        const SizedBox(width: 9),
        Expanded(
          child: Text(label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.fredoka(
                  color: color, fontWeight: FontWeight.w600, fontSize: 15)),
        ),
      ],
    );
  }
}
