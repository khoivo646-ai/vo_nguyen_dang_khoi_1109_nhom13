import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';

class Auth {
  static final AuthService _authService = AuthService();
  static final ApiClient _apiClient = ApiClient();

  static Future<Map<String, dynamic>> login(
    String username,
    String password,
  ) async {
    return await _authService.login(username, password);
  }

  static Future<Map<String, dynamic>> verifyOtp(
    String username,
    String otpCode,
  ) async {
    return await _authService.verifyOtp(username, otpCode);
  }

  static Future<Map<String, dynamic>> confirmEmail(
    String email,
    String code,
  ) async {
    return await _authService.confirmEmail(email, code);
  }

  static Future<Map<String, dynamic>> resendConfirmation(String email) async {
    return await _authService.resendConfirmation(email);
  }

  static Future<Map<String, dynamic>> registerFace(
    String faceDataBase64,
  ) async {
    return await _authService.registerFace(faceDataBase64);
  }

  static Future<Map<String, dynamic>> loginWithFace(
    String username,
    String faceDataBase64,
  ) async {
    return await _authService.loginWithFace(username, faceDataBase64);
  }

  static Future<Map<String, dynamic>?> getMe() async {
    return await _authService.getMe();
  }

  static Future<Map<String, dynamic>> verifyParentPassword({
    required String parentPassword,
    int? deviceId,
  }) async {
    return await _authService.verifyParentPassword(
      parentPassword: parentPassword,
      deviceId: deviceId,
    );
  }

  // Đăng ký tài khoản qua Email (chỉ chọn role Parent hoặc Child)
  static Future<Map<String, dynamic>> register({
    required String username,
    required String email,
    required String password,
    required String initials,
    required String role,
  }) async {
    Map<String, dynamic> body = {
      "username": username,
      "email": email,
      "password": password,
      "initials": initials,
      "role": role,
    };

    try {
      var response = await _apiClient.post('Authenticate/register', body: body);
      Map<String, dynamic> result = {};
      if (response.body.trim().isNotEmpty) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) result = decoded;
      }

      if (response.statusCode == 200 && result['status'] == true) {
        return {
          'success': true,
          'requiresEmailConfirmation':
              result['requiresEmailConfirmation'] ?? true,
          'email': result['email'] ?? email,
          'message': result['message'] ?? 'Đăng ký thành công!',
        };
      } else {
        return {
          'success': false,
          'message':
              result['message'] ?? 'Đăng ký thất bại, vui lòng kiểm tra lại.',
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Lỗi kết nối Server: $e',
      };
    }
  }

  // Đăng xuất: xóa jwt_token nhưng giữ lại username để đăng nhập nhanh bằng khuôn mặt
  static Future<void> logout() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove('jwt_token');
  }
}
