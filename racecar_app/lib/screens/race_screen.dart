import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../main.dart';
import '../mqtt_topics.dart';
import '../services/mqtt_service.dart';
import '../widgets/camera_view.dart';
import '../widgets/candy_button.dart';

enum _Phase { countdown, racing, finished }

/// The race: 3·2·1 countdown, live driving with a VS HUD + timer, then a
/// win/lose result. Driving uses the same `cars/<id>/cmd/drive` topic.
///
/// The finish is decided by the finish-line judge ESP, which publishes one
/// `race/result` message per finisher: {time, playerName, playerColor}. The
/// fastest time wins. Players are matched by colour, not car id.
class RaceScreen extends StatefulWidget {
  final MqttService mqtt;
  final String carId; // the car this phone drives
  final String myName;
  final String myColor; // 'red' | 'blue'
  final String? oppName;
  final String? oppColor;

  const RaceScreen({
    super.key,
    required this.mqtt,
    required this.carId,
    required this.myName,
    required this.myColor,
    required this.oppName,
    required this.oppColor,
  });

  @override
  State<RaceScreen> createState() => _RaceScreenState();
}

class _RaceScreenState extends State<RaceScreen> {
  _Phase _phase = _Phase.countdown;
  int _count = 3;
  bool _cameraOn = false;

  // Finish results from the judge ESP: colour -> time (seconds) / name.
  final Map<String, double> _times = {};
  final Map<String, String> _resultNames = {};
  String? _winnerColor;

  // Result messages already accounted for. The MQTT log persists across
  // screens, so we mark everything present at open (and everything seen since)
  // to avoid a stale result from a previous race ending this one instantly.
  final Set<MqttLogEntry> _seenResults = {};

  Duration _elapsed = Duration.zero;
  Timer? _countdownTimer;
  Timer? _clockTimer;
  Timer? _repeatTimer;
  String? _activeCmd;

  MqttService get _mqtt => widget.mqtt;
  String get _driveTopic => Topics.driveCmd(widget.carId);
  bool get _won => _winnerColor == widget.myColor;

  @override
  void initState() {
    super.initState();
    // Ignore any results already in the log from an earlier race this session.
    for (final e in _mqtt.log) {
      if (e.topic == Topics.raceResult) _seenResults.add(e);
    }
    _mqtt.addListener(_onMsg);
    _mqtt.subscribe(Topics.raceResult);
    _startCountdown();
  }

