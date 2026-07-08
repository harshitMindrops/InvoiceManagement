import 'dart:convert';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../model/usermodel.dart';

class AuthService {
  static const String baseUrl = "https://invoice-staging-api.mindrops.com/api/v1/";
  static const String USER_ID_KEY = "user_id";

  /// **Send OTP**
  static Future<Map<String, dynamic>> sendOtp(String phoneNumber) async {
    try {
      var response = await http.post(
        Uri.parse("$baseUrl/send-otp"),
        body: jsonEncode({"phone": phoneNumber}),
        headers: {"Content-Type": "application/json"},
      );

      if (response.statusCode == 200) {
        return {'success': true, 'message': 'OTP sent successfully'};
      } else {
        var data = jsonDecode(response.body);
        log("Response Status Code: ${response.statusCode}");
        log("Response Body: ${response.body}");
        return {
          'success': false,
          'message': data['message'] ?? 'Failed to send OTP',
        };
      }
    } catch (e) {
      log("Error sending OTP: $e");
      return {'success': false, 'message': e.toString()};
    }
  }

  /// **Verify OTP & Store User Data**
  static Future<Map<String, dynamic>> verifyOtp(
    String phoneNumber,
    String otp,
  ) async {
    try {
      var response = await http.post(
        Uri.parse("$baseUrl/verify-otp"),
        body: jsonEncode({"phone": phoneNumber, "otp": otp}),
        headers: {"Content-Type": "application/json"},
      );

      log("Response: ${response.statusCode} - ${response.body}");

      if (response.statusCode == 200) {
        var data = jsonDecode(response.body);

        if (data != null &&
            data.containsKey('user') &&
            data.containsKey('token')) {
              print("User and token data found in response.");
          User user = User.fromJson(data['user']);
          String token = data['token'];
          if (token != null || token.isNotEmpty) {
            print("got token $token");
          } else{print("token is null");}

          await storeUserData(user);
          await storeToken(token);
          await storeUserId(user.id.toString());

          return {'success': true, 'user': user, 'message': 'Login successful'};
        } else {
          log("Error: No 'user' or 'token' data found in response.");
          return {
            'success': false,
            'message': data['message'] ?? 'Invalid response from server',
          };
        }
      } else {
        var data = jsonDecode(response.body);
        log("Error Response: ${response.body}");
        return {
          'success': false,
          'message': data['message'] ?? 'Invalid OTP or server error',
        };
      }
    } catch (e) {
      log("Exception: $e");
      return {'success': false, 'message': e.toString()};
    }
  }

  /// **Store user data in SharedPreferences**
  static Future<void> storeUserData(User user) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString("user", jsonEncode(user.toJson()));
    print("User data stored: ${user.toJson()}");
  }

  /// **Store authentication token in SharedPreferences**
  static Future<void> storeToken(String token) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString("token", token);
    try{print("Token stored: $token");}
    catch(e){print("Error storing token: $e");}  
  }

  /// **Store user ID in SharedPreferences**
  static Future<void> storeUserId(String userId) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(USER_ID_KEY, userId);
    print("User ID stored: $userId"); 
  }

  /// **Retrieve stored user data**
  static Future<User?> getUserData() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? userData = prefs.getString("user");
    if (userData != null) {
      return User.fromJson(jsonDecode(userData));
    }
    return null;
  }

  /// **Retrieve stored token**
  static Future<String?> getToken() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getString("token");
  }

  static Future<String?> getUserId() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getString(USER_ID_KEY);
  }

  /// **Logout & Clear User Data**
  static Future<void> logout() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }
}
