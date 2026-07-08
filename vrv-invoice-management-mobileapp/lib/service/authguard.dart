import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

class AuthGuard {
  /// **Check User Access**
  static Future<void> verifyUserAccess(BuildContext context) async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? token = prefs.getString('token');

      if (token == null || token.isEmpty) {
        print("No token found in storage");
        logoutUser(context);
        return;
      }

      print(
        "Using token: ${token.substring(0, 10)}...",
      ); // Log first 10 chars for debugging

      final response = await http.get(
        Uri.parse('https://invoice-staging-api.mindrops.com/api/v1/'),
        headers: {'Authorization': 'Bearer $token'},
      );

      print("API Response Status Code: ${response.statusCode}");
      print("verify user API Response Body: ${response.body}");

      if (response.statusCode == 200) {
        var data = jsonDecode(response.body);
        debugPrint("User response data: $data");
        bool hasAccess = data['app_access'] ?? false;
        debugPrint("User has access: $hasAccess");

        if (!hasAccess) {
          logoutUser(context);
        }
      } else if (response.statusCode == 401) {
        // Handle unauthorized specifically
        print("Unauthorized access - token may be expired");
        logoutUser(context);
      } else {
        print(
          "Error verifying user: ${response.statusCode} - ${response.body}",
        );
      }
    } catch (e) {
      print("Exception during auth check: $e");
    }
  }

  /// **Logout User**
  static void logoutUser(BuildContext context) async {
    print("❌ User Access Revoked - Logging Out...");
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.clear();

    if (context.mounted) {
      Navigator.pushReplacementNamed(context, '/login'); // ✅ Redirect safely
    }
  }
}