  void _startCountdown() {
    _count = 3;
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      setState(() => _count--);
      if (_count <= 0) {
        t.cancel();
        _beginRacing();
      }
    });
  }

  void _beginRacing() {
    setState(() => _phase = _Phase.racing);
    _clockTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      setState(() => _elapsed += const Duration(milliseconds: 200));
    });
  }

  // Listen for finish results from the judge ESP. Each log entry is processed
  // once (tracked by identity), so a rematch isn't ended by old results.
  void _onMsg() {
    for (final entry in _mqtt.log) {
      if (entry.topic == Topics.raceResult && _seenResults.add(entry)) {
        _handleResult(entry.payload);
      }
    }
    if (mounted) setState(() {});
  }

  void _handleResult(String payload) {
    try {
      final m = jsonDecode(payload) as Map;
      final color = m['playerColor']?.toString();
      final time = (m['time'] as num?)?.toDouble();
      if (color == null || time == null) return;
      if (_times.containsKey(color)) return; // already recorded this finisher
      _times[color] = time;
      final name = m['playerName']?.toString();
      if (name != null && name.isNotEmpty) _resultNames[color] = name;
      _decideWinner();
    } catch (_) {
      // ignore malformed messages
    }
  }

  // Winner = the smallest finish time seen so far (first across the line).
  void _decideWinner() {
    if (_times.isEmpty) return;
    var winner = _times.entries.first;
    for (final e in _times.entries) {
      if (e.value < winner.value) winner = e;
    }
    _winnerColor = winner.key;
    if (_phase != _Phase.finished) _finish();
  }

  void _finish() {
    _clockTimer?.cancel();
    _repeatTimer?.cancel();
    _mqtt.publish(_driveTopic, 'STOP');
    setState(() => _phase = _Phase.finished);
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _clockTimer?.cancel();
    _repeatTimer?.cancel();
    _mqtt.removeListener(_onMsg);
    super.dispose();
  }

  // --- driving --------------------------------------------------------------
  void _startCommand(String cmd) {
    if (_phase != _Phase.racing) return;
    setState(() => _activeCmd = cmd);
    _mqtt.publish(_driveTopic, cmd);
    _repeatTimer?.cancel();
    _repeatTimer = Timer.periodic(const Duration(milliseconds: 100),
        (_) => _mqtt.publish(_driveTopic, cmd));
  }

  void _stopCommand() {
    _repeatTimer?.cancel();
    _repeatTimer = null;
    setState(() => _activeCmd = null);
    _mqtt.publish(_driveTopic, 'STOP');
  }

  String get _clock {
    final m = _elapsed.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = _elapsed.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kDark,
      body: Stack(
        children: [
          Positioned.fill(child: _camera()),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  _hud(),
                  const SizedBox(height: 10),
                  _vsBar(),
                  const Spacer(),
                  if (_phase == _Phase.racing)
                    Align(
                        alignment: Alignment.bottomLeft,
                        child: _dpad(enabled: true)),
                ],
              ),
            ),
          ),
          if (_phase == _Phase.countdown) _countdownOverlay(),
          if (_phase == _Phase.finished)
            _ResultOverlay(
              won: _won,
              myName: widget.myName,
              myColor: widget.myColor,
              oppName: widget.oppName ?? 'Opponent',
              oppColor: widget.oppColor ?? (widget.myColor == 'red' ? 'blue' : 'red'),
              myTime: _times[widget.myColor],
              oppTime: _times[widget.oppColor],
              onRematch: _rematch,
              onExit: () => Navigator.of(context).pop(),
            ),
        ],
      ),
    );
  }

  void _rematch() {
    setState(() {
      _phase = _Phase.countdown;
      _elapsed = Duration.zero;
      _times.clear();
      _resultNames.clear();
      _winnerColor = null;
    });
    _startCountdown();
  }

  Widget _camera() {
    return CameraView(
      on: _cameraOn,
      host: _mqtt.carIp[widget.carId],
      onSetIp: _promptCarIp,
    );
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
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('Save')),
        ],
      ),
    );
    if (ip != null && ip.isNotEmpty) _mqtt.setCarIp(widget.carId, ip);
  }

  Widget _hud() {
    return Row(
      children: [
        _GlassIcon(icon: Icons.arrow_back, onTap: () => Navigator.pop(context)),
        const SizedBox(width: 8),
        _glass(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            _Dot(color: teamColor(widget.myColor)),
            const SizedBox(width: 8),
            Text(widget.myName,
                style: GoogleFonts.fredoka(
                    color: Colors.white, fontWeight: FontWeight.w600)),
          ]),
        ),
        const Spacer(),
        if (_phase == _Phase.racing) _liveChip(),
        const SizedBox(width: 8),
        _GlassIcon(
            icon: _cameraOn ? Icons.videocam : Icons.videocam_off,
            onTap: () => setState(() => _cameraOn = !_cameraOn)),
      ],
    );
  }

  Widget _liveChip() {
    return _glass(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const PulseDot(color: kRed, size: 9),
        const SizedBox(width: 8),
        Text('LIVE · ',
            style: GoogleFonts.fredoka(
                color: Colors.white, fontWeight: FontWeight.w600)),
        Text(_clock,
            style: GoogleFonts.fredoka(
                color: Colors.white, fontWeight: FontWeight.w600)),
      ]),
    );
  }

  Widget _vsBar() {
    return _glass(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Dot(color: teamColor(widget.myColor)),
          const SizedBox(width: 8),
          Text(widget.myName,
              style: GoogleFonts.fredoka(
                  color: Colors.white, fontWeight: FontWeight.w600)),
          const SizedBox(width: 12),
          Text('VS', style: GoogleFonts.fredoka(color: Colors.white54, fontSize: 13)),
          const SizedBox(width: 12),
          Text(widget.oppName ?? 'Opponent',
              style: GoogleFonts.fredoka(
                  color: Colors.white, fontWeight: FontWeight.w600)),
          const SizedBox(width: 8),
          _Dot(color: teamColor(widget.oppColor)),
        ],
      ),
    );
  }

  Widget _dpad({required bool enabled}) {
    Widget b(IconData i, String cmd) => _RaceDir(
        icon: i,
        active: _activeCmd == cmd,
        enabled: enabled,
        onDown: () => _startCommand(cmd),
        onUp: _stopCommand);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        b(Icons.keyboard_arrow_up, 'FWD'),
        Row(mainAxisSize: MainAxisSize.min, children: [
          b(Icons.keyboard_arrow_left, 'LEFT'),
          const SizedBox(width: 60),
          b(Icons.keyboard_arrow_right, 'RIGHT'),
        ]),
        b(Icons.keyboard_arrow_down, 'BACK'),
      ],
    );
  }

  Widget _countdownOverlay() {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.55),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 128,
              height: 128,
              decoration: BoxDecoration(
                gradient: kCandyGradient,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                      color: kIndigo.withValues(alpha: 0.5),
                      blurRadius: 36,
                      offset: const Offset(0, 12)),
                ],
              ),
              child: Center(
                child: Text(_count > 0 ? '$_count' : 'GO',
                    style: GoogleFonts.fredoka(
                        color: Colors.white,
                        fontSize: _count > 0 ? 72 : 44,
                        fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(height: 18),
            Text('Get ready…',
                style: GoogleFonts.fredoka(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }

  // shared glass helpers
  Widget _glass({required Widget child, required EdgeInsets padding}) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: child,
    );
  }
}

class _GlassIcon extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _GlassIcon({required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.42),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
        ),
        child: Icon(icon, color: Colors.white, size: 22),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  final Color color;
  const _Dot({required this.color});
  @override
  Widget build(BuildContext context) => Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(color: color.withValues(alpha: 0.25), spreadRadius: 3)
          ],
        ),
      );
}

