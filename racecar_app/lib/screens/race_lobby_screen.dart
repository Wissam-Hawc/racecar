import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mqtt_client/mqtt_client.dart' show MqttQos;

import '../main.dart';
import '../mqtt_topics.dart';
import '../services/mqtt_service.dart';
import '../widgets/candy_button.dart';
import 'race_screen.dart';

/// Race lobby with a real room model over MQTT.
///
/// Players are identified by NAME + COLOUR, not by car id. The host types a
/// name and picks a team colour (red/blue); a joiner types a name and is given
/// the other colour automatically. Each player publishes its name to
/// `race/<code>/players/<colour>` (retained), so a joiner sees who's in.
///
/// When the host starts, it publishes the match config to `race/match`
/// (retained) so the finish-line judge ESP knows who is racing.
class RaceLobbyScreen extends StatefulWidget {
  final MqttService mqtt;
  final String carId;
  final bool isHost;
  final String? roomCode; // required when joining; generated when hosting

  const RaceLobbyScreen({
    super.key,
    required this.mqtt,
    required this.carId,
    required this.isHost,
    this.roomCode,
  });

  @override
  State<RaceLobbyScreen> createState() => _RaceLobbyScreenState();
}

class _RaceLobbyScreenState extends State<RaceLobbyScreen> {
  late final String _code;
  late final RegExp _playerRe;
  final TextEditingController _nameCtrl = TextEditingController();

  String _myColor = 'red'; // host's pick; joiner gets the opposite
  String _myName = '';
  bool _isReady = false; // published our presence?
  bool _started = false;

  // Present players: colour -> name (latest retained value per colour).
  Map<String, String> _players = {};

  MqttService get _mqtt => widget.mqtt;
  bool get _isHost => widget.isHost;

  @override
  void initState() {
    super.initState();
    _code = widget.roomCode ?? _generateRoomCode();
    _playerRe = RegExp('^race/$_code/players/(red|blue)\$');

    _mqtt.addListener(_onChanged);
    _mqtt.subscribe(Topics.racePlayersWildcard(_code));
    _mqtt.subscribe(Topics.raceStart(_code));
    _recompute();
  }

  // The MQTT service fires on EVERY message (telemetry arrives every 500 ms).
  // Only rebuild when something we actually show changed, otherwise the
  // constant setState() drops the keyboard while typing your name.
  void _onChanged() {
    final changed = _recompute();
    _maybeStart();
    if (mounted && changed) setState(() {});
  }

  // Build the live colour->name map from the retained presence messages.
  // Returns true if the room (members or our assigned colour) actually changed.
  bool _recompute() {
    final prevColor = _myColor;
    final seen = <String>{};
    final map = <String, String>{};
    for (final e in _mqtt.log) {
      final m = _playerRe.firstMatch(e.topic);
      if (m == null) continue;
      final color = m.group(1)!;
      if (!seen.add(color)) continue; // newest entry per colour wins
      final name = e.payload.trim();
      if (name.isNotEmpty) map[color] = name;
    }

    // A joiner takes whichever colour the host did NOT take.
    if (!_isHost && !_isReady) {
      if (map.containsKey('red') && !map.containsKey('blue')) {
        _myColor = 'blue';
      } else if (map.containsKey('blue') && !map.containsKey('red')) {
        _myColor = 'red';
      }
    }

    final changed = _myColor != prevColor || !_sameMembers(map, _players);
    _players = map;
    return changed;
  }

  bool _sameMembers(Map<String, String> a, Map<String, String> b) {
    if (a.length != b.length) return false;
    for (final k in a.keys) {
      if (b[k] != a[k]) return false;
    }
    return true;
  }

  void _maybeStart() {
    if (_started) return;
    if (_mqtt.log.any((e) => e.topic == Topics.raceStart(_code))) _goToRace();
  }

  String? get _oppColor {
    for (final c in const ['red', 'blue']) {
      if (c != _myColor && _players.containsKey(c)) return c;
    }
    return null;
  }

  String? get _oppName => _oppColor == null ? null : _players[_oppColor];

