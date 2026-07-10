import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:http/http.dart' as http;
import 'package:invoice_management/screens/send_otp.dart';
import 'package:pinput/pinput.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../service/authservice.dart';
import 'homescreen.dart';

class VerifyOtpScreen extends StatefulWidget {
  final String phoneNumber;

  const VerifyOtpScreen({super.key, required this.phoneNumber});

  @override
  State<VerifyOtpScreen> createState() => _VerifyOtpScreenState();
}

class _VerifyOtpScreenState extends State<VerifyOtpScreen> {
  final _otpController = TextEditingController();
  final _otpFocusNode = FocusNode();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  String? _errorMessage;
  bool _canResendOtp = false;
  int _resendCountdown = 10;
  Timer? _resendTimer;

  @override
  void initState() {
    super.initState();
    _startResendTimer();
  }

  @override
  void dispose() {
    _otpController.dispose();
    _otpFocusNode.dispose();
    _resendTimer?.cancel();
    super.dispose();
  }

  void _startResendTimer() {
    setState(() {
      _canResendOtp = false;
      _resendCountdown = 10;
    });

    _resendTimer = Timer.periodic(Duration(seconds: 1), (timer) {
      if (_resendCountdown > 0) {
        setState(() {
          _resendCountdown--;
        });
      } else {
        timer.cancel();
        setState(() {
          _canResendOtp = true;
        });
      }
    });
  }

