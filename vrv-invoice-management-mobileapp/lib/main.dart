import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:invoice_management/screens/homescreen.dart';
import 'package:invoice_management/screens/send_otp.dart';
import 'package:invoice_management/widgets/app_animations.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VRV Invoice Management',
      theme: ThemeData(
        // Seed color same rakha hai taaki buttons/accents ka color na badle.
        // Bas white surfaces ko pure white par force kiya hai aur elevation ka
        // surfaceTint (jo Material 3 me pinkish overlay daalta hai) hataya hai,
        // taaki kahin bhi background pink na dikhe.
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          surface: Colors.white,
        ),
        scaffoldBackgroundColor: Colors.white,
        canvasColor: Colors.white,
        cardColor: Colors.white,
        dialogBackgroundColor: Colors.white,
        dialogTheme: const DialogThemeData(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
        ),
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
        ),
        cardTheme: const CardThemeData(
          color: Colors.white,
          surfaceTintColor: Colors.transparent,
        ),
        popupMenuTheme: const PopupMenuThemeData(
          color: Colors.white,
          surfaceTintColor: Colors.transparent,
        ),
      ),
      home: SplashScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  _SplashScreenState createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _logoFade;
  late Animation<double> _logoScale;
  late Animation<Offset> _textSlide;
  late Animation<double> _textFade;

  @override
  void initState() {
    super.initState();

    // animation controller for the progress bar
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..addListener(() {
      setState(() {}); // UI ko update karne ke liye
    });

    // Entrance animations derived from the same controller/timeline
    _logoFade = CurvedAnimation(
      parent: _animationController,
      curve: const Interval(0.0, 0.45, curve: Curves.easeOut),
    );
    _logoScale = Tween<double>(begin: 0.82, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.0, 0.55, curve: Curves.easeOutBack),
      ),
    );
    _textFade = CurvedAnimation(
      parent: _animationController,
      curve: const Interval(0.25, 0.65, curve: Curves.easeOut),
    );
    _textSlide = Tween<Offset>(
      begin: const Offset(0, 0.25),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.25, 0.65, curve: Curves.easeOutCubic),
      ),
    );

    // Animation start karna
    _animationController.forward().then((value) {
      // JAISE HI ANIMATION KHATAM HOGI (Progress bar full hoga), YAHAN NEXT SCREEN PAR BHEJNA HAI
      // Example:
      // Navigator.pushReplacement(
      //   context,
      //   MaterialPageRoute(builder: (context) => const NextScreen()), // Apni next screen ka naam daalo
      // );
    });

    _checkLoginStatus();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _checkLoginStatus() async {
    await Future.delayed(Duration(seconds: 2)); // Splash delay
    print("in checkloginstatus");

    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? token = prefs.getString('token');

    if (token == null) {
      print("No token found. Navigating to SendOtpScreen.");
      _logoutUser();
      return;
    }

    String authStatus = await _verifyUserAccess(token);

    if (authStatus == 'authorized') {
      if (mounted) {
        Navigator.of(
          context,
        ).pushReplacement(smoothPageRoute(InvoiceManagementScreen()));
      }
    } else if (authStatus == 'networkError') {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Connection issue. Entering offline mode."),
            duration: Duration(seconds: 3),
          ),
        );
        Navigator.of(
          context,
        ).pushReplacement(smoothPageRoute(InvoiceManagementScreen()));
      }
    } else {
      _logoutUser();
    }
  }

  Future<String> _verifyUserAccess(String token) async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();

      final response = await http
          .get(
            Uri.parse(
              'https://invoice-staging-api.mindrops.com/api/v1/user/validate',
            ),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        var data = jsonDecode(response.body);
        var user = data['user'];
        if (user == null) {
          return 'unauthorized';
        }

        bool isActive = user['status'] == "Active"; // Check if user is active
        bool hasAccess = user['app_access'] ?? false;

        if (isActive && hasAccess) {
          // User is active, update stored permissions
          var permissions = user['permissions'];
          if (permissions != null && permissions['app'] != null) {
            List<dynamic> latestPermissions = permissions['app'];
            await prefs.setString('permissions', jsonEncode(latestPermissions));
          }
          return 'authorized'; // Keep user logged in as long as status is Active
        } else {
          // User is not active, should log out
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  "Access denied: You don’t have permission to use this app.",
                ),
              ),
            );
          }
          return 'unauthorized';
        }
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        print("❌ Unauthorized: ${response.statusCode} - ${response.body}");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Session expired. Please login again."),
            ),
          );
        }
        return 'unauthorized';
      } else {
        print("❌ Error verifying user: ${response.body}");
        return 'networkError';
      }
    } catch (e) {
      print("❌ Exception: $e");
      return 'networkError';
    }
  }

  void _logoutUser() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.clear(); // Clear stored data
    if (mounted) {
      Navigator.of(context).pushReplacement(smoothPageRoute(SendOtpScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: const Color(0xFF141B44),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1B2456), Color(0xFF141B44), Color(0xFF0F1533)],
          ),
        ),
        child: Stack(
          children: [
            // Decorative soft glow blobs for depth
            Positioned(
              top: -size.width * 0.35,
              right: -size.width * 0.3,
              child: Container(
                width: size.width * 0.85,
                height: size.width * 0.85,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFF7C5CFA).withOpacity(0.20),
                      const Color(0xFF7C5CFA).withOpacity(0.0),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: -size.width * 0.4,
              left: -size.width * 0.35,
              child: Container(
                width: size.width * 0.9,
                height: size.width * 0.9,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFF3CBD6B).withOpacity(0.14),
                      const Color(0xFF3CBD6B).withOpacity(0.0),
                    ],
                  ),
                ),
              ),
            ),

            // Faint grid / dot texture accent (subtle, top area)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                height: size.height * 0.4,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withOpacity(0.03),
                      Colors.white.withOpacity(0.0),
                    ],
                  ),
                ),
              ),
            ),

            // Main centered content: logo card + title
            Align(
              alignment: const Alignment(0.0, -0.22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FadeTransition(
                    opacity: _logoFade,
                    child: ScaleTransition(
                      scale: _logoScale,
                      child: Container(
                        padding: const EdgeInsets.all(22),
                        margin: const EdgeInsets.only(bottom: 22),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(28),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF7C5CFA).withOpacity(0.25),
                              blurRadius: 40,
                              spreadRadius: 2,
                              offset: const Offset(0, 18),
                            ),
                            BoxShadow(
                              color: Colors.black.withOpacity(0.15),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Image.asset(
                          'assets/images/img_1.png',
                          height: 130,
                          width: 200,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ),
                  FadeTransition(
                    opacity: _textFade,
                    child: SlideTransition(
                      position: _textSlide,
                      child: Column(
                        children: [
                          ShaderMask(
                            shaderCallback:
                                (bounds) => const LinearGradient(
                                  colors: [
                                    Color(0xFFFFFFFF),
                                    Color(0xFFC9D2F5),
                                  ],
                                ).createShader(bounds),
                            child: const Text(
                              'Invoice Management',
                              style: TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                letterSpacing: 0.6,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Smart. Simple. Streamlined.',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: Colors.white.withOpacity(0.55),
                              letterSpacing: 0.8,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Bottom Content: Animated gradient progress bar + status text
            Positioned(
              bottom: 70,
              left: 60,
              right: 60,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      height: 6,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: _animationController.value.clamp(0.0, 1.0),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            gradient: const LinearGradient(
                              colors: [Color(0xFF7C5CFA), Color(0xFF3CBD6B)],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF7C5CFA).withOpacity(0.5),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Getting things ready...',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Colors.white.withOpacity(0.45),
                      letterSpacing: 0.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
