import 'dart:convert';

class UserResponse {
  final String message;
  final String token;
  final User user;

  UserResponse({
    required this.message,
    required this.token,
    required this.user,
  });

  factory UserResponse.fromJson(Map<String, dynamic> json) {
    return UserResponse(
      message: json['message'] as String,
      token: json['token'] as String,
      user: User.fromJson(json['user'] as Map<String, dynamic>),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'message': message,
      'token': token,
      'user': user.toJson(),
    };
  }
}

class User {
  final String id;
  final String name;
  final String phone;
  final String? email;
  final String role;
  final String status;
  final Permissions permissions;

  User({
    required this.id,
    required this.name,
    required this.phone,
    this.email,
    required this.role,
    required this.status,
    required this.permissions,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as String,
      name: json['name'] as String,
      phone: json['phone'] as String,
      email: json['email'] as String?,
      role: json['role'] as String,
      status: json['status'] as String,
      permissions: Permissions.fromJson(json['permissions'] as Map<String, dynamic>),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'phone': phone,
      'email': email,
      'role': role,
      'status': status,
      'permissions': permissions.toJson(),
    };
  }
}

class Permissions {
  final List<String> app;
  final List<String> web;

  Permissions({
    required this.app,
    required this.web,
  });

  factory Permissions.fromJson(Map<String, dynamic> json) {
    return Permissions(
      app: List<String>.from(json['app'] as List<dynamic>),
      web: List<String>.from(json['web'] as List<dynamic>),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'app': app,
      'web': web,
    };
  }
}