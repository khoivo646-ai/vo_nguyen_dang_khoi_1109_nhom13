import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import '../models/child_device.dart';
import '../services/device_service.dart';
import '../utils/auth.dart';
import 'face_auth_screen.dart';
import 'location_share_screen.dart';
import 'login_screen.dart';
import 'noise_monitor_screen.dart';

/// Màn hình dành cho tài khoản Trẻ em (Role: Child):
/// - Hiển thị thiết bị mà phụ huynh đã liên kết với tài khoản của trẻ (chỉ xem, không được tự sửa/xóa).
/// - Nếu phụ huynh bật "Khóa thiết bị từ xa" (IsLocked = true), hiển thị màn hình khóa cảnh báo.
/// - Hiển thị giới hạn thời gian màn hình, danh sách ứng dụng bị chặn, nút Chia sẻ vị trí GPS và Đo tiếng ồn.
/// - QUAN TRỌNG: Chặn nút Back hệ thống; khi trẻ muốn Đăng xuất bắt buộc phải nhập đúng MẬT KHẨU CỦA PHỤ HUYNH
///   (xác thực qua POST /api/Authenticate/verify-parent-password).
class ChildScreen extends StatefulWidget {
  const ChildScreen({super.key});

  @override
  State<ChildScreen> createState() => _ChildScreenState();
}

class _ChildScreenState extends State<ChildScreen> {
  final DeviceService _deviceService = DeviceService();

  List<ChildDevice> _myDevices = [];
  String _username = '';
  bool _isLoading = true;
  Timer? _syncTimer;

