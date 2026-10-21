import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/config_url.dart';
import 'api_client.dart';

class AuthService {
  final ApiClient _apiClient = ApiClient();

  Map<String, dynamic> _safeJson(String body) {
    if (body.trim().isEmpty) return {};
    try {
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> ? decoded : {};
    } catch (_) {
      return {};
    }
  }

  Future<Map<String, dynamic>> _saveTokenAndRole(
    String fallbackUsername,
    Map<String, dynamic> data,
  ) async {
    final String token = data['token']?.toString() ?? '';
    final Map<String, dynamic> decodedToken = JwtDecoder.decode(token);

    final String role = data['role']?.toString() ??
        decodedToken['role']?.toString() ??
        decodedToken['http://schemas.microsoft.com/ws/2008/06/identity/claims/role']
            ?.toString() ??
        'Parent';

    final String username = data['username']?.toString() ??
        decodedToken['unique_name']?.toString() ??
        fallbackUsername;

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('jwt_token', token);
    await prefs.setString('user_role', role);
    await prefs.setString('saved_username', username);

    return {
      "success": true,
      "token": token,
      "role": role,
      "username": username,
      "similarity": data['similarity'],
      "message": data['message'] ?? "Đăng nhập thành công!",
      "decodedToken": decodedToken,
    };
  }

  // Đăng nhập trực tiếp bằng Username + Password -> Nhận ngay JWT Token & Role (Admin / Parent / Child)
  Future<Map<String, dynamic>> login(String username, String password) async {
    try {
      final response = await http.post(
        Uri.parse("${Config_URL.baseUrl}Authenticate/login"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "username": username,
          "password": password,
        }),
      );

      final data = _safeJson(response.body);
      if (response.statusCode == 200 && data['status'] == true) {
        if (data['token'] != null && data['token'].toString().isNotEmpty) {
          return await _saveTokenAndRole(username, data);
        }
        if (data['requiresOtp'] == true) {
          return {
            "success": true,
            "requiresOtp": true,
            "email": data['email']?.toString() ?? "",
            "message": data['message'] ?? "Đã gửi mã OTP",
          };
        }
      }
      return {
        "success": false,
        "requiresEmailConfirmation": data['requiresEmailConfirmation'] == true,
        "email": data['email']?.toString() ?? "",
        "message": data['message'] ?? "Tên đăng nhập hoặc mật khẩu không đúng!",
      };
    } catch (e) {
      return {
        "success": false,
        "message": "Không thể kết nối tới Web API: $e",
      };
    }
  }

  // Xác minh OTP (Bước 2 của Đăng nhập)
  Future<Map<String, dynamic>> verifyOtp(String username, String otpCode) async {
    try {
      final response = await http.post(
        Uri.parse("${Config_URL.baseUrl}Authenticate/verify-otp"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "username": username,
          "otpCode": otpCode,
        }),
      );
      final data = _safeJson(response.body);
      if (response.statusCode == 200 && data['status'] == true) {
        return await _saveTokenAndRole(username, data);
      }
      return {
        "success": false,
        "message": data['message'] ?? "Mã OTP không hợp lệ hoặc đã hết hạn!",
      };
    } catch (e) {
      return {"success": false, "message": "Lỗi kết nối Server: $e"};
    }
  }

  // Xác minh email sau khi đăng ký bằng mã 6 chữ số
  Future<Map<String, dynamic>> confirmEmail(String email, String code) async {
    try {
      final response = await http.post(
        Uri.parse("${Config_URL.baseUrl}Authenticate/confirm-email"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "email": email,
          "code": code,
        }),
      );
      final data = _safeJson(response.body);
      return {
        "success": response.statusCode == 200 && data['status'] == true,
        "message": data['message'] ?? "Không thể xác minh email!",
      };
    } catch (e) {
      return {"success": false, "message": "Lỗi kết nối Server: $e"};
    }
  }

  // Gửi lại mã xác minh email
  Future<Map<String, dynamic>> resendConfirmation(String email) async {
    try {
      final response = await http.post(
        Uri.parse("${Config_URL.baseUrl}Authenticate/resend-confirmation"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"email": email}),
      );
      final data = _safeJson(response.body);
      return {
        "success": response.statusCode == 200 && data['status'] == true,
        "message": data['message'] ?? "Không thể gửi lại mã!",
      };
    } catch (e) {
      return {"success": false, "message": "Lỗi kết nối Server: $e"};
    }
  }

  // Đăng ký khuôn mặt 2D (ArcFace) cho tài khoản đang đăng nhập
  Future<Map<String, dynamic>> registerFace(String faceDataBase64) async {
    try {
      final response = await _apiClient.post(
        'Authenticate/register-face',
        body: {"faceDataBase64": faceDataBase64},
      );
      final data = _safeJson(response.body);
      if (response.statusCode == 200 && data['status'] == true) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('face_enrolled', true);
        return {
          "success": true,
          "message": data['message'] ?? "Đăng ký khuôn mặt thành công!",
        };
      }
      return {
        "success": false,
        "message": data['message'] ?? "Đăng ký khuôn mặt thất bại!",
      };
    } catch (e) {
      return {"success": false, "message": "Lỗi kết nối Server: $e"};
    }
  }

  // Đăng nhập bằng khuôn mặt 2D (so khớp vector ArcFace trên backend)
  Future<Map<String, dynamic>> loginWithFace(
    String username,
    String faceDataBase64,
  ) async {
    try {
      final response = await http.post(
        Uri.parse("${Config_URL.baseUrl}Authenticate/login-face"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "username": username,
          "faceDataBase64": faceDataBase64,
        }),
      );
      final data = _safeJson(response.body);
      if (response.statusCode == 200 && data['status'] == true) {
        return await _saveTokenAndRole(username, data);
      }
      return {
        "success": false,
        "similarity": data['similarity'],
        "message": data['message'] ?? "Khuôn mặt không khớp!",
      };
    } catch (e) {
      return {"success": false, "message": "Lỗi kết nối Server: $e"};
    }
  }

  // Lấy thông tin tài khoản hiện tại (/api/Authenticate/me)
  Future<Map<String, dynamic>?> getMe() async {
    try {
      final response = await _apiClient.get('Authenticate/me');
      if (response.statusCode == 200) {
        return _safeJson(response.body);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  // Kiểm tra mật khẩu phụ huynh khi tài khoản Trẻ em muốn đăng xuất
  Future<Map<String, dynamic>> verifyParentPassword({
    required String parentPassword,
    int? deviceId,
  }) async {
    try {
      final response = await _apiClient.post(
        'Authenticate/verify-parent-password',
        body: {
          if (deviceId != null) "deviceId": deviceId,
          "parentPassword": parentPassword,
        },
      );
      final data = _safeJson(response.body);
      return {
        "success": response.statusCode == 200 && data['status'] == true,
        "parentUsername": data['parentUsername'],
        "message": data['message'] ?? "Mật khẩu phụ huynh không đúng!",
      };
    } catch (e) {
      return {"success": false, "message": "Lỗi kết nối Server: $e"};
    }
  }
}