  Future<void> _resendOtp() async {
    if (!_canResendOtp) return;

    try {
      setState(() {
        _canResendOtp = false;
        _errorMessage = null;
      });

      var result = await AuthService.sendOtp(widget.phoneNumber);

      if (result['success']) {
        Fluttertoast.showToast(
          msg: "OTP resent successfully",
          toastLength: Toast.LENGTH_SHORT,
          gravity: ToastGravity.BOTTOM,
          backgroundColor: Colors.green,
          textColor: Colors.white,
          fontSize: 16.0,
        );
        _startResendTimer();
      } else {
        setState(() {
          _errorMessage = result['message'] ?? "Failed to resend OTP";
        });
        Fluttertoast.showToast(
          msg: result['message'] ?? "Failed to resend OTP",
          toastLength: Toast.LENGTH_LONG,
          gravity: ToastGravity.BOTTOM,
          backgroundColor: Colors.red,
          textColor: Colors.white,
          fontSize: 16.0,
        );
        setState(() {
          _canResendOtp = true;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = "Failed to resend OTP: ${e.toString()}";
        _canResendOtp = true;
      });
      Fluttertoast.showToast(
        msg: "Failed to resend OTP: ${e.toString()}",
        toastLength: Toast.LENGTH_LONG,
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.red,
        textColor: Colors.white,
        fontSize: 16.0,
      );
    }
  }

  Future<void> _login() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      try {
        final result = await AuthService.verifyOtp(
          widget.phoneNumber,
          _otpController.text,
        );

        if (result['user'] != null) {
          print("✅ Login successful for user: ${result['user'].phone}");
          await _validateUserAppAccess();
        } else {
          setState(() {
            _errorMessage =
                result['message'] ?? "Invalid OTP. Please try again.";
          });
          Fluttertoast.showToast(
            msg: result['message'] ?? "Invalid OTP. Please try again.",
            toastLength: Toast.LENGTH_LONG,
            gravity: ToastGravity.BOTTOM,
            backgroundColor: Colors.red,
            textColor: Colors.white,
            fontSize: 16.0,
          );
        }
      } catch (e) {
        setState(() {
          _errorMessage = "Login failed: $e";
        });
        Fluttertoast.showToast(
          msg: "Login failed: $e",
          toastLength: Toast.LENGTH_LONG,
          gravity: ToastGravity.BOTTOM,
          backgroundColor: Colors.red,
          textColor: Colors.white,
          fontSize: 16.0,
        );
      } finally {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<bool> _validateUserAppAccess() async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? token = prefs.getString('token');

      if (token == null || token.isEmpty) {
        setState(() {
          _errorMessage = "No token found, please login again.";
        });
        Fluttertoast.showToast(
          msg: "No token found, please login again.",
          toastLength: Toast.LENGTH_LONG,
          gravity: ToastGravity.BOTTOM,
          backgroundColor: Colors.red,
          textColor: Colors.white,
          fontSize: 16.0,
        );
        return false;
      }

      final response = await http.get(
        Uri.parse('https://invoice-staging-api.mindrops.com/api/v1/user/validate'),
        headers: {'Authorization': 'Bearer $token'},
      );

      print("Validation response: ${response.statusCode} - ${response.body}");

      if (response.statusCode == 200) {
        var data = jsonDecode(response.body);
        bool hasAccess = data['user']?['app_access'] ?? false;
        print("App access: $hasAccess");

        if (hasAccess) {
          print("Navigating to InvoiceManagementScreen");
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => InvoiceManagementScreen()),
            (route) => false, // Removes all previous routes
          );
          return true;
        } else {
          setState(() {
            _errorMessage = "You don’t have permission to use this app.";
          });
          Fluttertoast.showToast(
            msg: "You don’t have permission to use this app.",
            toastLength: Toast.LENGTH_LONG,
            gravity: ToastGravity.BOTTOM,
            backgroundColor: Colors.red,
            textColor: Colors.white,
            fontSize: 16.0,
          );
          return false;
        }
      } else {
        setState(() {
          _errorMessage = "Failed to validate access.";
        });
        Fluttertoast.showToast(
          msg: "Failed to validate access.",
          toastLength: Toast.LENGTH_LONG,
          gravity: ToastGravity.BOTTOM,
          backgroundColor: Colors.red,
          textColor: Colors.white,
          fontSize: 16.0,
        );
        return false;
      }
    } catch (e) {
      setState(() {
        _errorMessage = "Something went wrong: ${e.toString()}";
      });
      Fluttertoast.showToast(
        msg: "Something went wrong: ${e.toString()}",
        toastLength: Toast.LENGTH_LONG,
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.red,
        textColor: Colors.white,
        fontSize: 16.0,
      );
      return false;
    }
  }

  final defaultPinTheme = PinTheme(
    width: 56,
    height: 56,
    textStyle: TextStyle(
      fontSize: 20,
      color: Color(0xFF192155),
      fontWeight: FontWeight.w600,
    ),
    decoration: BoxDecoration(
      border: Border.all(color: Color(0xFF4A4A4A)),
      borderRadius: BorderRadius.circular(12),
    ),
  );

  final focusedPinTheme = PinTheme(
    width: 56,
    height: 56,
    textStyle: TextStyle(
      fontSize: 20,
      color: Color(0xFF192155),
      fontWeight: FontWeight.w600,
    ),
    decoration: BoxDecoration(
      border: Border.all(color: Color(0xFF192155), width: 2),
      borderRadius: BorderRadius.circular(12),
    ),
  );

  final errorPinTheme = PinTheme(
    width: 56,
    height: 56,
    textStyle: TextStyle(
      fontSize: 20,
      color: Colors.red,
      fontWeight: FontWeight.w600,
    ),
    decoration: BoxDecoration(
      border: Border.all(color: Colors.red),
      borderRadius: BorderRadius.circular(12),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(horizontal: 32),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    margin: EdgeInsets.only(bottom: 10),
                    child: Image.asset(
                      'assets/images/img_1.png',
                      height: 250,
                      width: 250,
                      fit: BoxFit.contain,
                    ),
                  ),
                  Text(
                    'VERIFY OTP',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF192155),
                      letterSpacing: 1.2,
                      shadows: [
                        Shadow(
                          blurRadius: 2,
                          color: Colors.blue.withOpacity(0.5),
                          offset: Offset(1, 1),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 24),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Verification Code',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF4A4A4A),
                        ),
                      ),
                      SizedBox(height: 8),
                      Pinput(
                        controller: _otpController,
                        focusNode: _otpFocusNode,
                        length: 6,
                        defaultPinTheme: defaultPinTheme,
                        focusedPinTheme: focusedPinTheme,
                        errorPinTheme: errorPinTheme,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter the OTP';
                          } else if (value.length < 6) {
                            return 'Please enter a valid 6-digit OTP';
                          }
                          return null;
                        },
                        pinputAutovalidateMode: PinputAutovalidateMode.onSubmit,
                        showCursor: true,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        onCompleted: (pin) {
                          _login();
                        },
                      ),
                      SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          GestureDetector(
                            onTap: _canResendOtp ? _resendOtp : null,
                            child: Text(
                              _canResendOtp
                                  ? "Resend OTP"
                                  : "Resend OTP in $_resendCountdown sec",
                              style: TextStyle(
                                color:
                                    _canResendOtp
                                        ? Color(0xFF192155)
                                        : Colors.grey,
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                decoration:
                                    _canResendOtp
                                        ? TextDecoration.underline
                                        : null,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              Navigator.pushReplacement(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => SendOtpScreen(),
                                ),
                              );
                            },
                            child: Text(
                              "Edit Number",
                              style: TextStyle(
                                color: Color(0xFF192155),
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  SizedBox(height: 24),
                  Container(
                    width: double.infinity,
                    height: 56,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      gradient: LinearGradient(
                        colors: [Color(0xFF192155), Color(0xFF192155)],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.blue.withOpacity(0.3),
                          blurRadius: 8,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _login,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        padding: EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child:
                          _isLoading
                              ? Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white,
                                      ),
                                    ),
                                  ),
                                  SizedBox(width: 12),
                                  Text(
                                    "Logging in...",
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              )
                              : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.login_rounded,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                                  SizedBox(width: 12),
                                  Text(
                                    "Login",
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
