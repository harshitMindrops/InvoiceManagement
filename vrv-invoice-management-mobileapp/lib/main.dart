import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:invoice_management/screens/homescreen.dart';
import 'package:invoice_management/screens/send_otp.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VRV Invoice Management',
      theme: ThemeData(
        // Notice that the counter didn't reset back to zero; the application
        // state is not lost during the reload. To reset the state, use hot
        // restart instead.
        //
        // This works for code too, not just values: Most code changes can be
        // tested with just a hot reload.
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
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

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;

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
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => InvoiceManagementScreen()),
        );
      }
    } else if (authStatus == 'networkError') {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Connection issue. Entering offline mode."),
            duration: Duration(seconds: 3),
          ),
        );
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => InvoiceManagementScreen()),
        );
      }
    } else {
      _logoutUser();
    }
  }

  Future<String> _verifyUserAccess(String token) async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();

      final response = await http.get(
        Uri.parse('https://invoice-staging-api.mindrops.com/api/v1/user/validate'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 10));

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
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (context) => SendOtpScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // Logo aur Text ko center se thoda upar shift kiya gaya hai
          Align(
            // y (vertical) axis ko -0.3 set kiya hai (-1.0 top hota hai, 0.0 center, 1.0 bottom)
            alignment: const Alignment(0.0, -0.3), 
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: Image.asset(
                    'assets/images/img_1.png',
                    height: 180,
                    width: 280,
                    fit: BoxFit.contain,
                  ),
                ),
                const Text(
                  'Invoice Management',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF134CB5),
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
          
          // Bottom Content: Animated Linear Progress Bar
          Positioned(
            bottom: 80, 
            left: 60,   
            right: 60,  
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: LinearProgressIndicator(
                value: _animationController.value, 
                minHeight: 6,
                backgroundColor: Colors.blue.withOpacity(0.15),
                valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF192155)),
              ),
            ),
          ),
        ],
      ),
    );
  }

}
