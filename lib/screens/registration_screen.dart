import 'package:flutter/material.dart';
import '../utils/auth.dart';
import 'email_confirm_screen.dart';

class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({super.key});

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _initialsController = TextEditingController();

  // Chỉ được chọn Parent (Phụ huynh) hoặc Child (Trẻ em) theo đúng đề bài
  String _selectedRole = 'Parent';
  bool _isLoading = false;
  bool _obscurePassword = true;

  Future<void> _handleRegister() async {
    final username = _usernameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (username.isEmpty || email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vui lòng nhập đầy đủ Tên đăng nhập, Email và Mật khẩu!'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    Map<String, dynamic> result = await Auth.register(
      username: username,
      email: email,
      password: password,
      initials: _initialsController.text.trim().isEmpty
          ? 'KG'
          : _initialsController.text.trim(),
      role: _selectedRole,
    );
    setState(() => _isLoading = false);

    if (!mounted) return;

    if (result['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message'] ?? 'Đăng ký thành công!'),
          backgroundColor: Colors.green,
        ),
      );

      // Chuyển sang màn hình nhập mã xác minh Email 6 chữ số đã gửi tới hộp thư
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => EmailConfirmScreen(
            email: email,
            maskedEmail: result['email']?.toString() ?? email,
            initialMessage: result['message']?.toString() ??
                'Mã xác minh 6 chữ số đã được gửi tới email của bạn.',
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message'] ?? 'Đăng ký thất bại'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F6FB),
      appBar: AppBar(
        title: const Text('Đăng Ký Tài Khoản Qua Email'),
        backgroundColor: Colors.indigo.shade700,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Card(
          elevation: 4,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.indigo.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.indigo),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Tài khoản tự đăng ký chỉ được chọn Phụ huynh (Parent) hoặc Trẻ em (Child). Tài khoản Admin do quản trị viên cấp.',
                          style: TextStyle(fontSize: 12.5, color: Colors.black87),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _usernameController,
                  decoration: InputDecoration(
                    labelText: 'Tên đăng nhập *',
                    hintText: 'VD: phu_huynh_01 hoặc be_minh_an',
                    prefixIcon: const Icon(Icons.person),
                    filled: true,
                    fillColor: Colors.grey.shade100,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: 'Email xác minh & nhận OTP *',
                    prefixIcon: const Icon(Icons.email),
                    filled: true,
                    fillColor: Colors.grey.shade100,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    labelText: 'Mật khẩu (>= 6 ký tự) *',
                    prefixIcon: const Icon(Icons.lock),
                    filled: true,
                    fillColor: Colors.grey.shade100,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    suffixIcon: IconButton(
                      icon: Icon(_obscurePassword
                          ? Icons.visibility_off
                          : Icons.visibility),
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _initialsController,
                  decoration: InputDecoration(
                    labelText: 'Ký tự viết tắt (VD: PH, TE)',
                    prefixIcon: const Icon(Icons.badge),
                    filled: true,
                    fillColor: Colors.grey.shade100,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: _selectedRole,
                  decoration: InputDecoration(
                    labelText: 'Vai trò tài khoản *',
                    prefixIcon: const Icon(Icons.family_restroom),
                    filled: true,
                    fillColor: Colors.grey.shade100,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'Parent',
                      child: Text('Phụ huynh (Parent) - Quản lý thiết bị con'),
                    ),
                    DropdownMenuItem(
                      value: 'Child',
                      child: Text('Trẻ em (Child) - Thiết bị chịu sự giám sát'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _selectedRole = value);
                  },
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _handleRegister,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.indigo.shade700,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: const Icon(Icons.mark_email_unread_outlined,
                        color: Colors.white),
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
                            'ĐĂNG KÝ & NHẬN MÃ XÁC MINH EMAIL',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14.5,
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
