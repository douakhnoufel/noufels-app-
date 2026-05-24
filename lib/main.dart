import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/splash_screen.dart';
import 'screens/onboarding_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  
  final prefs = await SharedPreferences.getInstance();
  final onboardingComplete = prefs.getBool('onboarding_complete') ?? false;

  runApp(PlantGuardApp(onboardingComplete: onboardingComplete));
}

class PlantGuardApp extends StatefulWidget {
  final bool onboardingComplete;
  const PlantGuardApp({super.key, required this.onboardingComplete});

  @override
  State<PlantGuardApp> createState() => _PlantGuardAppState();
}

class _PlantGuardAppState extends State<PlantGuardApp> {
  late bool _onboardingComplete;

  @override
  void initState() {
    super.initState();
    _onboardingComplete = widget.onboardingComplete;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PlantGuard',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF4CAF50),
          brightness: Brightness.dark,
          surface: const Color(0xFF0A0E0A),
        ),
        textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
        // Fix: Use CardThemeData-compatible properties or the specific CardTheme constructor
        cardTheme: CardThemeData(
          color: const Color(0xFF141A14),
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      home: _onboardingComplete 
          ? const SplashScreen() 
          : OnboardingScreen(onFinish: () => setState(() => _onboardingComplete = true)),
    );
  }
}
