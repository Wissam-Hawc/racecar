import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mqtt_client/mqtt_client.dart' show MqttQos;

import '../main.dart';
import '../mqtt_topics.dart';
import '../services/mqtt_service.dart';
import '../widgets/app_logo.dart';
import '../widgets/camera_view.dart';
import '../widgets/candy_button.dart';
import 'race_lobby_screen.dart';

/// Driving screen for one car. Publishes drive + mode commands over MQTT and
/// shows telemetry / camera.
///
/// Landscape: the camera fills the screen and the controls float on top
/// (RC / FPV style). Portrait: camera on top, controls in a panel below.
class DriveScreen extends StatefulWidget {
  final MqttService mqtt;
  final String carId;

  const DriveScreen({super.key, required this.mqtt, required this.carId});

  @override
  State<DriveScreen> createState() => _DriveScreenState();
}

class _DriveScreenState extends State<DriveScreen> {
  String _mode = 'MANUAL';
  bool _cameraOn = false;
  String? _activeCmd;
  Timer? _repeatTimer;
  double? _distanceCm;

  MqttService get _mqtt => widget.mqtt;
  String get _driveTopic => Topics.driveCmd(widget.carId);
  String get _modeTopic => Topics.modeCmd(widget.carId);
  String get _cameraTopic => Topics.cameraCmd(widget.carId);
  String get _telemetryTopic => Topics.telemetry(widget.carId);

  @override
  void initState() {
    super.initState();
    _mqtt.addListener(_onServiceChanged);
    _mqtt.subscribe(_telemetryTopic);
    _mqtt.publish(_modeTopic, 'MANUAL', qos: MqttQos.atLeastOnce, retain: true);
  }

  void _onServiceChanged() {
    for (final entry in _mqtt.log) {
      if (entry.topic == _telemetryTopic) {
        _parseTelemetry(entry.payload);
        break;
      }
    }
    if (mounted) setState(() {});
  }

  void _parseTelemetry(String payload) {
    try {
      final map = jsonDecode(payload) as Map<String, dynamic>;
      _distanceCm = (map['distance_cm'] as num?)?.toDouble();
    } catch (_) {}
  }

  @override
  void dispose() {
    _repeatTimer?.cancel();
    _mqtt.removeListener(_onServiceChanged);
    super.dispose();
  }

  // --- Command sending ------------------------------------------------------
  void _startCommand(String cmd) {
    if (_mode != 'MANUAL') return;
    setState(() => _activeCmd = cmd);
    _mqtt.publish(_driveTopic, cmd);
    _repeatTimer?.cancel();
    _repeatTimer = Timer.periodic(
      const Duration(milliseconds: 100),
      (_) => _mqtt.publish(_driveTopic, cmd),
    );
  }

  void _stopCommand() {
    _repeatTimer?.cancel();
    _repeatTimer = null;
    setState(() => _activeCmd = null);
    _mqtt.publish(_driveTopic, 'STOP');
  }

  void _setMode(String mode) {
    setState(() => _mode = mode);
    _mqtt.publish(_modeTopic, mode, qos: MqttQos.atLeastOnce, retain: true);
    if (mode != 'MANUAL') _stopCommand();
  }

  void _toggleCamera() {
    setState(() => _cameraOn = !_cameraOn);
    _mqtt.publish(_cameraTopic, _cameraOn ? 'ON' : 'OFF',
        qos: MqttQos.atLeastOnce);
  }

