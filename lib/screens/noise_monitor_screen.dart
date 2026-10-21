import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/child_device.dart';
import '../services/device_service.dart';

/// Màn hình Đo tiếng ồn khi trẻ la hét & Xem lịch sử cảnh báo:
/// - Trên thiết bị Android thật: đọc biên độ micro thời gian thực qua MethodChannel ("nhom13/audio_meter")
///   sử dụng android.media.AudioRecord.
/// - Có thanh trượt/nút mô phỏng tiếng la hét (>= ngưỡng dB) để kiểm thử nhanh trên máy ảo không có micro.
/// - Cho phép Phụ huynh đổi ngưỡng cảnh báo (dB) và xem lịch sử các lần vượt ngưỡng.
class NoiseMonitorScreen extends StatefulWidget {
  final ChildDevice device;
  final bool canChangeThreshold;

  const NoiseMonitorScreen({
    super.key,
    required this.device,
    this.canChangeThreshold = true,
  });

  @override
  State<NoiseMonitorScreen> createState() => _NoiseMonitorScreenState();
}

class _NoiseMonitorScreenState extends State<NoiseMonitorScreen> {
  static const MethodChannel _audioChannel = MethodChannel('nhom13/audio_meter');

  final DeviceService _deviceService = DeviceService();
  final Random _rng = Random();

  late double _thresholdDb;
  double _currentDb = 42.0;
  double _peakDb = 45.0;
  bool _isMonitoringMic = false;
  bool _usingHardwareMic = false;
  bool _isSending = false;
  bool _isLoadingHistory = true;
  bool _isRequestingRemote = false;

  Timer? _meterTimer;
  Timer? _remotePollTimer;
  int _loudStreakSeconds = 0;

  List<NoiseEventItem> _events = [];

  int _alertCount = 0;
  double? _avgDb;
  double? _maxDb;

  @override
  void initState() {
    super.initState();
    _thresholdDb = widget.device.noiseThresholdDb;
    if (widget.device.lastNoiseDb != null) {
      _currentDb = widget.device.lastNoiseDb!;
      _peakDb = _currentDb;
    }
    _loadHistory();
  }

