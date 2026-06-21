import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../main.dart';
import '../services/mqtt_service.dart';
import '../widgets/app_logo.dart';
import 'drive_screen.dart';

/// Lists cars discovered on the broker (from retained `cars/<id>/status`).
/// Supports any number of cars; pull down to refresh statuses.
class CarSelectScreen extends StatefulWidget {
  final MqttService mqtt;

  const CarSelectScreen({super.key, required this.mqtt});

  @override
  State<CarSelectScreen> createState() => _CarSelectScreenState();
}

class _CarSelectScreenState extends State<CarSelectScreen> {
  MqttService get _mqtt => widget.mqtt;

  @override
  void initState() {
    super.initState();
    _mqtt.addListener(_onChanged);
    _mqtt.discoverCars();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _mqtt.removeListener(_onChanged);
    super.dispose();
  }

  // Pull-to-refresh: re-subscribe and give the broker a moment to replay
  // retained statuses before we stop the spinner.
  Future<void> _onRefresh() async {
    _mqtt.discoverCars();
    await Future.delayed(const Duration(milliseconds: 700));
    if (mounted) setState(() {});
  }

  void _drive(String carId) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => DriveScreen(mqtt: _mqtt, carId: carId),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final entries = _mqtt.cars.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final onlineCount = entries.where((e) => e.value).length;

    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top bar
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 6, 22, 14),
              child: Row(
                children: [
                  _RoundButton(
                    icon: Icons.arrow_back,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 14),
                  const AppLogo(size: 30),
                  const SizedBox(width: 10),
                  Text('Select a car',
                      style: GoogleFonts.fredoka(
                          fontSize: 25,
                          fontWeight: FontWeight.w600,
                          color: kInk,
                          letterSpacing: -0.3)),
                  const Spacer(),
                  if (entries.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 13, vertical: 7),
                      decoration: BoxDecoration(
                        color: kIndigo100,
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: Text('$onlineCount online',
                          style: GoogleFonts.fredoka(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: kIndigoD)),
                    ),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _onRefresh,
                color: kIndigo,
                child: entries.isEmpty
                    ? LayoutBuilder(
                        builder: (context, c) => SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          child: ConstrainedBox(
                            constraints:
                                BoxConstraints(minHeight: c.maxHeight),
                            child: const Center(child: _EmptyState()),
                          ),
                        ),
                      )
                    : OrientationBuilder(
                        builder: (context, orientation) {
                          if (orientation == Orientation.landscape) {
                            // Grid: 2 columns of stacked cards.
                            return GridView.builder(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding:
                                  const EdgeInsets.fromLTRB(22, 4, 22, 90),
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                mainAxisExtent: 188,
                                crossAxisSpacing: 18,
                                mainAxisSpacing: 18,
                              ),
                              itemCount: entries.length,
                              itemBuilder: (context, i) {
                                final e = entries[i];
                                return _CarCard(
                                  id: e.key,
                                  online: e.value,
                                  grid: true,
                                  onDrive:
                                      e.value ? () => _drive(e.key) : null,
                                );
                              },
                            );
                          }
                          // List: full-width rows.
                          return ListView.separated(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(22, 4, 22, 90),
                            itemCount: entries.length,
                            separatorBuilder: (_, i) =>
                                const SizedBox(height: 14),
                            itemBuilder: (context, i) {
                              final e = entries[i];
                              return _CarCard(
                                id: e.key,
                                online: e.value,
                                onDrive:
                                    e.value ? () => _drive(e.key) : null,
                              );
                            },
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
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
      elevation: 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(15),
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(icon, color: kInk, size: 22),
        ),
      ),
    );
  }
}

class _CarCard extends StatelessWidget {
  final String id;
  final bool online;
  final VoidCallback? onDrive;
  final bool grid;
  const _CarCard({
    required this.id,
    required this.online,
    required this.onDrive,
    this.grid = false,
  });

  @override
  Widget build(BuildContext context) {
    final avatar = SizedBox(
      width: 62,
      height: 62,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [kIndigo50, kIndigo200],
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Padding(
              padding: EdgeInsets.all(10),
              child: AppLogo(size: 42),
            ),
          ),
          if (online)
            Positioned(
              right: -3,
              bottom: -3,
              child: Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: kGreen,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 3),
                ),
              ),
            ),
        ],
      ),
    );

    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Car $id',
            style: GoogleFonts.fredoka(
                fontSize: 19, fontWeight: FontWeight.w600, color: kInk)),
        const SizedBox(height: 3),
        Row(
          children: [
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                  color: online ? kGreen : kMuted, shape: BoxShape.circle),
            ),
            const SizedBox(width: 7),
            Text(online ? 'online' : 'offline',
                style: TextStyle(
                    color: online ? kGreenD : kMuted,
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5)),
          ],
        ),
      ],
    );

    final card = BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(26),
      boxShadow: [
        BoxShadow(
            color: const Color(0xFF3C3282).withValues(alpha: 0.09),
            blurRadius: 26,
            offset: const Offset(0, 10)),
      ],
    );

    if (grid) {
      // Stacked: avatar + info on top, full-width Drive button below.
      return Container(
        decoration: card,
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                avatar,
                const SizedBox(width: 14),
                Expanded(child: info),
              ],
            ),
            const SizedBox(height: 18),
            _DriveButton(onTap: onDrive, expand: true),
          ],
        ),
      );
    }

    // Row: avatar | info | Drive button.
    return Container(
      decoration: card,
      padding: const EdgeInsets.fromLTRB(16, 16, 18, 16),
      child: Row(
        children: [
          avatar,
          const SizedBox(width: 16),
          Expanded(child: info),
          _DriveButton(onTap: onDrive),
        ],
      ),
    );
  }
}

/// Candy "Drive" button. [expand] makes it full-width (grid card).
class _DriveButton extends StatelessWidget {
  final VoidCallback? onTap;
  final bool expand;
  const _DriveButton({required this.onTap, this.expand = false});

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onTap == null ? 0.5 : 1,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 46,
          width: expand ? double.infinity : null,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          decoration: BoxDecoration(
            gradient: kCandyGradient,
            borderRadius: BorderRadius.circular(15),
            boxShadow: onTap == null
                ? null
                : [
                    const BoxShadow(
                        color: kIndigoDD, offset: Offset(0, 5), blurRadius: 0),
                    BoxShadow(
                        color: kIndigo.withValues(alpha: 0.32),
                        offset: const Offset(0, 10),
                        blurRadius: 18),
                  ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Drive',
                  style: GoogleFonts.fredoka(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600)),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right, color: Colors.white, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.smart_toy_outlined, size: 64, color: kIndigo200),
            const SizedBox(height: 16),
            Text('No cars online yet',
                style: GoogleFonts.fredoka(
                    fontSize: 18, fontWeight: FontWeight.w600, color: kInk)),
            const SizedBox(height: 8),
            const Text(
              'Cars appear here automatically when they connect and publish '
              'their status. Pull down to refresh.',
              textAlign: TextAlign.center,
              style: TextStyle(color: kMuted, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