  String _generateRoomCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final r = Random();
    return List.generate(3, (_) => chars[r.nextInt(chars.length)]).join();
  }

  @override
  void dispose() {
    if (_isReady) {
      // Leave the room: clear our retained presence.
      _mqtt.publish(Topics.racePlayer(_code, _myColor), '',
          qos: MqttQos.atLeastOnce, retain: true);
    }
    _mqtt.removeListener(_onChanged);
    _nameCtrl.dispose();
    super.dispose();
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text),
      behavior: SnackBarBehavior.floating,
      backgroundColor: kIndigoD,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ));
  }

  void _shareCode() {
    Clipboard.setData(ClipboardData(text: 'R4CE-$_code'));
    _snack('Room code copied');
  }

  // Lock in our name + colour and announce presence to the room.
  void _setReady() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return _snack('Type your name first');
    if (!_isHost && _players.isEmpty) {
      return _snack('Waiting for the host to pick a colour…');
    }
    // A 1v1 room only has two colour slots; don't let a third player in (it
    // would overwrite an existing player's slot).
    if (!_isHost && _players.length >= 2 && !_players.containsKey(_myColor)) {
      return _snack('This room is full');
    }
    setState(() {
      _myName = name;
      _isReady = true;
    });
    _mqtt.publish(Topics.racePlayer(_code, _myColor), name,
        qos: MqttQos.atLeastOnce, retain: true);
  }

  void _startRace() {
    // Both players must be present before a race can start.
    if (!_isReady || _oppColor == null) {
      _snack('Both players must join before starting');
      return;
    }
    // Tell the finish-line judge ESP who is racing (retained, so a late judge
    // still gets it), then signal both phones to begin.
    _mqtt.publish(
      Topics.raceMatch,
      jsonEncode({
        'code': _code,
        'red': _players['red'] ?? '',
        'blue': _players['blue'] ?? '',
      }),
      qos: MqttQos.atLeastOnce,
      retain: true,
    );
    _mqtt.publish(Topics.raceStart(_code), _code, qos: MqttQos.atLeastOnce);
    _goToRace();
  }

  void _goToRace() {
    if (_started) return;
    _started = true;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => RaceScreen(
        mqtt: _mqtt,
        carId: widget.carId,
        myName: _myName,
        myColor: _myColor,
        oppName: _oppName,
        oppColor: _oppColor,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    // Use the SCREEN orientation (stable), not OrientationBuilder — the latter
    // keys off its box size, which shrinks when the keyboard opens and would
    // flip the layout mid-typing, dropping focus on the name field.
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: Column(
          children: [
            _topBar(),
            Expanded(child: isLandscape ? _landscape() : _portrait()),
          ],
        ),
      ),
    );
  }

  Widget _topBar() {
    final inRoom = _players.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 6, 22, 14),
      child: Row(
        children: [
          _RoundButton(
              icon: Icons.arrow_back, onTap: () => Navigator.pop(context)),
          const SizedBox(width: 14),
          const Icon(Icons.sports_score, color: kIndigo, size: 26),
          const SizedBox(width: 8),
          Text('Race',
              style: GoogleFonts.fredoka(
                  fontSize: 25,
                  fontWeight: FontWeight.w600,
                  color: kInk,
                  letterSpacing: -0.3)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
            decoration: BoxDecoration(
                color: const Color(0xFFFEF1D6),
                borderRadius: BorderRadius.circular(30)),
            child: Text('$inRoom in room',
                style: GoogleFonts.fredoka(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFFB7791F))),
          ),
        ],
      ),
    );
  }

  Widget _portrait() {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(22, 4, 22, 8),
            children: [
              _CodeCard(code: _code, onShare: _shareCode),
              const SizedBox(height: 16),
              _detailsCard(),
              const SizedBox(height: 16),
              _VsCard(
                  redName: _players['red'],
                  blueName: _players['blue'],
                  myColor: _myColor),
              const SizedBox(height: 16),
              const _Judge(),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 8, 22, 22),
          child: _footer(),
        ),
      ],
    );
  }

  // One vertical scroll holding two columns, so nothing overflows the short
  // landscape height and the layout still scrolls when the keyboard is up.
  Widget _landscape() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 4, 28, 22),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              children: [
                _CodeCard(code: _code, onShare: _shareCode),
                const SizedBox(height: 14),
                _detailsCard(),
              ],
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              children: [
                _VsCard(
                    redName: _players['red'],
                    blueName: _players['blue'],
                    myColor: _myColor),
                const SizedBox(height: 14),
                const _Judge(),
                const SizedBox(height: 14),
                _footer(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Name field + colour choice. Host picks the colour; a joiner sees the
  // colour assigned to them. Locks once the player taps "I'm ready".
  Widget _detailsCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(
              color: const Color(0xFF3C3282).withValues(alpha: 0.07),
              blurRadius: 20,
              offset: const Offset(0, 8)),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('YOUR DETAILS',
              style: GoogleFonts.fredoka(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                  color: kIndigoD.withValues(alpha: 0.7))),
          const SizedBox(height: 12),
          TextField(
            controller: _nameCtrl,
            enabled: !_isReady,
            textCapitalization: TextCapitalization.words,
            style: GoogleFonts.fredoka(
                fontSize: 17, fontWeight: FontWeight.w500, color: kInk),
            decoration: InputDecoration(
              hintText: 'Your name',
              prefixIcon: const Icon(Icons.person_outline, color: kIndigo),
              filled: true,
              fillColor: kIndigo50,
              contentPadding: const EdgeInsets.symmetric(vertical: 4),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 14),
          Text(_isHost ? 'Pick your team colour' : 'Your team colour',
              style: GoogleFonts.fredoka(
                  fontSize: 13.5, fontWeight: FontWeight.w600, color: kInkSoft)),
          const SizedBox(height: 8),
          Row(
            children: [
              _ColorChip(
                color: 'red',
                selected: _myColor == 'red',
                // Host chooses freely (before ready); joiner's is fixed.
                enabled: _isHost && !_isReady,
                onTap: () => setState(() => _myColor = 'red'),
              ),
              const SizedBox(width: 12),
              _ColorChip(
                color: 'blue',
                selected: _myColor == 'blue',
                enabled: _isHost && !_isReady,
                onTap: () => setState(() => _myColor = 'blue'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_isReady)
            Row(
              children: [
                const Icon(Icons.check_circle, color: kGreen, size: 22),
                const SizedBox(width: 8),
                Text('Ready as $_myName',
                    style: GoogleFonts.fredoka(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: kGreenD)),
              ],
            )
          else
            SizedBox(
              width: double.infinity,
              child: CandyButton(
                  label: "I'm ready",
                  icon: Icons.check_rounded,
                  onTap: _setReady),
            ),
        ],
      ),
    );
  }

  // Host sees Start (enabled with an opponent + once ready); a joiner waits.
  Widget _footer() {
    final hasOpponent = _oppColor != null;
    if (!_isHost) {
      return _WaitingBar(
          text: _isReady
              ? 'Waiting for the host to start…'
              : 'Type your name and tap “I’m ready”');
    }
    return Column(
      children: [
        if (!_isReady)
          const Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: Text('Set your name & colour, then tap “I’m ready”',
                style: TextStyle(color: kMuted, fontWeight: FontWeight.w600)),
          )
        else if (!hasOpponent)
          const Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: Text('Waiting for an opponent to join…',
                style: TextStyle(color: kMuted, fontWeight: FontWeight.w600)),
          ),
        CandyButton(
          label: 'Start race',
          icon: Icons.sports_score,
          onTap: (_isReady && hasOpponent) ? _startRace : null,
        ),
      ],
    );
  }
}