  Future<void> _promptCarIp() async {
    final controller =
        TextEditingController(text: _mqtt.carIp[widget.carId] ?? '');
    final ip = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Car's IP address"),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'e.g. 192.168.1.50'),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('Save')),
        ],
      ),
    );
    if (ip != null && ip.isNotEmpty) _mqtt.setCarIp(widget.carId, ip);
  }

  void _openRace() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => _RaceEntrySheet(
        onHost: () {
          Navigator.pop(ctx);
          _pushLobby(isHost: true);
        },
        onJoin: (code) {
          Navigator.pop(ctx);
          _pushLobby(isHost: false, code: code);
        },
      ),
    );
  }

  void _pushLobby({required bool isHost, String? code}) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => RaceLobbyScreen(
        mqtt: _mqtt,
        carId: widget.carId,
        isHost: isHost,
        roomCode: code,
      ),
    ));
  }

  // --- UI -------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: OrientationBuilder(
        builder: (context, orientation) => orientation == Orientation.landscape
            ? _buildLandscape()
            : _buildPortrait(),
      ),
    );
  }

  // Fullscreen camera with floating controls.
  Widget _buildLandscape() {
    final enabled = _mode == 'MANUAL';
    return Stack(
      children: [
        Positioned.fill(
                      child: CameraView(
                          on: _cameraOn,
                          host: _mqtt.carIp[widget.carId],
                          onSetIp: _promptCarIp)),
        // Top scrim for legibility of the controls.
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Container(
            height: 110,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black.withValues(alpha: 0.55), Colors.transparent],
              ),
            ),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                _buildTopBar(overlay: true),
                const Spacer(),
                // D-pad bottom-left, STOP (brake) bottom-right.
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _buildDpadSection(enabled: enabled, overlay: true),
                    const Spacer(),
                    _StopButton(enabled: enabled, onTap: _stopCommand),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPortrait() {
    final enabled = _mode == 'MANUAL';
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: _buildTopBar(overlay: false),
          ),
          Expanded(
            flex: 5,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: CameraView(
                          on: _cameraOn,
                          host: _mqtt.carIp[widget.carId],
                          onSetIp: _promptCarIp)),
                    // Distance only matters in self-drive; hide it in manual.
                    if (_mode == 'AUTO')
                      Positioned(top: 12, right: 12, child: _telemetryPill()),
                  ],
                ),
              ),
            ),
          ),
          // Control panel — a large section, balanced with the camera.
          Expanded(
            flex: 4,
            child: Container(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                      color: const Color(0xFF3C3282).withValues(alpha: 0.08),
                      blurRadius: 24,
                      offset: const Offset(0, -4)),
                ],
              ),
              child: Column(
                children: [
                  _ModeSelector(
                      mode: _mode, overlay: false, onChanged: _setMode),
                  // D-pad (scales to fit) on the left, STOP (brake) on the right.
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(
                          child: Center(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: _buildDpadSection(
                                  enabled: enabled, overlay: false, size: 76),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _StopButton(enabled: enabled, onTap: _stopCommand),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar({required bool overlay}) {
    final fg = overlay ? Colors.white : Colors.black87;
    return Row(
      children: [
        _GlassIconButton(
          icon: Icons.arrow_back,
          overlay: overlay,
          onTap: () => Navigator.of(context).pop(),
        ),
        const SizedBox(width: 8),
        _Glass(
          overlay: overlay,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppLogo(size: 22, fallbackColor: fg),
              const SizedBox(width: 8),
              Text('Car ${widget.carId}',
                  style: TextStyle(color: fg, fontWeight: FontWeight.w600)),
              const SizedBox(width: 8),
              Icon(Icons.circle,
                  size: 10,
                  color: _mqtt.isConnected ? Colors.greenAccent : Colors.red),
            ],
          ),
        ),
        const Spacer(),
        // In portrait the mode selector lives in the bottom panel, so the top
        // bar only needs it in the landscape (overlay) layout.
        if (overlay) ...[
          // Distance only shown in self-drive mode.
          if (_mode == 'AUTO') ...[
            _telemetryPill(),
            const SizedBox(width: 8),
          ],
          _ModeSelector(mode: _mode, overlay: overlay, onChanged: _setMode),
          const SizedBox(width: 8),
        ],
        _RacePill(onTap: _openRace),
        const SizedBox(width: 8),
        _GlassIconButton(
          icon: _cameraOn ? Icons.videocam : Icons.videocam_off,
          overlay: overlay,
          onTap: _toggleCamera,
        ),
      ],
    );
  }

  Widget _telemetryPill() {
    final txt = _distanceCm != null
        ? '${_distanceCm!.toStringAsFixed(0)} cm'
        : '— cm';
    return _Glass(
      overlay: true,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.straighten, size: 16, color: Colors.white),
          const SizedBox(width: 6),
          Text(txt, style: const TextStyle(color: Colors.white)),
        ],
      ),
    );
  }

  Widget _buildDpad(
      {required bool enabled, required bool overlay, double size = 62}) {
    Widget btn(IconData icon, String cmd) => _DirButton(
          icon: icon,
          active: _activeCmd == cmd,
          enabled: enabled,
          overlay: overlay,
          size: size,
          onDown: () => _startCommand(cmd),
          onUp: _stopCommand,
        );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        btn(Icons.keyboard_arrow_up, 'FWD'),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            btn(Icons.keyboard_arrow_left, 'LEFT'),
            const SizedBox(width: 18),
            // Center "core" dot so the cross reads as one piece.
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: overlay ? Colors.white24 : kIndigo200,
              ),
            ),
            const SizedBox(width: 18),
            btn(Icons.keyboard_arrow_right, 'RIGHT'),
          ],
        ),
        btn(Icons.keyboard_arrow_down, 'BACK'),
      ],
    );
  }

  // D-pad with the "self-driving — controls locked" overlay on top when AUTO.
  Widget _buildDpadSection(
      {required bool enabled, required bool overlay, double size = 62}) {
    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        _buildDpad(enabled: enabled, overlay: overlay, size: size),
        if (_mode == 'AUTO')
          Positioned.fill(child: _DpadLockOverlay(overlay: overlay)),
      ],
    );
  }
}

