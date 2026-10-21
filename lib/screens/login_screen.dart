import 'package:flutter/material.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/auth.dart';
import 'admin_screen.dart';
import 'child_screen.dart';
import 'customer_screen.dart';
import 'email_confirm_screen.dart';
import 'face_auth_screen.dart';
import 'otp_verify_screen.dart';
import 'registration_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _checkToken();
  }

  // Tự động đăng nhập lại và vào ĐÚNG màn hình theo Role (Admin / Parent / Child) khi mở lại App
  Future<void> _checkToken() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? token = prefs.getString('jwt_token');
    String? savedUser = prefs.getString('saved_username');

    if (savedUser != null) {
      _usernameController.text = savedUser;
    }

    if (token != null && token.isNotEmpty && !JwtDecoder.isExpired(token)) {
      final me = await Auth.getMe();
      if (me != null) {
        final String role = me['role']?.toString() ?? 'Parent';
        await prefs.setString('user_role', role);
        if (!mounted) return;
        _navigateByRole(role);
        return;
      }

      Map<String, dynamic> decoded = JwtDecoder.decode(token);
      String role = prefs.getString('user_role') ??
          decoded['role']?.toString() ??
          decoded['http://schemas.microsoft.com/ws/2008/06/identity/claims/role']
              ?.toString() ??
          'Parent';

      if (!mounted) return;
      _navigateByRole(role);
    }
  }

  void _navigateByRole(String role) {
    Widget destination;
    if (role == 'Admin') {
      destination = const AdminScreen();
    } else if (role == 'Child') {
      destination = const ChildScreen();
    } else {
      destination = const CustomerScreen();
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => destination),
    );
  }

  // Đăng nhập trực tiếp bằng Username + Password -> Nhận JWT Token & vào thẳng màn hình theo Role
  Future<void> _handleLogin() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    if (username.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vui lòng nhập đầy đủ Tên đăng nhập và Mật khẩu!'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    final result = await Auth.login(username, password);
    setState(() => _isLoading = false);

    if (!mounted) return;

    if (result['success'] == true) {
      if (result['requiresOtp'] == true) {
        // Luồng mới: Backend yêu cầu OTP
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => OtpVerifyScreen(
              username: username,
              maskedEmail: result['email']?.toString() ?? '',
              serverMessage: result['message']?.toString() ?? '',
            ),
          ),
        );
      } else {
        // (Dự phòng) Nếu backend trả token trực tiếp
        final String role = result['role']?.toString() ?? 'Parent';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Đăng nhập thành công với vai trò: $role'),
            backgroundColor: Colors.green,
          ),
        );
        _navigateByRole(role);
      }
    } else if (result['requiresEmailConfirmation'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message'] ?? 'Email chưa được xác minh!'),
          backgroundColor: Colors.orange.shade800,
        ),
      );
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => EmailConfirmScreen(
            email: '',
            maskedEmail: result['email']?.toString() ?? '',
            initialMessage: result['message']?.toString() ??
                'Tài khoản chưa xác minh email. Vui lòng nhập mã xác minh đã gửi tới hộp thư.',
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message'] ?? 'Đăng nhập thất bại'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // Chức năng 5a: Đăng nhập bằng Khuôn mặt thật (chụp ảnh -> so khớp ArcFace trên Server -> nhận JWT)
  Future<void> _handleFaceLogin() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    String initialUser = _usernameController.text.trim().isNotEmpty
        ? _usernameController.text.trim()
        : (prefs.getString('saved_username') ?? '');

    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => FaceAuthScreen(
          mode: FaceAuthMode.login,
          initialUsername: initialUser,
        ),
      ),
    );

    if (result != null && result['success'] == true && mounted) {
      final String role = result['role']?.toString() ?? 'Parent';
      _navigateByRole(role);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F6FB),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding:
                const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.indigo.shade700, Colors.blue.shade500],
                    ),
                    shape: BoxShape.circle,
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black12,
                        blurRadius: 12,
                        offset: Offset(0, 6),
                      )
                    ],
                  ),
                  child: const Icon(
                    Icons.shield_moon_rounded,
                    size: 58,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'KIDGUARD PARENTAL',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    color: Colors.indigo.shade900,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Quản Lý Điện Thoại Trẻ Em - Nhóm 13',
                  style: TextStyle(color: Colors.blueGrey, fontSize: 13.5),
                ),
                const SizedBox(height: 28),
                Card(
                  elevation: 5,
                  shadowColor: Colors.black12,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(22.0),
                    child: Column(
                      children: [
                        TextField(
                          controller: _usernameController,
                          decoration: InputDecoration(
                            labelText: 'Tên đăng nhập',
                            hintText: 'Nhập username của bạn',
                            prefixIcon: const Icon(Icons.person_outline),
                            filled: true,
                            fillColor: Colors.grey.shade100,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          decoration: InputDecoration(
                            labelText: 'Mật khẩu',
                            hintText: 'Nhập mật khẩu',
                            prefixIcon: const Icon(Icons.lock_outline),
                            filled: true,
                            fillColor: Colors.grey.shade100,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide.none,
                            ),
                            suffixIcon: IconButton(
                              icon: Icon(_obscurePassword
                                  ? Icons.visibility_off
                                  : Icons.visibility),
                              onPressed: () {
                                setState(
                                    () => _obscurePassword = !_obscurePassword);
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton.icon(
                            onPressed: _isLoading ? null : _handleLogin,
                            icon: const Icon(
                              Icons.login_rounded,
                              color: Colors.white,
                            ),
                            label: _isLoading
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2.5,
                                    ),
                                  )
                                : const Text(
                                    'ĐĂNG NHẬP',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.indigo.shade700,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: OutlinedButton.icon(
                            onPressed: _handleFaceLogin,
                            icon: const Icon(
                              Icons.face_retouching_natural,
                              color: Colors.indigo,
                            ),
                            label: const Text(
                              'Đăng nhập bằng Khuôn mặt AI (ArcFace)',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: Colors.indigo,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(
                                color: Colors.indigo.shade300,
                                width: 1.5,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text("Chưa có tài khoản? "),
                    TextButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const RegistrationScreen(),
                          ),
                        );
                      },
                      child: const Text(
                        'Đăng ký qua Email ngay',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.indigo,
                        ),
                      ),
                    ),
                  ],
                ),
                TextButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const EmailConfirmScreen(
                          email: '',
                          maskedEmail: '',
                          initialMessage:
                              'Nhập email đã đăng ký và mã 6 chữ số trong hộp thư để kích hoạt tài khoản.',
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.verified_outlined, size: 18),
                  label: const Text('Đã đăng ký nhưng chưa xác minh Email?'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
