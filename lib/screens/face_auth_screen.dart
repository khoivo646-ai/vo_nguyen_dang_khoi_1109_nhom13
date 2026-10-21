import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:local_auth/local_auth.dart';
import '../utils/auth.dart';

enum FaceAuthMode {
  register,
  login,
}

/// Màn hình Chụp ảnh khuôn mặt & So khớp vector ArcFace 512 chiều trên Backend:
/// - Chế độ [FaceAuthMode.register]: chụp/chọn ảnh chân dung và gọi POST /api/Authenticate/register-face.
/// - Chế độ [FaceAuthMode.login]: kiểm tra sinh trắc học thiết bị (nếu có) + chụp ảnh khuôn mặt gửi lên
///   POST /api/Authenticate/login-face để server tính cosine similarity (>= 0.42) và cấp JWT Token thật.
class FaceAuthScreen extends StatefulWidget {
  final FaceAuthMode mode;
  final String? initialUsername;

  const FaceAuthScreen({
    super.key,
    required this.mode,
    this.initialUsername,
  });

  @override
  State<FaceAuthScreen> createState() => _FaceAuthScreenState();
}

class _FaceAuthScreenState extends State<FaceAuthScreen> {
  final ImagePicker _picker = ImagePicker();
  final LocalAuthentication _localAuth = LocalAuthentication();
  late final TextEditingController _usernameController;

  Uint8List? _imageBytes;
  String? _imageBase64;
  bool _isProcessing = false;
  String? _statusText;
  bool _biometricChecked = false;

  @override
  void initState() {
    super.initState();
    _usernameController =
        TextEditingController(text: widget.initialUsername ?? '');
  }

  Future<void> _pickFaceImage(ImageSource source) async {
    try {
      final XFile? file = await _picker.pickImage(
        source: source,
        preferredCameraDevice: CameraDevice.front,
        maxWidth: 960,
        maxHeight: 960,
        imageQuality: 88,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      setState(() {
        _imageBytes = bytes;
        _imageBase64 = base64Encode(bytes);
        _statusText =
            'Đã chọn ảnh (${(bytes.length / 1024).toStringAsFixed(0)} KB). Bấm xác nhận để gửi lên AI ArcFace.';
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Không mở được camera/thư viện: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _verifyDeviceBiometricIfAvailable() async {
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      final supported = await _localAuth.isDeviceSupported();
      if (canCheck || supported) {
        final ok = await _localAuth.authenticate(
          localizedReason:
              'Xác thực sinh trắc học thiết bị kết hợp nhận diện khuôn mặt AI',
        );
        if (mounted) setState(() => _biometricChecked = ok);
      }
    } catch (_) {}
  }

  Future<void> _submitFace() async {
    if (_imageBase64 == null || _imageBase64!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vui lòng chụp hoặc chọn ảnh khuôn mặt trước!'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (widget.mode == FaceAuthMode.login &&
        _usernameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vui lòng nhập Tên đăng nhập cần nhận diện khuôn mặt!'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isProcessing = true;
      _statusText = widget.mode == FaceAuthMode.register
          ? 'Đang phát hiện khuôn mặt (SCRFD) & trích xuất vector ArcFace 512 chiều...'
          : 'Đang trích xuất vector khuôn mặt & so khớp Cosine Similarity trên Server...';
    });

    if (widget.mode == FaceAuthMode.login && !_biometricChecked) {
      await _verifyDeviceBiometricIfAvailable();
    }

    Map<String, dynamic> res;
    if (widget.mode == FaceAuthMode.register) {
      res = await Auth.registerFace(_imageBase64!);
    } else {
      res = await Auth.loginWithFace(
        _usernameController.text.trim(),
        _imageBase64!,
      );
    }

    if (!mounted) return;
    setState(() {
      _isProcessing = false;
      final sim = res['similarity'];
      _statusText = sim != null
          ? '${res['message']} (Độ tương đồng Cosine: ${(sim as num).toStringAsFixed(3)})'
          : res['message']?.toString();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_statusText ?? ''),
        backgroundColor: res['success'] == true ? Colors.green : Colors.red,
      ),
    );

    if (res['success'] == true) {
      Navigator.pop(context, res);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isRegister = widget.mode == FaceAuthMode.register;
    return Scaffold(
      backgroundColor: const Color(0xFFF3F6FB),
      appBar: AppBar(
        backgroundColor: Colors.indigo.shade700,
        foregroundColor: Colors.white,
        title: Text(
          isRegister
              ? 'Đăng Ký Khuôn Mặt AI (ArcFace)'
              : 'Đăng Nhập Bằng Khuôn Mặt AI',
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Card(
          elevation: 4,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.indigo.shade50,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.face_retouching_natural,
                          color: Colors.indigo, size: 28),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          isRegister
                              ? 'Hãy chụp ảnh rõ 1 khuôn mặt chính diện. Backend sẽ phát hiện 5 điểm landmark và lưu vector đặc trưng ArcFace 512 chiều.'
                              : 'Chụp ảnh khuôn mặt hiện tại để Backend so khớp Cosine Similarity (>= 0.42) với khuôn mặt đã đăng ký.',
                          style: const TextStyle(fontSize: 12.8),
                        ),
                      ),
                    ],
                  ),
                ),
                if (!isRegister) ...[
                  const SizedBox(height: 16),
                  TextField(
                    controller: _usernameController,
                    decoration: InputDecoration(
                      labelText: 'Tên đăng nhập *',
                      prefixIcon: const Icon(Icons.person_outline),
                      filled: true,
                      fillColor: Colors.grey.shade100,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                Container(
                  width: 230,
                  height: 230,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: _imageBytes != null
                          ? Colors.indigo
                          : Colors.grey.shade300,
                      width: 2.5,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _imageBytes != null
                      ? Image.memory(_imageBytes!, fit: BoxFit.cover)
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.camera_front_rounded,
                                size: 68, color: Colors.indigo.shade300),
                            const SizedBox(height: 10),
                            const Text(
                              'Chưa có ảnh khuôn mặt',
                              style: TextStyle(color: Colors.black54),
                            ),
                          ],
                        ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _isProcessing
                            ? null
                            : () => _pickFaceImage(ImageSource.camera),
                        icon: const Icon(Icons.photo_camera),
                        label: const Text('Chụp Camera'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _isProcessing
                            ? null
                            : () => _pickFaceImage(ImageSource.gallery),
                        icon: const Icon(Icons.photo_library_outlined),
                        label: const Text('Chọn Ảnh Có Sẵn'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                if (_statusText != null) ...[
                  const SizedBox(height: 14),
                  Text(
                    _statusText!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.indigo.shade900,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: _isProcessing ? null : _submitFace,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.indigo.shade700,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: const Icon(Icons.verified_user_rounded,
                        color: Colors.white),
                    label: _isProcessing
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.5,
                            ),
                          )
                        : Text(
                            isRegister
                                ? 'LƯU KHUÔN MẶT LÊN SERVER'
                                : 'SO KHỚP KHUÔN MẶT & ĐĂNG NHẬP',
                            style: const TextStyle(
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
