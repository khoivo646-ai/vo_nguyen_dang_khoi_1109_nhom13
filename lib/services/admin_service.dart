import 'dart:convert';
import 'api_client.dart';

class UserAccountItem {
  final String id;
  final String username;
  final String email;
  final bool emailConfirmed;
  final List<String> roles;
  final bool hasFace;
  final bool isLockedOut;

  UserAccountItem({
    required this.id,
    required this.username,
    required this.email,
    required this.emailConfirmed,
    required this.roles,
    required this.hasFace,
    required this.isLockedOut,
  });

  String get primaryRole => roles.isNotEmpty ? roles.first : 'Parent';

  factory UserAccountItem.fromJson(Map<String, dynamic> json) {
    final rawRoles = (json['roles'] as List<dynamic>? ?? [])
        .map((e) => e.toString())
        .toList();
    return UserAccountItem(
      id: json['id']?.toString() ?? '',
      username: json['username']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      emailConfirmed: json['emailConfirmed'] == true,
      roles: rawRoles,
      hasFace: json['hasFace'] == true,
      isLockedOut: json['isLockedOut'] == true,
    );
  }
}

class AdminService {
  final ApiClient _apiClient = ApiClient();

  Future<List<UserAccountItem>> getUsers({String? search}) async {
    String endpoint = 'Admin/users';
    if (search != null && search.trim().isNotEmpty) {
      endpoint += '?search=${Uri.encodeComponent(search.trim())}';
    }
    final response = await _apiClient.get(endpoint);
    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((item) => UserAccountItem.fromJson(item)).toList();
    }
    throw Exception('Không tải được danh sách tài khoản (${response.statusCode})');
  }

  // Admin cấp tài khoản mới trực tiếp (Admin / Parent / Child)
  Future<Map<String, dynamic>> createUser({
    required String username,
    required String email,
    required String password,
    required String role,
    String? initials,
  }) async {
    final response = await _apiClient.post(
      'Admin/users',
      body: {
        "username": username,
        "email": email,
        "password": password,
        "role": role,
        "initials": initials ?? "KG",
      },
    );
    final data = response.body.isNotEmpty ? jsonDecode(response.body) : {};
    return {
      "success": response.statusCode == 200 && data['status'] == true,
      "message": data['message'] ?? "Lỗi cấp tài khoản",
    };
  }

  // Admin đổi quyền của người dùng (Admin / Parent / Child)
  Future<Map<String, dynamic>> setUserRole(String username, String role) async {
    final response = await _apiClient.put(
      'Admin/users/${Uri.encodeComponent(username)}/role',
      body: {"role": role},
    );
    final data = response.body.isNotEmpty ? jsonDecode(response.body) : {};
    return {
      "success": response.statusCode == 200 && data['status'] == true,
      "message": data['message'] ?? "Lỗi đổi quyền",
    };
  }

  // Admin mở khóa tài khoản bị tạm khóa
  Future<Map<String, dynamic>> unlockUser(String username) async {
    final response = await _apiClient.put(
      'Admin/users/${Uri.encodeComponent(username)}/unlock',
      body: {},
    );
    final data = response.body.isNotEmpty ? jsonDecode(response.body) : {};
    return {
      "success": response.statusCode == 200 && data['status'] == true,
      "message": data['message'] ?? "Lỗi mở khóa tài khoản",
    };
  }

  // Admin xóa tài khoản
  Future<Map<String, dynamic>> deleteUser(String username) async {
    final response = await _apiClient.delete(
      'Admin/users/${Uri.encodeComponent(username)}',
    );
    final data = response.body.isNotEmpty ? jsonDecode(response.body) : {};
    return {
      "success": response.statusCode == 200 && data['status'] == true,
      "message": data['message'] ?? "Lỗi xóa tài khoản",
    };
  }
}
