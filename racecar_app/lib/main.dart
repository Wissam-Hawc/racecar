import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'services/mqtt_service.dart';
import 'screens/splash_screen.dart';

const kInk = Color(0xFF211E3B);
const kInkSoft = Color(0xFF3A3760);
const kMuted = Color(0xFF7B7A96);
const kBg = Color(0xFFF0F0FA);
const kLine = Color(0xFFECEBF6);

const kIndigo = Color(0xFF6366F1);
const kIndigoD = Color(0xFF4F46E5);
const kIndigoDD = Color(0xFF4338CA);
const kIndigo50 = Color(0xFFEEF0FE);
const kIndigo100 = Color(0xFFE4E5FD);
const kIndigo200 = Color(0xFFD3D5FB);
const kCandyTop = Color(0xFF7C84FF);

const kGreen = Color(0xFF22C55E);
const kGreenD = Color(0xFF16A34A);
const kRed = Color(0xFFFB4E5B);
const kRedD = Color(0xFFE11D48);
const kAmber = Color(0xFFFBBF24);
const kAmberD = Color(0xFFF59E0B);
const kCyan = Color(0xFF22D3EE);
const kPink = Color(0xFFFB7185);

const kDark = Color(0xFF0A0A12);

// Race teams: the host picks a colour, the joiner gets the other one.
// Players are identified by name + colour (not by car id).
const kTeamRed = Color(0xFFFB4E5B);
const kTeamBlue = Color(0xFF3B82F6);

Color teamColor(String? color) => color == 'blue' ? kTeamBlue : kTeamRed;
String teamLabel(String? color) => color == 'blue' ? 'BLUE' : 'RED';

/// Amber "Race" pill / start-race accents.
const kRaceGradient = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [kAmber, kAmberD],
);

const kRCard = 30.0;
const kRCtrl = 20.0;

// Aliases kept for older references.
const kBrandSeed = kIndigo;

/// Hero gradient (radial cyan → indigo → purple), portrait.
const kHeroGradient = RadialGradient(
  center: Alignment(0.0, -1.2),
  radius: 1.35,
  colors: [Color(0xFF7DE3F4), Color(0xFF6F7CF6), Color(0xFF7A53E8)],
  stops: [0.0, 0.44, 1.0],
);
const kBrandGradient = kHeroGradient;

/// Hero gradient for the landscape branding pane (origin top-left-ish).
const kHeroGradientLand = RadialGradient(
  center: Alignment(-0.4, -0.9),
  radius: 1.5,
  colors: [Color(0xFF7DE3F4), Color(0xFF6F7CF6), Color(0xFF7A53E8)],
  stops: [0.0, 0.46, 1.0],
);

/// Candy button gradient (top→bottom indigo).
const kCandyGradient = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [kCandyTop, kIndigo],
);

/// Red STOP button gradient.
const kStopGradient = RadialGradient(
  center: Alignment(-0.2, -0.4),
  radius: 1.2,
  colors: [Color(0xFFFF7A84), kRed, kRedD],
  stops: [0.0, 0.55, 1.0],
);

void main() {
  runApp(const CarApp());
}

class CarApp extends StatefulWidget {
  const CarApp({super.key});

  @override
  State<CarApp> createState() => _CarAppState();
}

class _CarAppState extends State<CarApp> {
  final MqttService _mqtt = MqttService();

  @override
  void dispose() {
    _mqtt.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: kIndigo),
      scaffoldBackgroundColor: kBg,
    );
    return MaterialApp(
      title: 'Car App',
      debugShowCheckedModeBanner: false,
      theme: base.copyWith(
        // Nunito as the body font; Fredoka is applied per-widget for display.
        textTheme: GoogleFonts.nunitoTextTheme(base.textTheme),
      ),
      home: SplashScreen(mqtt: _mqtt),
    );
  }
}
