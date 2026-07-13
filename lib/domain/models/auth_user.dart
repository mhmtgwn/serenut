// lib/domain/models/auth_user.dart
// PHASE 0 - Auth Contract (Day 1)
// Generated: 20 Jun 2026

import 'dart:convert';
import 'package:serenutos/domain/models/permission.dart';

class AuthUser {
  final String id;
  final String companyId;
  final String name;
  final String email;
  final String? username;
  final String? pin;
  final String? businessCode;
  final UserRole role;
  final List<String> permissions;
  final DateTime createdAt;

  const AuthUser({
    required this.id,
    this.companyId = 'TEST_COMPANY',
    required this.name,
    required this.email,
    this.username,
    this.pin,
    this.businessCode,
    required this.role,
    required this.permissions,
    required this.createdAt,
  });

  /// Check if user has a specific permission
  bool hasPermission(String permission) => permissions.contains(permission);

  /// Check if user has ALL required permissions
  bool hasAllPermissions(List<String> required) =>
      required.every(hasPermission);

  /// Check if user has ANY of the required permissions
  bool hasAnyPermission(List<String> any) =>
      any.any(hasPermission);

  /// Get all permission names for UI display
  List<String> getAllPermissions() => List.unmodifiable(permissions);

  /// Serialization for SharedPreferences storage
  Map<String, dynamic> toMap() => {
    'id': id,
    'companyId': companyId,
    'name': name,
    'email': email,
    'username': username,
    'pin': pin,
    'businessCode': businessCode,
    'role': role.name,
    'permissions': permissions,
    'created_at': createdAt.toIso8601String(),
  };

  /// Deserialization from SharedPreferences
  factory AuthUser.fromMap(Map<String, dynamic> map) => AuthUser(
    id: map['id'] as String,
    companyId: map['companyId'] as String? ?? 'TEST_COMPANY',
    name: map['name'] as String,
    email: map['email'] as String? ?? '',
    username: map['username'] as String?,
    pin: map['pin'] as String?,
    businessCode: map['businessCode'] as String?,
    role: UserRole.values.firstWhere(
      (r) => r.name == map['role'],
      orElse: () => UserRole.cashier,
    ),
    permissions: List<String>.from(map['permissions'] as List),
    createdAt: DateTime.parse(map['created_at'] as String),
  );

  /// JSON serialization
  String toJson() => jsonEncode(toMap());

  /// JSON deserialization
  factory AuthUser.fromJson(String source) =>
      AuthUser.fromMap(jsonDecode(source) as Map<String, dynamic>);

  @override
  String toString() => 'AuthUser(id: $id, companyId: $companyId, name: $name, email: $email, username: $username, role: ${role.name})';

  AuthUser copyWith({
    String? id,
    String? companyId,
    String? name,
    String? email,
    String? username,
    String? pin,
    String? businessCode,
    UserRole? role,
    List<String>? permissions,
    DateTime? createdAt,
  }) {
    return AuthUser(
      id: id ?? this.id,
      companyId: companyId ?? this.companyId,
      name: name ?? this.name,
      email: email ?? this.email,
      username: username ?? this.username,
      pin: pin ?? this.pin,
      businessCode: businessCode ?? this.businessCode,
      role: role ?? this.role,
      permissions: permissions ?? this.permissions,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AuthUser &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          companyId == other.companyId &&
          name == other.name &&
          email == other.email &&
          username == other.username &&
          pin == other.pin &&
          businessCode == other.businessCode &&
          role == other.role;

  @override
  int get hashCode => id.hashCode ^ companyId.hashCode ^ name.hashCode ^ email.hashCode ^ role.hashCode;
}
