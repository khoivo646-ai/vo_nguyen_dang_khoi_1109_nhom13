import 'package:flutter/material.dart';
import '../utils/auth.dart';

class EmailConfirmScreen extends StatefulWidget {
  final String email;
  final String maskedEmail;
  final String initialMessage;

  const EmailConfirmScreen({
    super.key,
    required this.email,
    required this.maskedEmail,
    required this.initialMessage,
  });

  @override
  State<EmailConfirmScreen> createState() => _EmailConfirmScreenState();
}

class _EmailConfirmScreenState extends State<EmailConfirmScreen> {
  late final TextEditingController _emailController;
  final TextEditingController _codeController = TextEditingController();
  bool _isSubmitting = false;
  bool _isResending = false;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController(text: widget.email);
  }

  Future<void> _handleConfirm() async {
    final email = _emailController.text.trim();
    final code = _codeController.text.trim();
    if (email.isEmpty || code.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vui lòng nhập đúng địa chỉ Email và mã xác minh 6 chữ số!'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    final res = await Auth.confirmEmail(email, code);
    setState(() => _isSubmitting = false);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(res['message'] ?? ''),
        backgroundColor: res['success'] == true ? Colors.green : Colors.red,
      ),
    );

    if (res['success'] == true) {
      Navigator.pop(context, true);
    }
  }

  Future<void> _handleResend() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vui lòng nhập địa chỉ Email đã đăng ký!'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isResending = true);
    final res = await Auth.resendConfirmation(email);
    setState(() => _isResending = false);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(res['message'] ?? ''),
        backgroundColor: res['success'] == true ? Colors.teal : Colors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F6FB),
      appBar: AppBar(
        title: const Text('Xác Minh Địa Chỉ Email'),
        backgroundColor: Colors.indigo.shade700,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Card(
          elevation: 4,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              children: [
                const Icon(
                  Icons.mark_email_read_rounded,
                  size: 68,
                  color: Colors.indigo,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Kích Hoạt Tài Khoản Qua Email',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.initialMessage,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.black54, fontSize: 13.5),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: 'Email đã đăng ký',
                    prefixIcon: const Icon(Icons.email_outlined),
                    filled: true,
                    fillColor: Colors.grey.shade100,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _codeController,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 10,
                    color: Colors.indigo,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Mã xác minh 6 số trong Email',
                    hintText: '000000',
                    filled: true,
                    fillColor: Colors.grey.shade100,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: _isSubmitting ? null : _handleConfirm,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.indigo.shade700,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: const Icon(Icons.verified_rounded, color: Colors.white),
                    label: _isSubmitting
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.5,
                            ),
                          )
                        : const Text(
                            'XÁC MINH EMAIL',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 10),
                TextButton.icon(
                  onPressed: _isResending ? null : _handleResend,
                  icon: const Icon(Icons.refresh),
                  label: Text(
                    _isResending
                        ? 'Đang gửi lại mã...'
                        : 'Chưa nhận được email? Gửi lại mã xác minh',
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