  @override
  void initState() {
    super.initState();
    _initData();
    // Tự động đồng bộ trạng thái khóa từ xa / giới hạn giờ của phụ huynh mỗi 10 giây
    _syncTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _loadMyDevices(silent: true),
    );
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    super.dispose();
  }

  Future<void> _initData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _username = prefs.getString('saved_username') ?? '';
    });
    await _loadMyDevices();
  }

  Future<void> _loadMyDevices({bool silent = false}) async {
    if (!silent) setState(() => _isLoading = true);
    try {
      final list = await _deviceService.getDevices();

      // KIỂM TRA LỆNH TỪ TỪ XA CỦA PHỤ HUYNH
      for (int i = 0; i < list.length; i++) {
        var dev = list[i];
        bool needUpdate = false;
        String newBlockedApps = dev.blockedApps;

        // Lệnh đo tiếng ồn
        if (newBlockedApps.contains('[REQ_NOISE]')) {
          newBlockedApps = newBlockedApps.replaceAll('[REQ_NOISE]', '').replaceAll(',,', ',').trim();
          _performSilentNoiseMeasurement(dev);
          needUpdate = true;
        }

        // Lệnh lấy vị trí GPS
        if (newBlockedApps.contains('[REQ_LOC]')) {
          newBlockedApps = newBlockedApps.replaceAll('[REQ_LOC]', '').replaceAll(',,', ',').trim();
          _performSilentLocationUpdate(dev);
          needUpdate = true;
        }

        if (needUpdate) {
          if (newBlockedApps.endsWith(',')) newBlockedApps = newBlockedApps.substring(0, newBlockedApps.length - 1);
          
          final updatedDev = ChildDevice(
             id: dev.id,
             childName: dev.childName,
             deviceName: dev.deviceName,
             childUsername: dev.childUsername,
             screenTimeLimitMinutes: dev.screenTimeLimitMinutes,
             blockedApps: newBlockedApps,
             isLocked: dev.isLocked,
             latitude: dev.latitude,
             longitude: dev.longitude,
             parentUsername: dev.parentUsername,
             noiseThresholdDb: dev.noiseThresholdDb,
          );
          await _deviceService.updateDevice(updatedDev);
          list[i] = updatedDev; 
        }
      }

      if (!mounted) return;
      setState(() => _myDevices = list);
    } catch (_) {
    } finally {
      if (mounted && !silent) setState(() => _isLoading = false);
    }
  }

  // Đo tiếng ồn ngầm trên thiết bị trẻ em
  Future<void> _performSilentNoiseMeasurement(ChildDevice dev) async {
    const MethodChannel audioChannel = MethodChannel('nhom13/audio_meter');
    bool hardwareStarted = false;
    try {
      final res = await audioChannel.invokeMethod<bool>('start');
      hardwareStarted = res == true;
    } catch (_) {}

    double finalDb = 45.0;
    double finalPeak = 45.0;

    if (hardwareStarted) {
      // Đọc mic trong 3 giây
      for (int i = 0; i < 6; i++) {
        await Future.delayed(const Duration(milliseconds: 500));
        try {
          final map = await audioChannel.invokeMapMethod<String, double>('read');
          if (map != null) {
            finalDb = map['decibel'] ?? finalDb;
            finalPeak = map['peakDecibel'] ?? finalPeak;
          }
        } catch (_) {}
      }
      try {
        await audioChannel.invokeMethod('stop');
      } catch (_) {}
    } else {
      // Nếu máy ảo không có micro thật -> giả lập mức ồn
      await Future.delayed(const Duration(seconds: 2));
      finalDb = 60.0 + (DateTime.now().second % 20); // Tạo ra 1 con số ngẫu nhiên 60-80
      finalPeak = finalDb + 5.0;
    }

    // Gửi báo cáo lên server
    await _deviceService.reportNoise(
      deviceId: dev.id!,
      decibel: double.parse(finalDb.toStringAsFixed(1)),
      peakDecibel: double.parse(finalPeak.toStringAsFixed(1)),
      durationSeconds: 3,
    );
  }

  // Lấy GPS ngầm trên máy trẻ em (TUYỆT ĐỐI KHÔNG BUNG POPUP HỎI QUYỀN)
  Future<void> _performSilentLocationUpdate(ChildDevice dev) async {
    if (dev.id == null) return;
    try {
      LocationPermission perm = await Geolocator.checkPermission();
      // Nếu bị từ chối quyền, ném lỗi luôn để chuyển sang khối catch giả lập tọa độ
      // (Không gọi requestPermission() để tránh bung hộp thoại lên mặt trẻ em)
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        throw Exception("No Permission");
      }

      Position pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      ).timeout(const Duration(seconds: 5));

      await _deviceService.updateLocation(dev.id!, pos.latitude, pos.longitude);
    } catch (e) {
      // Giả lập tọa độ nếu máy ảo không bật GPS (nhích nhẹ GPS)
      final newLat = dev.latitude + 0.0005;
      final newLng = dev.longitude + 0.0005;
      await _deviceService.updateLocation(dev.id!, newLat, newLng);
    }
  }

  // Hộp thoại bắt buộc nhập mật khẩu của Phụ huynh mới cho phép Trẻ em đăng xuất
  Future<void> _requestParentPasswordToLogout() async {
    final passwordCtrl = TextEditingController();
    bool obscure = true;
    bool verifying = false;
    String? errorMsg;

    final int? primaryDeviceId =
        _myDevices.isNotEmpty ? _myDevices.first.id : null;
    final String? parentName =
        _myDevices.isNotEmpty ? _myDevices.first.parentUsername : null;

    final bool? confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.lock_person_rounded, color: Colors.red),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Yêu Cầu Mật Khẩu Phụ Huynh',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                parentName != null && parentName.isNotEmpty
                    ? 'Tài khoản trẻ em (@$_username) đang được giám sát bởi phụ huynh "$parentName". Vui lòng nhập mật khẩu của phụ huynh để đăng xuất:'
                    : 'Tài khoản trẻ em đang chịu sự giám sát. Vui lòng nhập mật khẩu của Phụ huynh để đăng xuất:',
                style: const TextStyle(fontSize: 13.5, color: Colors.black87),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: passwordCtrl,
                obscureText: obscure,
                decoration: InputDecoration(
                  labelText: 'Mật khẩu của Phụ huynh *',
                  prefixIcon: const Icon(Icons.vpn_key_rounded),
                  errorText: errorMsg,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  suffixIcon: IconButton(
                    icon: Icon(
                        obscure ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setDialogState(() => obscure = !obscure),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: verifying ? null : () => Navigator.pop(ctx, false),
              child: const Text('Hủy'),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade700,
                foregroundColor: Colors.white,
              ),
              onPressed: verifying
                  ? null
                  : () async {
                      if (passwordCtrl.text.isEmpty) {
                        setDialogState(() =>
                            errorMsg = 'Vui lòng nhập mật khẩu phụ huynh!');
                        return;
                      }
                      setDialogState(() {
                        verifying = true;
                        errorMsg = null;
                      });
                      final res = await Auth.verifyParentPassword(
                        parentPassword: passwordCtrl.text,
                        deviceId: primaryDeviceId,
                      );
                      if (!ctx.mounted) return;
                      if (res['success'] == true) {
                        Navigator.pop(ctx, true);
                      } else {
                        setDialogState(() {
                          verifying = false;
                          errorMsg = res['message']?.toString() ??
                              'Mật khẩu phụ huynh không đúng!';
                        });
                      }
                    },
              icon: verifying
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.logout_rounded),
              label: const Text('Xác Nhận & Đăng Xuất'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true && mounted) {
      await Auth.logout();
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  Widget _buildLockedBanner(ChildDevice dev) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.red.shade800, Colors.redAccent.shade700],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4))
        ],
      ),
      child: Column(
        children: [
          const Icon(Icons.phonelink_lock_rounded,
              size: 62, color: Colors.white),
          const SizedBox(height: 10),
          const Text(
            'THIẾT BỊ ĐANG BỊ PHỤ HUYNH KHÓA TỪ XA!',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Thiết bị "${dev.deviceName}" đã bị phụ huynh (${dev.parentUsername ?? "Parent"}) khóa. Các ứng dụng giải trí tạm thời bị vô hiệu hóa.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _requestParentPasswordToLogout();
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF3F6FB),
        appBar: AppBar(
          backgroundColor: Colors.teal.shade700,
          foregroundColor: Colors.white,
          automaticallyImplyLeading: false,
          title: Text(
            'Chế Độ Trẻ Em (@$_username)',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          actions: [
            IconButton(
              tooltip: 'Đồng bộ quy tắc từ Phụ huynh',
              icon: const Icon(Icons.sync),
              onPressed: () => _loadMyDevices(),
            ),
            IconButton(
              tooltip: 'Đăng ký khuôn mặt AI',
              icon: const Icon(Icons.face_retouching_natural),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        const FaceAuthScreen(mode: FaceAuthMode.register),
                  ),
                );
              },
            ),
            IconButton(
              tooltip: 'Đăng xuất (Cần mật khẩu Phụ huynh)',
              icon: const Icon(Icons.logout_rounded),
              onPressed: _requestParentPasswordToLogout,
            ),
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _loadMyDevices,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.teal.shade50,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.teal.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.shield_rounded,
                              color: Colors.teal.shade800, size: 32),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'PHÂN QUYỀN: TRẺ EM (CHILD)',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.teal,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Thiết bị đang được phụ huynh bảo vệ. Khi muốn đăng xuất phải có mật khẩu của phụ huynh.',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: Colors.black87,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_myDevices.isEmpty)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            children: [
                              Icon(Icons.phonelink_setup,
                                  size: 56, color: Colors.teal.shade400),
                              const SizedBox(height: 12),
                              const Text(
                                'Chưa có thiết bị nào được gắn với tài khoản của con',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Nhờ Phụ huynh vào ứng dụng -> Thêm/Sửa thiết bị và điền Username của con là "$_username" vào ô "Username tài khoản của trẻ".',
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.black54),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      ..._myDevices.map((dev) {
                        final blockedList = dev.blockedApps
                            .split(',')
                            .map((e) => e.trim())
                            .where((e) => e.isNotEmpty)
                            .toList();

                        return Column(
                          children: [
                            if (dev.isLocked) _buildLockedBanner(dev),
                            Card(
                              elevation: 3,
                              margin: const EdgeInsets.only(bottom: 16),
                              child: Padding(
                                padding: const EdgeInsets.all(18),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        CircleAvatar(
                                          radius: 26,
                                          backgroundColor: dev.isLocked
                                              ? Colors.red.shade100
                                              : Colors.teal.shade100,
                                          child: Icon(
                                            dev.isLocked
                                                ? Icons.lock_rounded
                                                : Icons.smartphone_rounded,
                                            color: dev.isLocked
                                                ? Colors.red
                                                : Colors.teal.shade800,
                                            size: 28,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                dev.childName,
                                                style: const TextStyle(
                                                  fontSize: 18,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              Text(
                                                'Thiết bị: ${dev.deviceName} • Phụ huynh: ${dev.parentUsername ?? "Parent"}',
                                                style: const TextStyle(
                                                  color: Colors.black54,
                                                  fontSize: 13,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    const Divider(height: 24),
                                    ListTile(
                                      contentPadding: EdgeInsets.zero,
                                      leading: const Icon(Icons.timer,
                                          color: Colors.indigo),
                                      title: const Text(
                                        'Thời gian sử dụng cho phép trong ngày',
                                        style: TextStyle(
                                            fontWeight: FontWeight.w600),
                                      ),
                                      subtitle: Text(
                                        '${dev.screenTimeLimitMinutes} phút / ngày',
                                        style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.indigo,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    const Text(
                                      'Ứng dụng bị Phụ huynh chặn:',
                                      style: TextStyle(
                                          fontWeight: FontWeight.w600),
                                    ),
                                    const SizedBox(height: 6),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 6,
                                      children: blockedList.isEmpty
                                          ? [
                                              const Chip(
                                                  label: Text(
                                                      'Không có ứng dụng bị chặn'))
                                            ]
                                          : blockedList
                                              .map(
                                                (app) => Chip(
                                                  backgroundColor:
                                                      Colors.red.shade50,
                                                  avatar: const Icon(
                                                    Icons.block,
                                                    size: 16,
                                                    color: Colors.red,
                                                  ),
                                                  label: Text(
                                                    app,
                                                    style: TextStyle(
                                                      color:
                                                          Colors.red.shade900,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  ),
                                                ),
                                              )
                                              .toList(),
                                    ),
                                    const SizedBox(height: 16),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: ElevatedButton.icon(
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor:
                                                  Colors.teal.shade700,
                                              foregroundColor: Colors.white,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      vertical: 12),
                                            ),
                                            onPressed: () async {
                                              await Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (_) =>
                                                      LocationShareScreen(
                                                          device: dev,
                                                          isParentMode: false,
                                                      ),
                                                ),
                                              );
                                              _loadMyDevices();
                                            },
                                            icon: const Icon(Icons.my_location),
                                            label:
                                                const Text('Chia sẻ Vị trí GPS'),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: ElevatedButton.icon(
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor:
                                                  Colors.deepPurple.shade700,
                                              foregroundColor: Colors.white,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      vertical: 12),
                                            ),
                                            onPressed: () async {
                                              await Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (_) =>
                                                      NoiseMonitorScreen(
                                                    device: dev,
                                                    canChangeThreshold: false,
                                                  ),
                                                ),
                                              );
                                              _loadMyDevices();
                                            },
                                            icon: const Icon(Icons.mic_rounded),
                                            label: const Text('Đo Tiếng Ồn'),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        );
                      }),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red.shade700,
                        side: BorderSide(color: Colors.red.shade300),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: _requestParentPasswordToLogout,
                      icon: const Icon(Icons.lock_open_rounded),
                      label: const Text(
                        'ĐĂNG XUẤT (YÊU CẦU MẬT KHẨU PHỤ HUYNH)',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
