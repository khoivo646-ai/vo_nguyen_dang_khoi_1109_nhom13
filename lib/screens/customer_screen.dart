import 'package:flutter/material.dart';
import '../models/child_device.dart';
import '../services/device_service.dart';
import '../utils/auth.dart';
import 'face_auth_screen.dart';
import 'location_share_screen.dart';
import 'login_screen.dart';
import 'noise_monitor_screen.dart';

class CustomerScreen extends StatefulWidget {
  final String dashboardTitle;
  final String roleBadge;
  final Color primaryColor;
  final bool isAdminView;

  const CustomerScreen({
    super.key,
    this.dashboardTitle = 'Phụ Huynh - Quản Lý Thiết Bị Trẻ Em',
    this.roleBadge = 'PHỤ HUYNH (PARENT)',
    this.primaryColor = Colors.indigo,
    this.isAdminView = false,
  });

  @override
  State<CustomerScreen> createState() => _CustomerScreenState();
}

class _CustomerScreenState extends State<CustomerScreen> {
  final DeviceService _deviceService = DeviceService();
  final TextEditingController _searchController = TextEditingController();

  List<ChildDevice> _devices = [];
  List<NoiseAlertItem> _noiseAlerts = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchDevices();
  }

  Future<void> _fetchDevices({String? searchQuery}) async {
    setState(() => _isLoading = true);
    try {
      final alertsFuture = _deviceService.getUnacknowledgedAlerts();
      if (searchQuery != null && int.tryParse(searchQuery.trim()) != null) {
        int id = int.parse(searchQuery.trim());
        final single = await _deviceService.getDeviceById(id);
        final alerts = await alertsFuture;
        if (!mounted) return;
        setState(() {
          _devices = single != null ? [single] : [];
          _noiseAlerts = alerts;
        });
      } else {
        final list = await _deviceService.getDevices(search: searchQuery);
        final alerts = await alertsFuture;
        if (!mounted) return;
        setState(() {
          _devices = list;
          _noiseAlerts = alerts;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Không thể tải dữ liệu: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Hộp thoại Thêm Mới hoặc Cập Nhật Thiết bị (CRUD)
  void _openDeviceFormDialog({ChildDevice? existingDevice}) {
    final childNameCtrl =
        TextEditingController(text: existingDevice?.childName ?? '');
    final deviceNameCtrl =
        TextEditingController(text: existingDevice?.deviceName ?? '');
    final childUserCtrl =
        TextEditingController(text: existingDevice?.childUsername ?? '');
    final limitCtrl = TextEditingController(
      text: (existingDevice?.screenTimeLimitMinutes ?? 120).toString(),
    );
    final blockedCtrl = TextEditingController(
      text: existingDevice?.blockedApps ?? 'TikTok, Roblox, FreeFire',
    );
    final thresholdCtrl = TextEditingController(
      text: (existingDevice?.noiseThresholdDb ?? 80).toStringAsFixed(0),
    );
    bool isLocked = existingDevice?.isLocked ?? false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(
            existingDevice == null
                ? 'Thêm Thiết Bị Trẻ Em'
                : 'Cập Nhật Thiết Bị #${existingDevice.id}',
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: childNameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Họ và tên trẻ em *',
                    prefixIcon: Icon(Icons.child_care),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: deviceNameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Tên điện thoại / Máy tính bảng *',
                    prefixIcon: Icon(Icons.phone_iphone),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: childUserCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Username tài khoản của trẻ (Role Child)',
                    hintText: 'Để trống nếu chưa gán tài khoản',
                    prefixIcon: Icon(Icons.account_circle_outlined),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: limitCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Giới hạn màn hình (phút/ngày)',
                    prefixIcon: Icon(Icons.timer),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: blockedCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Danh sách App bị chặn',
                    prefixIcon: Icon(Icons.block),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: thresholdCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Ngưỡng cảnh báo tiếng ồn (dB)',
                    prefixIcon: Icon(Icons.graphic_eq),
                  ),
                ),
                const SizedBox(height: 10),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Khóa máy từ xa ngay lập tức'),
                  value: isLocked,
                  activeThumbColor: Colors.red,
                  onChanged: (val) => setDialogState(() => isLocked = val),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Hủy'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: widget.primaryColor),
              onPressed: () async {
                if (childNameCtrl.text.trim().isEmpty ||
                    deviceNameCtrl.text.trim().isEmpty) {
                  return;
                }
                final deviceModel = ChildDevice(
                  id: existingDevice?.id,
                  childName: childNameCtrl.text.trim(),
                  deviceName: deviceNameCtrl.text.trim(),
                  childUsername: childUserCtrl.text.trim().isEmpty
                      ? null
                      : childUserCtrl.text.trim(),
                  screenTimeLimitMinutes: int.tryParse(limitCtrl.text) ?? 120,
                  blockedApps: blockedCtrl.text.trim(),
                  isLocked: isLocked,
                  latitude: existingDevice?.latitude ?? 10.8018,
                  longitude: existingDevice?.longitude ?? 106.7144,
                  parentUsername: existingDevice?.parentUsername,
                  noiseThresholdDb:
                      double.tryParse(thresholdCtrl.text) ?? 80.0,
                );

                Navigator.pop(ctx);
                final res = existingDevice == null
                    ? await _deviceService.addDevice(deviceModel)
                    : await _deviceService.updateDevice(deviceModel);

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(res['message'] ?? ''),
                      backgroundColor:
                          res['success'] == true ? Colors.green : Colors.red,
                    ),
                  );
                }
                _fetchDevices();
              },
              child: const Text(
                'Lưu Thiết Bị',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Đảo trạng thái Khóa / Mở khóa nhanh 1 chạm
  Future<void> _toggleQuickLock(ChildDevice dev) async {
    final updated = ChildDevice(
      id: dev.id,
      childName: dev.childName,
      deviceName: dev.deviceName,
      screenTimeLimitMinutes: dev.screenTimeLimitMinutes,
      blockedApps: dev.blockedApps,
      isLocked: !dev.isLocked,
      latitude: dev.latitude,
      longitude: dev.longitude,
      parentUsername: dev.parentUsername,
      childUsername: dev.childUsername,
      noiseThresholdDb: dev.noiseThresholdDb,
    );
    await _deviceService.updateDevice(updated);
    _fetchDevices(searchQuery: _searchController.text);
  }

  void _openNoiseAlertsSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.campaign_rounded, color: Colors.red.shade700),
                const SizedBox(width: 8),
                Text(
                  'Cảnh báo tiếng ồn chưa xem (${_noiseAlerts.length})',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const Divider(),
            if (_noiseAlerts.isEmpty)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Center(
                  child: Text('Không có cảnh báo tiếng ồn mới.'),
                ),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _noiseAlerts.length,
                  itemBuilder: (_, idx) {
                    final a = _noiseAlerts[idx];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.red.shade100,
                        child: Icon(Icons.volume_up, color: Colors.red.shade800),
                      ),
                      title: Text(
                        '${a.childName} (${a.deviceName}) - ${a.decibel.toStringAsFixed(0)} dB',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        'Ngưỡng ${a.thresholdDb.toStringAsFixed(0)} dB • ${a.measuredAt.toLocal().toString().substring(0, 19)}',
                      ),
                      trailing: TextButton(
                        onPressed: () async {
                          await _deviceService.acknowledgeNoiseAlert(a.id);
                          if (ctx.mounted) Navigator.pop(ctx);
                          _fetchDevices();
                        },
                        child: const Text('Đã xem'),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    return Column(
      children: [
        // Header thống kê nhanh & Tìm kiếm
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          decoration: BoxDecoration(
            color: widget.primaryColor,
            borderRadius:
                const BorderRadius.vertical(bottom: Radius.circular(24)),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'PHÂN QUYỀN: ${widget.roleBadge}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'Tổng số máy: ${_devices.length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              if (_noiseAlerts.isNotEmpty) ...[
                const SizedBox(height: 10),
                InkWell(
                  onTap: _openNoiseAlertsSheet,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.red.shade600,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.warning_amber_rounded,
                            color: Colors.white),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Có ${_noiseAlerts.length} cảnh báo tiếng ồn (trẻ la hét) mới! Bấm để xem.',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _searchController,
                onSubmitted: (val) => _fetchDevices(searchQuery: val),
                decoration: InputDecoration(
                  hintText: 'Tìm theo tên trẻ, tên máy hoặc nhập ID...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _searchController.clear();
                      _fetchDevices();
                    },
                  ),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ],
          ),
        ),
        // Danh sách thiết bị CRUD
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _devices.isEmpty
                  ? const Center(
                      child: Text('Chưa có thiết bị trẻ em nào được thêm.'),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(14, 14, 14, 80),
                      itemCount: _devices.length,
                      itemBuilder: (context, index) {
                        final dev = _devices[index];
                        final bool isLoud = dev.lastNoiseDb != null &&
                            dev.lastNoiseDb! >= dev.noiseThresholdDb;

                        return Card(
                          elevation: 3,
                          margin: const EdgeInsets.only(bottom: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 24,
                                      backgroundColor: dev.isLocked
                                          ? Colors.red.shade100
                                          : Colors.green.shade100,
                                      child: Icon(
                                        dev.isLocked
                                            ? Icons.lock_clock
                                            : Icons.phone_android,
                                        color: dev.isLocked
                                            ? Colors.red
                                            : Colors.green.shade700,
                                        size: 26,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '${dev.childName} (ID: #${dev.id})',
                                            style: const TextStyle(
                                              fontSize: 16.5,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          Text(
                                            'Thiết bị: ${dev.deviceName}${dev.childUsername != null && dev.childUsername!.isNotEmpty ? " • TK trẻ: @${dev.childUsername}" : ""}',
                                            style: const TextStyle(
                                              color: Colors.black54,
                                              fontSize: 12.8,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    ActionChip(
                                      backgroundColor: dev.isLocked
                                          ? Colors.red.shade50
                                          : Colors.green.shade50,
                                      avatar: Icon(
                                        dev.isLocked
                                            ? Icons.lock
                                            : Icons.lock_open,
                                        size: 16,
                                        color: dev.isLocked
                                            ? Colors.red
                                            : Colors.green,
                                      ),
                                      label: Text(
                                        dev.isLocked ? 'Đang khóa' : 'Đang mở',
                                        style: TextStyle(
                                          color: dev.isLocked
                                              ? Colors.red
                                              : Colors.green.shade800,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                        ),
                                      ),
                                      onPressed: () => _toggleQuickLock(dev),
                                    ),
                                  ],
                                ),
                                const Divider(height: 22),
                                Row(
                                  children: [
                                    const Icon(Icons.timer_outlined,
                                        size: 18, color: Colors.indigo),
                                    const SizedBox(width: 6),
                                    Text(
                                        'Giới hạn ngày: ${dev.screenTimeLimitMinutes} phút'),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    const Icon(Icons.block,
                                        size: 18, color: Colors.redAccent),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                          'App bị chặn: ${dev.blockedApps}'),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    Icon(
                                      Icons.graphic_eq,
                                      size: 18,
                                      color: isLoud
                                          ? Colors.red.shade700
                                          : Colors.deepPurple,
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        dev.lastNoiseDb != null
                                            ? 'Tiếng ồn gần nhất: ${dev.lastNoiseDb!.toStringAsFixed(1)} dB (Ngưỡng: ${dev.noiseThresholdDb.toStringAsFixed(0)} dB)'
                                            : 'Ngưỡng cảnh báo tiếng ồn: ${dev.noiseThresholdDb.toStringAsFixed(0)} dB',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: isLoud
                                              ? FontWeight.bold
                                              : FontWeight.normal,
                                          color: isLoud
                                              ? Colors.red.shade700
                                              : Colors.black87,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    const Icon(Icons.pin_drop_outlined,
                                        size: 18, color: Colors.teal),
                                    const SizedBox(width: 6),
                                    Text(
                                      'GPS: ${dev.latitude.toStringAsFixed(4)}, ${dev.longitude.toStringAsFixed(4)}',
                                      style: const TextStyle(
                                        fontSize: 12.5,
                                        color: Colors.black54,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  alignment: WrapAlignment.end,
                                  children: [
                                    FilledButton.tonalIcon(
                                      onPressed: () async {
                                        await Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                LocationShareScreen(
                                                    device: dev,
                                                    isParentMode: true,
                                                ),
                                          ),
                                        );
                                        _fetchDevices();
                                      },
                                      icon: const Icon(Icons.map_outlined,
                                          size: 18),
                                      label: const Text('Vị trí GPS'),
                                    ),
                                    FilledButton.tonalIcon(
                                      style: FilledButton.styleFrom(
                                        backgroundColor:
                                            Colors.deepPurple.shade50,
                                        foregroundColor:
                                            Colors.deepPurple.shade800,
                                      ),
                                      onPressed: () async {
                                        await Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => NoiseMonitorScreen(
                                              device: dev,
                                              canChangeThreshold: true,
                                            ),
                                          ),
                                        );
                                        _fetchDevices();
                                      },
                                      icon: const Icon(Icons.graphic_eq,
                                          size: 18),
                                      label: const Text('Đo tiếng ồn'),
                                    ),
                                    IconButton(
                                      tooltip: 'Sửa thiết bị',
                                      icon: const Icon(Icons.edit_note,
                                          color: Colors.blue, size: 26),
                                      onPressed: () => _openDeviceFormDialog(
                                          existingDevice: dev),
                                    ),
                                    IconButton(
                                      tooltip: 'Xóa thiết bị',
                                      icon: const Icon(Icons.delete_outline,
                                          color: Colors.red, size: 24),
                                      onPressed: () async {
                                        await _deviceService
                                            .deleteDevice(dev.id!);
                                        _fetchDevices();
                                      },
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isAdminView) {
      return Scaffold(
        backgroundColor: const Color(0xFFF3F6FB),
        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: widget.primaryColor,
          onPressed: () => _openDeviceFormDialog(),
          icon: const Icon(Icons.add_circle_outline, color: Colors.white),
          label: const Text(
            'Thêm Thiết Bị',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
        body: _buildContent(),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF3F6FB),
      appBar: AppBar(
        backgroundColor: widget.primaryColor,
        foregroundColor: Colors.white,
        title: Text(
          widget.dashboardTitle,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            tooltip: 'Đăng ký Khuôn mặt AI (ArcFace)',
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
            tooltip: 'Đăng xuất',
            icon: const Icon(Icons.logout_rounded),
            onPressed: () async {
              final nav = Navigator.of(context);
              await Auth.logout();
              nav.pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
                (route) => false,
              );
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: widget.primaryColor,
        onPressed: () => _openDeviceFormDialog(),
        icon: const Icon(Icons.add_circle_outline, color: Colors.white),
        label: const Text(
          'Thêm Thiết Bị',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: _buildContent(),
    );
  }
}