  @override
  void dispose() {
    _stopMicMonitoring();
    _remotePollTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    if (widget.device.id == null) return;
    setState(() => _isLoadingHistory = true);
    try {
      final data = await _deviceService.getNoiseHistory(widget.device.id!);
      if (!mounted) return;
      setState(() {
        _thresholdDb = (data['thresholdDb'] as double?) ?? _thresholdDb;
        _events = (data['events'] as List<NoiseEventItem>);
        _alertCount = (data['alertCount'] as int?) ?? 0;
        _avgDb = data['averageDb'] as double?;
        _maxDb = data['maxDb'] as double?;
      });
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isLoadingHistory = false);
    }
  }

  Future<void> _startMicMonitoring() async {
    bool hardwareStarted = false;
    try {
      final res = await _audioChannel.invokeMethod<bool>('start');
      hardwareStarted = res == true;
    } catch (_) {
      hardwareStarted = false;
    }

    setState(() {
      _isMonitoringMic = true;
      _usingHardwareMic = hardwareStarted;
      _loudStreakSeconds = 0;
    });

    _meterTimer?.cancel();
    _meterTimer = Timer.periodic(const Duration(milliseconds: 500), (_) async {
      double db = _currentDb;
      double peak = _peakDb;

      if (_usingHardwareMic) {
        try {
          final map = await _audioChannel.invokeMapMethod<String, double>('read');
          if (map != null) {
            db = map['decibel'] ?? db;
            peak = map['peakDecibel'] ?? db;
          }
        } catch (_) {}
      } else {
        // Nếu máy ảo chưa cấp quyền micro, dao động nhẹ quanh giá trị thanh trượt
        db = (_currentDb + (_rng.nextDouble() * 4 - 2)).clamp(30.0, 120.0);
        peak = max(db, _peakDb);
      }

      if (!mounted) return;
      setState(() {
        _currentDb = db;
        _peakDb = max(db, peak);
      });

      // Nếu vượt ngưỡng liên tiếp ~2 giây thì tự động đẩy cảnh báo lên Server
      if (db >= _thresholdDb) {
        _loudStreakSeconds++;
        if (_loudStreakSeconds >= 4 && !_isSending) {
          _loudStreakSeconds = 0;
          await _sendReadingToServer(
            decibel: db,
            peakDecibel: _peakDb,
            durationSeconds: 2,
          );
        }
      } else {
        _loudStreakSeconds = 0;
      }
    });
  }

  Future<void> _stopMicMonitoring() async {
    _meterTimer?.cancel();
    _meterTimer = null;
    if (_usingHardwareMic) {
      try {
        await _audioChannel.invokeMethod('stop');
      } catch (_) {}
    }
    if (mounted) {
      setState(() {
        _isMonitoringMic = false;
        _usingHardwareMic = false;
      });
    }
  }

  Future<void> _sendReadingToServer({
    required double decibel,
    double? peakDecibel,
    int durationSeconds = 3,
  }) async {
    if (widget.device.id == null) return;
    setState(() => _isSending = true);
    final res = await _deviceService.reportNoise(
      deviceId: widget.device.id!,
      decibel: double.parse(decibel.toStringAsFixed(1)),
      peakDecibel:
          double.parse((peakDecibel ?? decibel).toStringAsFixed(1)),
      durationSeconds: durationSeconds,
    );
    if (!mounted) return;
    setState(() => _isSending = false);

    final isAlert = res['isAlert'] == true;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(res['message'] ?? ''),
        backgroundColor: isAlert ? Colors.red.shade700 : Colors.teal.shade700,
      ),
    );
    _loadHistory();
  }

  Future<void> _requestRemoteNoiseMeasurement() async {
    if (widget.device.id == null) return;
    setState(() => _isRequestingRemote = true);

    // 1. Thêm cờ vào BlockedApps để ra lệnh cho máy trẻ em (nếu chưa có)
    ChildDevice dev = await _deviceService.getDeviceById(widget.device.id!) ?? widget.device;
    if (!dev.blockedApps.contains('[REQ_NOISE]')) {
      final oldApps = dev.blockedApps.isNotEmpty ? '${dev.blockedApps},' : '';
      
      final updatedDev = ChildDevice(
         id: dev.id,
         childName: dev.childName,
         deviceName: dev.deviceName,
         childUsername: dev.childUsername,
         screenTimeLimitMinutes: dev.screenTimeLimitMinutes,
         blockedApps: '$oldApps[REQ_NOISE]',
         isLocked: dev.isLocked,
         latitude: dev.latitude,
         longitude: dev.longitude,
         parentUsername: dev.parentUsername,
         noiseThresholdDb: dev.noiseThresholdDb,
      );
      await _deviceService.updateDevice(updatedDev);
    }

    // 2. Poll server mỗi 3 giây để chờ kết quả trả về từ máy trẻ em
    int attempts = 0;
    _remotePollTimer?.cancel();
    _remotePollTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      attempts++;
      if (attempts > 12) {
        // Hết thời gian chờ (36s)
        timer.cancel();
        if (mounted) {
          setState(() => _isRequestingRemote = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Máy trẻ em không phản hồi (có thể đang tắt hoặc không mở app).'), backgroundColor: Colors.red),
          );
        }
        return;
      }

      ChildDevice? updatedDev = await _deviceService.getDeviceById(widget.device.id!);
      if (updatedDev != null && !updatedDev.blockedApps.contains('[REQ_NOISE]')) {
        // Trẻ em đã nhận lệnh và phản hồi (xóa cờ [REQ_NOISE])
        await Future.delayed(const Duration(seconds: 2)); // Đợi DB lưu xong logs
        await _loadHistory();
        timer.cancel();
        if (mounted) {
          setState(() {
            _isRequestingRemote = false;
            _currentDb = updatedDev.lastNoiseDb ?? _currentDb;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Đã nhận được kết quả đo tiếng ồn từ máy của Trẻ!'), backgroundColor: Colors.green),
          );
        }
      }
    });
  }

  Future<void> _saveThreshold(double newThreshold) async {
    if (widget.device.id == null) return;
    final ok = await _deviceService.updateNoiseThreshold(
      widget.device.id!,
      newThreshold,
    );
    if (!mounted) return;
    if (ok) {
      setState(() => _thresholdDb = newThreshold);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Đã lưu ngưỡng cảnh báo tiếng ồn: ${newThreshold.toStringAsFixed(0)} dB',
          ),
          backgroundColor: Colors.indigo,
        ),
      );
    }
  }

  Color _dbColor(double db) {
    if (db >= _thresholdDb) return Colors.red.shade700;
    if (db >= _thresholdDb - 10) return Colors.orange.shade700;
    return Colors.green.shade700;
  }

  String _dbLabel(double db) {
    if (db >= _thresholdDb) return 'CẢNH BÁO: TRẺ LA HÉT / QUÁ ỒN!';
    if (db >= 65) return 'Môi trường hơi ồn';
    return 'Bình thường / Yên tĩnh';
  }

  @override
  Widget build(BuildContext context) {
    final color = _dbColor(_currentDb);

    return Scaffold(
      backgroundColor: const Color(0xFFF3F6FB),
      appBar: AppBar(
        backgroundColor: Colors.deepPurple.shade700,
        foregroundColor: Colors.white,
        title: Text('Đo Tiếng Ồn: ${widget.device.childName}'),
        actions: [
          IconButton(
            tooltip: 'Tải lại lịch sử',
            onPressed: _loadHistory,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Đồng hồ đo dB trực quan
          Card(
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Chip(
                        avatar: Icon(
                          _usingHardwareMic ? Icons.mic : Icons.tune,
                          size: 18,
                          color: Colors.deepPurple,
                        ),
                        label: Text(
                          _isMonitoringMic
                              ? (_usingHardwareMic
                                  ? 'Micro thật đang đo'
                                  : 'Đang đo (Chế độ mô phỏng)')
                              : 'Đang tạm dừng micro',
                        ),
                      ),
                      Chip(
                        backgroundColor: Colors.red.shade50,
                        label: Text(
                          'Ngưỡng: ${_thresholdDb.toStringAsFixed(0)} dB',
                          style: TextStyle(
                            color: Colors.red.shade800,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    width: 170,
                    height: 170,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color.withValues(alpha: 0.1),
                      border: Border.all(color: color, width: 6),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _currentDb >= _thresholdDb
                              ? Icons.warning_amber_rounded
                              : Icons.graphic_eq_rounded,
                          color: color,
                          size: 36,
                        ),
                        Text(
                          _currentDb.toStringAsFixed(1),
                          style: TextStyle(
                            fontSize: 38,
                            fontWeight: FontWeight.w900,
                            color: color,
                          ),
                        ),
                        Text(
                          'dB SPL',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: color,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _dbLabel(_currentDb),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: LinearProgressIndicator(
                      value: (_currentDb / 120.0).clamp(0.0, 1.0),
                      minHeight: 12,
                      backgroundColor: Colors.grey.shade200,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 14),
                  
                  if (widget.canChangeThreshold) ...[
                    // Giao diện của Phụ huynh: Yêu cầu đo từ xa
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _isRequestingRemote ? null : _requestRemoteNoiseMeasurement,
                        icon: _isRequestingRemote 
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : const Icon(Icons.settings_remote_rounded),
                        label: Text(_isRequestingRemote ? 'Đang gửi lệnh & chờ phản hồi...' : 'YÊU CẦU MÁY CỦA TRẺ ĐO NGAY LẬP TỨC'),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.deepPurple.shade700,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Lệnh sẽ được gửi ngầm. Yêu cầu thiết bị của Trẻ đang có kết nối mạng và mở ứng dụng để thực hiện việc đo tiếng ồn.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ] else ...[
                    // Giao diện của Trẻ em: Đo thủ công tại chỗ
                    Row(
                      children: [
                        const Text('30 dB', style: TextStyle(fontSize: 12)),
                        Expanded(
                          child: Slider(
                            value: _currentDb.clamp(30.0, 120.0),
                            min: 30,
                            max: 120,
                            divisions: 90,
                            label: '${_currentDb.toStringAsFixed(0)} dB',
                            activeColor: color,
                            onChanged: (v) {
                              setState(() {
                                _currentDb = v;
                                _peakDb = max(_peakDb, v);
                              });
                            },
                          ),
                        ),
                        const Text('120 dB', style: TextStyle(fontSize: 12)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _isMonitoringMic
                                ? _stopMicMonitoring
                                : _startMicMonitoring,
                            icon: Icon(
                                _isMonitoringMic ? Icons.stop : Icons.mic_rounded),
                            label: Text(
                              _isMonitoringMic ? 'Dừng Micro' : 'Bắt đầu đo Micro',
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _isSending
                                ? null
                                : () => _sendReadingToServer(
                                      decibel: _currentDb,
                                      peakDecibel: max(_currentDb + 3, _peakDb),
                                      durationSeconds: 3,
                                    ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.deepPurple.shade700,
                              foregroundColor: Colors.white,
                            ),
                            icon: const Icon(Icons.cloud_upload_outlined),
                            label: Text(
                              _isSending ? 'Đang gửi...' : 'Gửi mẫu dB này',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.tonalIcon(
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.red.shade50,
                          foregroundColor: Colors.red.shade800,
                        ),
                        onPressed: _isSending
                            ? null
                            : () {
                                final screamDb = max(_thresholdDb + 14, 94.0);
                                setState(() {
                                  _currentDb = screamDb;
                                  _peakDb = screamDb + 4;
                                });
                                _sendReadingToServer(
                                  decibel: screamDb,
                                  peakDecibel: screamDb + 4,
                                  durationSeconds: 5,
                                );
                              },
                        icon: const Icon(Icons.campaign_rounded),
                        label: const Text(
                          'Mô phỏng Trẻ La Hét (Vượt ngưỡng -> Báo động Phụ huynh)',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // Cài đặt ngưỡng cảnh báo (chỉ dành cho Phụ huynh / Admin)
          if (widget.canChangeThreshold) ...[
            const SizedBox(height: 14),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Cấu hình ngưỡng cảnh báo tiếng ồn (Phụ huynh)',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Khi thiết bị của trẻ ghi nhận âm thanh >= ${_thresholdDb.toStringAsFixed(0)} dB, hệ thống sẽ tạo cảnh báo và gửi email cho phụ huynh.',
                      style:
                          const TextStyle(fontSize: 12.5, color: Colors.black54),
                    ),
                    Slider(
                      value: _thresholdDb.clamp(40.0, 110.0),
                      min: 40,
                      max: 110,
                      divisions: 14,
                      label: '${_thresholdDb.toStringAsFixed(0)} dB',
                      onChanged: (v) => setState(() => _thresholdDb = v),
                      onChangeEnd: _saveThreshold,
                    ),
                  ],
                ),
              ),
            ),
          ],

          // Thống kê & Lịch sử đo
          const SizedBox(height: 14),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.history, color: Colors.deepPurple),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Lịch Sử Đo & Cảnh Báo Tiếng Ồn',
                          style: TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Text(
                        'Cảnh báo: $_alertCount/${_events.length}',
                        style: TextStyle(
                          color: Colors.red.shade700,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  if (_avgDb != null || _maxDb != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Trung bình: ${_avgDb?.toStringAsFixed(1) ?? "-"} dB  |  Đỉnh cao nhất: ${_maxDb?.toStringAsFixed(1) ?? "-"} dB',
                      style:
                          const TextStyle(fontSize: 12.5, color: Colors.black54),
                    ),
                  ],
                  const Divider(height: 20),
                  if (_isLoadingHistory)
                    const Padding(
                      padding: EdgeInsets.all(20),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_events.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(
                        child: Text('Chưa có dữ liệu tiếng ồn nào.'),
                      ),
                    )
                  else
                    ..._events.take(20).map(
                          (e) => ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: CircleAvatar(
                              backgroundColor: e.isAlert
                                  ? Colors.red.shade100
                                  : Colors.green.shade100,
                              child: Icon(
                                e.isAlert
                                    ? Icons.notifications_active
                                    : Icons.volume_down,
                                color: e.isAlert
                                    ? Colors.red.shade800
                                    : Colors.green.shade800,
                                size: 20,
                              ),
                            ),
                            title: Text(
                              '${e.decibel.toStringAsFixed(1)} dB ${e.isAlert ? "(VƯỢT NGƯỠNG ${e.thresholdDb.toStringAsFixed(0)} dB)" : "(Bình thường)"}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: e.isAlert
                                    ? Colors.red.shade800
                                    : Colors.black87,
                              ),
                            ),
                            subtitle: Text(
                              'Thời lượng: ${e.durationSeconds}s • ${e.measuredAt.toLocal().toString().substring(0, 19)}',
                            ),
                          ),
                        ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