// ===========================================================================
//  Reusable styled widgets
// ===========================================================================

/// Translucent rounded panel — looks good floating over the video.
class _Glass extends StatelessWidget {
  final Widget child;
  final bool overlay;
  final EdgeInsets padding;
  const _Glass(
      {required this.child, required this.overlay, required this.padding});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: overlay
            ? Colors.black.withValues(alpha: 0.4)
            : Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: child,
    );
  }
}

class _GlassIconButton extends StatelessWidget {
  final IconData icon;
  final bool overlay;
  final VoidCallback onTap;
  const _GlassIconButton(
      {required this.icon, required this.overlay, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final fg = overlay ? Colors.white : Colors.black87;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: _Glass(
        overlay: overlay,
        padding: const EdgeInsets.all(10),
        child: Icon(icon, color: fg, size: 22),
      ),
    );
  }
}

/// Manual / Auto / Stop selector. Compact pills that read well on dark video.
/// Bottom sheet to host a new race or join one with a room code.
class _RaceEntrySheet extends StatefulWidget {
  final VoidCallback onHost;
  final ValueChanged<String> onJoin;
  const _RaceEntrySheet({required this.onHost, required this.onJoin});

  @override
  State<_RaceEntrySheet> createState() => _RaceEntrySheetState();
}

class _RaceEntrySheetState extends State<_RaceEntrySheet> {
  final _code = TextEditingController();

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  String _clean(String s) =>
      s.trim().toUpperCase().replaceFirst(RegExp(r'^R4CE-?'), '');

  @override
  Widget build(BuildContext context) {
    final code = _clean(_code.text);
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            24, 22, 24, 24 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: kLine, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 18),
          Text('Start a race',
              style: GoogleFonts.fredoka(
                  fontSize: 22, fontWeight: FontWeight.w600, color: kInk)),
          const SizedBox(height: 4),
          const Text('Host a room and share the code, or join one.',
              style: TextStyle(color: kMuted, fontWeight: FontWeight.w600)),
          const SizedBox(height: 20),
          CandyButton(
              label: 'Host a new race',
              icon: Icons.add,
              onTap: widget.onHost),
          const SizedBox(height: 20),
          Row(children: [
            const Expanded(child: Divider(color: kLine)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text('or join with a code',
                  style: TextStyle(
                      color: kMuted,
                      fontWeight: FontWeight.w600,
                      fontSize: 12.5)),
            ),
            const Expanded(child: Divider(color: kLine)),
          ]),
          const SizedBox(height: 16),
          TextField(
            controller: _code,
            autocorrect: false,
            textCapitalization: TextCapitalization.characters,
            onChanged: (_) => setState(() {}),
            style: GoogleFonts.fredoka(
                fontSize: 18, fontWeight: FontWeight.w500, letterSpacing: 2),
            decoration: InputDecoration(
              prefixText: 'R4CE-',
              prefixStyle: GoogleFonts.fredoka(
                  fontSize: 18, color: kMuted, fontWeight: FontWeight.w500),
              hintText: '7K2',
              filled: true,
              fillColor: kIndigo50,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: kIndigo100, width: 2),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: kIndigo, width: 2),
              ),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 52,
            child: OutlinedButton.icon(
              onPressed:
                  code.isEmpty ? null : () => widget.onJoin(code),
              icon: const Icon(Icons.login),
              label: Text('Join race',
                  style: GoogleFonts.fredoka(
                      fontWeight: FontWeight.w600, fontSize: 16)),
              style: OutlinedButton.styleFrom(
                foregroundColor: kIndigoD,
                side: const BorderSide(color: kIndigo, width: 1.6),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
        ],
        ),
      ),
    );
  }
}