class _RaceDir extends StatelessWidget {
  final IconData icon;
  final bool active;
  final bool enabled;
  final VoidCallback onDown;
  final VoidCallback onUp;
  const _RaceDir(
      {required this.icon,
      required this.active,
      required this.enabled,
      required this.onDown,
      required this.onUp});

  @override
  Widget build(BuildContext context) {
    final bg = !enabled
        ? Colors.white.withValues(alpha: 0.08)
        : active
            ? Colors.white
            : Colors.black.withValues(alpha: 0.45);
    final fg = !enabled
        ? Colors.white24
        : active
            ? Colors.black
            : Colors.white;
    return Padding(
      padding: const EdgeInsets.all(5),
      child: Listener(
        onPointerDown: enabled ? (_) => onDown() : null,
        onPointerUp: enabled ? (_) => onUp() : null,
        onPointerCancel: enabled ? (_) => onUp() : null,
        child: Container(
          width: 60,
          height: 60,
          decoration:
              BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16)),
          child: Icon(icon, size: 32, color: fg),
        ),
      ),
    );
  }
}

/// Win/lose result: trophy, the winner's name + finish times, confetti.
class _ResultOverlay extends StatelessWidget {
  final bool won;
  final String myName;
  final String myColor;
  final String oppName;
  final String oppColor;
  final double? myTime;
  final double? oppTime;
  final VoidCallback onRematch;
  final VoidCallback onExit;
  const _ResultOverlay({
    required this.won,
    required this.myName,
    required this.myColor,
    required this.oppName,
    required this.oppColor,
    required this.myTime,
    required this.oppTime,
    required this.onRematch,
    required this.onExit,
  });