class _ColorChip extends StatelessWidget {
  final String color; // 'red' | 'blue'
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;
  const _ColorChip({
    required this.color,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = teamColor(color);
    return Expanded(
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: 52,
          decoration: BoxDecoration(
            color: selected ? c : c.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: selected ? c : c.withValues(alpha: 0.35), width: 2),
          ),
          child: Center(
            child: Text(
              teamLabel(color),
              style: GoogleFonts.fredoka(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: selected ? Colors.white : c,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WaitingBar extends StatelessWidget {
  final String text;
  const _WaitingBar({required this.text});
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      decoration: BoxDecoration(
          color: kIndigo50, borderRadius: BorderRadius.circular(16)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
              width: 18,
              height: 18,
              child:
                  CircularProgressIndicator(strokeWidth: 2.4, color: kIndigo)),
          const SizedBox(width: 12),
          Flexible(
            child: Text(text,
                textAlign: TextAlign.center,
                style: GoogleFonts.fredoka(
                    color: kIndigoD, fontWeight: FontWeight.w600, fontSize: 15)),
          ),
        ],
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _RoundButton({required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(15),
      child: InkWell(
        borderRadius: BorderRadius.circular(15),
        onTap: onTap,
        child: SizedBox(
            width: 44, height: 44, child: Icon(icon, color: kInk, size: 22)),
      ),
    );
  }
}

class _CodeCard extends StatelessWidget {
  final String code;
  final VoidCallback onShare;
  const _CodeCard({required this.code, required this.onShare});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [kIndigo50, Color(0xFFE2E4FD)]),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: Colors.white, width: 2),
      ),
      padding: const EdgeInsets.all(22),
      child: Column(
        children: [
          Text('SHARE THIS ROOM CODE',
              style: GoogleFonts.fredoka(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.4,
                  color: kIndigoD.withValues(alpha: 0.7))),
          const SizedBox(height: 6),
          RichText(
            text: TextSpan(
              style: GoogleFonts.fredoka(
                  fontSize: 38,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 3,
                  color: kInk),
              children: [
                const TextSpan(text: 'R4CE-'),
                TextSpan(
                    text: code,
                    style: const TextStyle(
                        color: kIndigoD, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: onShare,
            child: Container(
              height: 46,
              padding: const EdgeInsets.symmetric(horizontal: 22),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(40),
                boxShadow: [
                  BoxShadow(
                      color: const Color(0xFF3C3282).withValues(alpha: 0.12),
                      blurRadius: 12,
                      offset: const Offset(0, 4)),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.copy, color: kIndigoD, size: 18),
                  const SizedBox(width: 9),
                  Text('Copy code',
                      style: GoogleFonts.fredoka(
                          color: kIndigoD,
                          fontWeight: FontWeight.w600,
                          fontSize: 15)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VsCard extends StatelessWidget {
  final String? redName;
  final String? blueName;
  final String myColor;
  const _VsCard(
      {required this.redName, required this.blueName, required this.myColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(
              color: const Color(0xFF3C3282).withValues(alpha: 0.09),
              blurRadius: 26,
              offset: const Offset(0, 10)),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 22),
      child: Row(
        children: [
          Expanded(
            child: _TeamSide(
                color: 'red', name: redName, isYou: myColor == 'red'),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Transform.rotate(
              angle: -0.1,
              child: Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  gradient: kCandyGradient,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                        color: kIndigo.withValues(alpha: 0.4),
                        blurRadius: 16,
                        offset: const Offset(0, 6)),
                  ],
                ),
                child: Center(
                  child: Text('VS',
                      style: GoogleFonts.fredoka(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 22)),
                ),
              ),
            ),
          ),
          Expanded(
            child: _TeamSide(
                color: 'blue', name: blueName, isYou: myColor == 'blue'),
          ),
        ],
      ),
    );
  }
}

class _TeamSide extends StatelessWidget {
  final String color; // 'red' | 'blue'
  final String? name;
  final bool isYou;
  const _TeamSide(
      {required this.color, required this.name, required this.isYou});

  @override
  Widget build(BuildContext context) {
    final c = teamColor(color);
    final present = name != null && name!.isNotEmpty;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            Opacity(
              opacity: present ? 1 : 0.45,
              child: Container(
                width: 74,
                height: 74,
                decoration: BoxDecoration(
                  color: c.withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                  border: Border.all(color: c, width: 3),
                ),
                child: Icon(Icons.directions_car, color: c, size: 36),
              ),
            ),
            if (present)
              Positioned(
                right: -2,
                bottom: -2,
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                      color: kGreen,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3)),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(present ? name! : 'Waiting…',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.fredoka(
                fontSize: 18, fontWeight: FontWeight.w600, color: kInk)),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
          decoration: BoxDecoration(
              color: c.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(30)),
          child: Text(isYou ? 'YOU · ${teamLabel(color)}' : teamLabel(color),
              style: GoogleFonts.fredoka(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  color: c)),
        ),
      ],
    );
  }
}

class _Judge extends StatelessWidget {
  const _Judge();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(
              color: const Color(0xFF3C3282).withValues(alpha: 0.07),
              blurRadius: 20,
              offset: const Offset(0, 8)),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
                color: const Color(0xFFE4F7EC),
                borderRadius: BorderRadius.circular(14)),
            child: const Icon(Icons.sports_score, color: kGreenD, size: 22),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Finish-line judge',
                    style: GoogleFonts.fredoka(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: kInk)),
                const SizedBox(height: 1),
                const Text('Color-line sensor · reports race/result',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: kMuted)),
              ],
            ),
          ),
          const PulseDot(),
        ],
      ),
    );
  }
}
