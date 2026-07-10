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
import '../widgets/app_animations.dart';
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
            smoothPageRoute(InvoiceManagementScreen()),
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
    width: 48,
    height: 56,
    textStyle: TextStyle(
      fontSize: 20,
      color: Color(0xFF192155),
      fontWeight: FontWeight.w700,
    ),
    decoration: BoxDecoration(
      color: Color(0xFFF3F4F7),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Color(0xFFE3E5EE)),
    ),
  );

  final focusedPinTheme = PinTheme(
    width: 48,
    height: 56,
    textStyle: TextStyle(
      fontSize: 20,
      color: Color(0xFF192155),
      fontWeight: FontWeight.w700,
    ),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Color(0xFF192155), width: 2),
      boxShadow: [
        BoxShadow(
          color: Color(0xFF192155).withOpacity(0.18),
          blurRadius: 10,
          offset: Offset(0, 4),
        ),
      ],
    ),
  );

  final errorPinTheme = PinTheme(
    width: 48,
    height: 56,
    textStyle: TextStyle(
      fontSize: 20,
      color: Colors.red.shade600,
      fontWeight: FontWeight.w700,
    ),
    decoration: BoxDecoration(
      color: Colors.red.shade50,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Colors.red.shade400, width: 1.4),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Color(0xFF2A3577),
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFFF3F4F7),
        body: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                FadeSlideIn(
                  beginOffset: const Offset(0, -0.05),
                  child: Container(
                  padding: EdgeInsets.fromLTRB(
                    24,
                    MediaQuery.of(context).padding.top + 18,
                    24,
                    34,
                  ),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF2A3577), Color(0xFF141B44)],
                    ),
                    borderRadius: BorderRadius.only(
                      bottomLeft: Radius.circular(32),
                      bottomRight: Radius.circular(32),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Color(0x33000000),
                        blurRadius: 18,
                        offset: Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Material(
                            color: Colors.white.withOpacity(0.12),
                            shape: const CircleBorder(),
                            child: IconButton(
                              icon: const Icon(
                                Icons.arrow_back_ios_new_rounded,
                                color: Colors.white,
                                size: 18,
                              ),
                              onPressed: () {
                                Navigator.pushReplacement(
                                  context,
                                  smoothPageRoute(SendOtpScreen()),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Center(
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.08),
                            shape: BoxShape.circle,
                          ),
                          child: Image.asset(
                            'assets/images/img_1.png',
                            height: 96,
                            width: 96,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      const Center(
                        child: Text(
                          'Verify OTP',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Center(
                        child: Text(
                          'Enter the 6-digit code sent to',
                          style: TextStyle(
                            fontSize: 13.5,
                            color: Colors.white.withOpacity(0.68),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Center(
                        child: Text(
                          '+91 ${widget.phoneNumber}',
                          style: const TextStyle(
                            fontSize: 15.5,
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                ),

                // Card with OTP form
                FadeSlideIn(
                  delay: const Duration(milliseconds: 120),
                  child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(20, 26, 20, 24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF192155).withOpacity(0.08),
                          blurRadius: 22,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'VERIFICATION CODE',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1,
                            color: Colors.grey.shade500,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Center(
                          child: Pinput(
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
                            pinputAutovalidateMode:
                                PinputAutovalidateMode.onSubmit,
                            showCursor: true,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            onCompleted: (pin) {
                              _login();
                            },
                          ),
                        ),
                        if (_errorMessage != null) ...[
                          const SizedBox(height: 14),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.red.shade100),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.error_outline_rounded,
                                    color: Colors.red.shade400, size: 18),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _errorMessage!,
                                    style: TextStyle(
                                      color: Colors.red.shade600,
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            GestureDetector(
                              onTap: _canResendOtp ? _resendOtp : null,
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.refresh_rounded,
                                    size: 16,
                                    color: _canResendOtp
                                        ? const Color(0xFF192155)
                                        : Colors.grey.shade400,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    _canResendOtp
                                        ? "Resend OTP"
                                        : "Resend in ${_resendCountdown}s",
                                    style: TextStyle(
                                      color: _canResendOtp
                                          ? const Color(0xFF192155)
                                          : Colors.grey.shade500,
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w600,
                                      decoration: _canResendOtp
                                          ? TextDecoration.underline
                                          : null,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            GestureDetector(
                              onTap: () {
                                Navigator.pushReplacement(
                                  context,
                                  smoothPageRoute(SendOtpScreen()),
                                );
                              },
                              child: Row(
                                children: const [
                                  Icon(
                                    Icons.edit_rounded,
                                    size: 15,
                                    color: Color(0xFF192155),
                                  ),
                                  SizedBox(width: 4),
                                  Text(
                                    "Edit Number",
                                    style: TextStyle(
                                      color: Color(0xFF192155),
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 26),
                        Material(
                          color: Colors.transparent,
                          borderRadius: BorderRadius.circular(16),
                          child: Ink(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              gradient: const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Color(0xFF2A3577),
                                  Color(0xFF141B44),
                                ],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF192155)
                                      .withOpacity(0.35),
                                  blurRadius: 14,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: _isLoading ? null : _login,
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                                child: _isLoading
                                    ? const Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              valueColor:
                                                  AlwaysStoppedAnimation<
                                                      Color>(Colors.white),
                                            ),
                                          ),
                                          SizedBox(width: 12),
                                          Text(
                                            "Logging in...",
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 16,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ],
                                      )
                                    : const Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.login_rounded,
                                            color: Colors.white,
                                            size: 18,
                                          ),
                                          SizedBox(width: 10),
                                          Text(
                                            "Login",
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 16,
                                              fontWeight: FontWeight.w700,
                                              letterSpacing: 0.2,
                                            ),
                                          ),
                                        ],
                                      ),
                              ),
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
        ),
      ),
    );
  }
}