/// Red STOP button — publishes STOP, which the L298N brakes on.
class _StopButton extends StatelessWidget {
  final bool enabled;
  final VoidCallback onTap;
  const _StopButton({required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Opacity(
        opacity: enabled ? 1 : 0.4,
        child: Container(
          width: 84,
          height: 84,
          decoration: BoxDecoration(
            color: const Color(0xFFE53935),
            shape: BoxShape.circle,
            boxShadow: enabled
                ? [
                    BoxShadow(
                        color: Colors.red.withValues(alpha: 0.4),
                        blurRadius: 16,
                        spreadRadius: 1),
                  ]
                : null,
          ),
          child: const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.stop, size: 34, color: Colors.white),
              Text('STOP',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Amber "Race" pill that opens the race lobby.
class _RacePill extends StatelessWidget {
  final VoidCallback onTap;
  const _RacePill({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          gradient: kRaceGradient,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
          boxShadow: [
            BoxShadow(
                color: kAmberD.withValues(alpha: 0.4),
                blurRadius: 12,
                offset: const Offset(0, 4)),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.sports_score, color: Colors.white, size: 18),
            const SizedBox(width: 6),
            Text('Race',
                style: GoogleFonts.fredoka(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 15)),
          ],
        ),
      ),
    );
  }
}

class _ModeSelector extends StatelessWidget {
  final String mode;
  final bool overlay;
  final ValueChanged<String> onChanged;
  const _ModeSelector(
      {required this.mode, required this.overlay, required this.onChanged});

  static const _items = [
    ('MANUAL', Icons.gamepad, 'Manual'),
    ('AUTO', Icons.smart_toy, 'Auto'),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _Glass(
      overlay: overlay,
      padding: const EdgeInsets.all(4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (value, icon, label) in _items)
            GestureDetector(
              onTap: () => onChanged(value),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: mode == value
                      ? (overlay ? Colors.white : scheme.primary)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon,
                        size: 16,
                        color: mode == value
                            ? (overlay ? Colors.black : Colors.white)
                            : (overlay ? Colors.white70 : Colors.black54)),
                    const SizedBox(width: 4),
                    Text(label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: mode == value
                              ? (overlay ? Colors.black : Colors.white)
                              : (overlay ? Colors.white70 : Colors.black54),
                        )),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Press-and-hold direction button. Publishes while held, stops on release.
class _DirButton extends StatelessWidget {
  final IconData icon;
  final bool active;
  final bool enabled;
  final bool overlay;
  final VoidCallback onDown;
  final VoidCallback onUp;
  final double size;

  const _DirButton({
    required this.icon,
    required this.active,
    required this.enabled,
    required this.overlay,
    required this.onDown,
    required this.onUp,
    this.size = 62,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Color bg;
    Color fg;
    if (overlay) {
      bg = !enabled
          ? Colors.white.withValues(alpha: 0.08)
          : active
              ? Colors.white
              : Colors.black.withValues(alpha: 0.45);
      fg = !enabled
          ? Colors.white24
          : active
              ? Colors.black
              : Colors.white;
    } else {
      bg = !enabled
          ? scheme.surfaceContainerHighest
          : active
              ? scheme.primary
              : scheme.primaryContainer;
      fg = !enabled
          ? scheme.outline
          : active
              ? scheme.onPrimary
              : scheme.onPrimaryContainer;
    }
    return Padding(
      padding: const EdgeInsets.all(5),
      child: Listener(
        onPointerDown: enabled ? (_) => onDown() : null,
        onPointerUp: enabled ? (_) => onUp() : null,
        onPointerCancel: enabled ? (_) => onUp() : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(size * 0.26),
          ),
          child: Icon(icon, size: size * 0.55, color: fg),
        ),
      ),
    );
  }
}

/// Overlay shown on top of the D-pad in AUTO mode — the controls are locked
/// because the car drives itself.
class _DpadLockOverlay extends StatelessWidget {
  final bool overlay;
  const _DpadLockOverlay({required this.overlay});

  @override
  Widget build(BuildContext context) {
    final bg = overlay
        ? Colors.black.withValues(alpha: 0.62)
        : kIndigo50.withValues(alpha: 0.94);
    final fg = overlay ? Colors.white : kIndigoD;
    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: fg.withValues(alpha: 0.25)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.lock, color: fg, size: 26),
          const SizedBox(height: 6),
          Text('Self-driving',
              style: TextStyle(
                  color: fg, fontWeight: FontWeight.w700, fontSize: 14)),
          Text('controls locked',
              style: TextStyle(
                  color: fg.withValues(alpha: 0.7), fontSize: 11)),
        ],
      ),
    );
  }
}
