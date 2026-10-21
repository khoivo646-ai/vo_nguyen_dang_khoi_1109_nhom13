import 'package:flutter/material.dart';
import '../utils/auth.dart';
import 'admin_screen.dart';
import 'child_screen.dart';
import 'customer_screen.dart';

class OtpVerifyScreen extends StatefulWidget {
  final String username;
  final String maskedEmail;
  final String serverMessage;

  const OtpVerifyScreen({
    super.key,
    required this.username,
    required this.maskedEmail,
    required this.serverMessage,
  });

  @override
  State<OtpVerifyScreen> createState() => _OtpVerifyScreenState();
}

class _OtpVerifyScreenState extends State<OtpVerifyScreen> {
  final TextEditingController _otpController = TextEditingController();
  bool _isLoading = false;

  void _navigateByRole(String role) {
    Widget destination;
    if (role == 'Admin') {
      destination = const AdminScreen();
    } else if (role == 'Child') {
      destination = const ChildScreen();
    } else {
      destination = const CustomerScreen();
    }

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => destination),
      (route) => false, // Xóa hết stack cũ
    );
  }

  Future<void> _verifyOtp() async {
    final otpCode = _otpController.text.trim();
    if (otpCode.isEmpty || otpCode.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vui lòng nhập đủ 6 chữ số OTP!'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    final result = await Auth.verifyOtp(widget.username, otpCode);
    setState(() => _isLoading = false);

    if (!mounted) return;

    if (result['success'] == true) {
      final String role = result['role']?.toString() ?? 'Parent';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Đăng nhập thành công với vai trò: $role'),
          backgroundColor: Colors.green,
        ),
      );
      _navigateByRole(role);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result['message'] ?? 'Xác minh OTP thất bại'),
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
        title: const Text('Xác Thực Mã OTP'),
        backgroundColor: Colors.indigo.shade700,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Card(
            elevation: 4,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.indigo.shade50,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.mark_email_read, size: 48, color: Colors.indigo.shade700),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Nhập mã OTP',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.serverMessage.isNotEmpty
                        ? widget.serverMessage
                        : 'Mã xác thực đã được gửi tới email ${widget.maskedEmail}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.black54),
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _otpController,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 24, letterSpacing: 8, fontWeight: FontWeight.bold),
                    decoration: InputDecoration(
                      hintText: '000000',
                      counterText: '',
                      filled: true,
                      fillColor: Colors.grey.shade100,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _verifyOtp,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.indigo.shade700,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                            )
                          : const Text(
                              'XÁC NHẬN OTP',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
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