  String _fmt(double? t) => t == null ? '—' : '${t.toStringAsFixed(2)}s';

  @override
  Widget build(BuildContext context) {
    final winnerName = won ? myName : oppName;
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.6),
        child: Stack(
          children: [
            if (won) const _Confetti(),
            Center(
              child: SingleChildScrollView(
                child: Container(
                  margin: const EdgeInsets.all(26),
                  constraints: const BoxConstraints(maxWidth: 360),
                  decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(32)),
                  padding: const EdgeInsets.fromLTRB(26, 36, 26, 26),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 84,
                        height: 84,
                        decoration: BoxDecoration(
                            color: won
                                ? const Color(0xFFFEF6E0)
                                : const Color(0xFFEEECF6),
                            borderRadius: BorderRadius.circular(26)),
                        child: Icon(won ? Icons.emoji_events : Icons.flag,
                            color: won ? kAmberD : const Color(0xFF9A99B5),
                            size: 42),
                      ),
                      const SizedBox(height: 16),
                      Text(won ? 'You win!' : 'You lost',
                          style: GoogleFonts.fredoka(
                              fontSize: 32,
                              fontWeight: FontWeight.w600,
                              color: kInk)),
                      const SizedBox(height: 4),
                      Text('$winnerName crossed the line first',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: kMuted)),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          _place(
                              pos: won ? '1st' : '2nd',
                              name: myName,
                              color: myColor,
                              time: _fmt(myTime),
                              winner: won),
                          const SizedBox(width: 10),
                          _place(
                              pos: won ? '2nd' : '1st',
                              name: oppName,
                              color: oppColor,
                              time: _fmt(oppTime),
                              winner: !won),
                        ],
                      ),
                      const SizedBox(height: 18),
                      CandyButton(
                          label: 'Rematch',
                          icon: Icons.refresh,
                          onTap: onRematch),
                      const SizedBox(height: 6),
                      GestureDetector(
                        onTap: onExit,
                        child: SizedBox(
                          height: 50,
                          child: Center(
                            child: Text('Exit race',
                                style: GoogleFonts.fredoka(
                                    color: kMuted,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 16)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _place({
    required String pos,
    required String name,
    required String color,
    required String time,
    required bool winner,
  }) {
    final c = teamColor(color);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 13),
        decoration: BoxDecoration(
          gradient: winner
              ? const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFFFEF3D4), Color(0xFFFCE9B5)])
              : null,
          color: winner ? null : kIndigo50,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          children: [
            Text(pos,
                style: GoogleFonts.fredoka(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: winner ? const Color(0xFFB7791F) : kMuted)),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.fredoka(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: kInkSoft)),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Text(time,
                style: GoogleFonts.fredoka(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: kMuted)),
          ],
        ),
      ),
    );
  }
}

/// Lightweight falling-confetti animation for the win screen.
class _Confetti extends StatefulWidget {
  const _Confetti();
  @override
  State<_Confetti> createState() => _ConfettiState();
}

class _ConfettiState extends State<_Confetti>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(seconds: 3))
    ..repeat();

  static const _colors = [kIndigo, kCyan, kAmber, kPink];

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          return LayoutBuilder(builder: (context, box) {
            final h = box.maxHeight;
            final w = box.maxWidth;
            return Stack(
              children: List.generate(16, (i) {
                final delay = (i % 8) / 8.0;
                final t = (_c.value + delay) % 1.0;
                final x = (i * 0.0625 + 0.03) * w;
                return Positioned(
                  left: x,
                  top: t * (h + 40) - 20,
                  child: Transform.rotate(
                    angle: t * 8 + i,
                    child: Container(
                      width: 9,
                      height: 14,
                      decoration: BoxDecoration(
                          color: _colors[i % 4],
                          borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                );
              }),
            );
          });
        },
      ),
    );
  }
}
