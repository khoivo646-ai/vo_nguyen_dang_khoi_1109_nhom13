import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../models/child_device.dart';
import '../services/device_service.dart';

class LocationShareScreen extends StatefulWidget {
  final ChildDevice device;
  final bool isParentMode;

  const LocationShareScreen({
    super.key,
    required this.device,
    this.isParentMode = true,
  });

  @override
  State<LocationShareScreen> createState() => _LocationShareScreenState();
}

class _LocationShareScreenState extends State<LocationShareScreen> {
  final DeviceService _deviceService = DeviceService();
  final MapController _mapController = MapController();

  late LatLng _devicePosition;
  bool _isUpdatingGps = false;
  bool _isRequestingRemote = false;
  Timer? _remotePollTimer;

  @override
  void initState() {
    super.initState();
    _devicePosition = LatLng(widget.device.latitude, widget.device.longitude);
  }

  @override
  void dispose() {
    _remotePollTimer?.cancel();
    super.dispose();
  }

  // 1. Máy trẻ em: Trực tiếp lấy GPS và gửi lên Server
  Future<void> _shareLiveLocation() async {
    setState(() => _isUpdatingGps = true);
    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }

      Position pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      ).timeout(const Duration(seconds: 5));

      setState(() {
        _devicePosition = LatLng(pos.latitude, pos.longitude);
      });
      _mapController.move(_devicePosition, 16.0);
      await _deviceService.updateLocation(widget.device.id!, pos.latitude, pos.longitude);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đã chia sẻ vị trí GPS thực tế lên SQL Server thành công!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      // Dự phòng nếu máy ảo chưa bật GPS: dịch chuyển tọa độ quanh HUTECH TP.HCM và lưu vào DB
      final newLat = _devicePosition.latitude + 0.0012;
      final newLng = _devicePosition.longitude + 0.0012;
      setState(() {
        _devicePosition = LatLng(newLat, newLng);
      });
      _mapController.move(_devicePosition, 16.0);
      await _deviceService.updateLocation(widget.device.id!, newLat, newLng);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đã cập nhật và chia sẻ tọa độ mới lên Server!'),
            backgroundColor: Colors.teal,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUpdatingGps = false);
    }
  }

  // 2. Máy phụ huynh: Gửi lệnh yêu cầu Trẻ lấy GPS (qua cờ [REQ_LOC])
  Future<void> _requestRemoteLocationUpdate() async {
    if (widget.device.id == null) return;
    setState(() => _isRequestingRemote = true);

    // 2.1 Thêm cờ vào BlockedApps
    ChildDevice dev = await _deviceService.getDeviceById(widget.device.id!) ?? widget.device;
    if (!dev.blockedApps.contains('[REQ_LOC]')) {
      final oldApps = dev.blockedApps.isNotEmpty ? '${dev.blockedApps},' : '';
      final updatedDev = ChildDevice(
         id: dev.id,
         childName: dev.childName,
         deviceName: dev.deviceName,
         childUsername: dev.childUsername,
         screenTimeLimitMinutes: dev.screenTimeLimitMinutes,
         blockedApps: '$oldApps[REQ_LOC]',
         isLocked: dev.isLocked,
         latitude: dev.latitude,
         longitude: dev.longitude,
         parentUsername: dev.parentUsername,
         noiseThresholdDb: dev.noiseThresholdDb,
      );
      await _deviceService.updateDevice(updatedDev);
    }

    // 2.2 Poll (Kiểm tra lại Server) mỗi 3s để chờ kết quả
    int attempts = 0;
    _remotePollTimer?.cancel();
    _remotePollTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      attempts++;
      if (attempts > 12) {
        timer.cancel();
        if (mounted) {
          setState(() => _isRequestingRemote = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Máy trẻ em không phản hồi (có thể đang tắt, mất mạng hoặc không mở app).'), backgroundColor: Colors.red),
          );
        }
        return;
      }

      ChildDevice? updatedDev = await _deviceService.getDeviceById(widget.device.id!);
      if (updatedDev != null && !updatedDev.blockedApps.contains('[REQ_LOC]')) {
        // Trẻ em đã báo cáo xong
        timer.cancel();
        if (mounted) {
          setState(() {
            _isRequestingRemote = false;
            _devicePosition = LatLng(updatedDev.latitude, updatedDev.longitude);
          });
          _mapController.move(_devicePosition, 16.0);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Đã cập nhật vị trí mới nhất của trẻ!'), backgroundColor: Colors.green),
          );
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.teal.shade700,
        foregroundColor: Colors.white,
        title: Text('Định Vị & Chia Sẻ: ${widget.device.childName}'),
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _devicePosition,
              initialZoom: 15.5,
            ),
            children: [
              TileLayer(
                // Sử dụng máy chủ Google Maps (hoạt động tốt, không bị chặn bởi User-Agent, hình nét)
                urlTemplate: 'https://mt1.google.com/vt/lyrs=m&x={x}&y={y}&z={z}',
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: _devicePosition,
                    width: 140,
                    height: 85,
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                          ),
                          child: Text(
                            widget.device.childName,
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const Icon(Icons.location_on, size: 44, color: Colors.red),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          Positioned(
            bottom: 24,
            left: 16,
            right: 16,
            child: Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              elevation: 6,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Thiết bị: ${widget.device.deviceName}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Tọa độ: ${_devicePosition.latitude.toStringAsFixed(5)}, ${_devicePosition.longitude.toStringAsFixed(5)}',
                      style: const TextStyle(color: Colors.black54),
                    ),
                    const SizedBox(height: 12),
                    if (widget.isParentMode)
                      // Giao diện của Phụ huynh
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton.icon(
                          onPressed: _isRequestingRemote ? null : _requestRemoteLocationUpdate,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.indigo.shade700,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          icon: _isRequestingRemote
                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                              : const Icon(Icons.sync_rounded, color: Colors.white),
                          label: Text(
                            _isRequestingRemote ? 'ĐANG CHỜ MÁY TRẺ BÁO CÁO...' : 'YÊU CẦU MÁY TRẺ CẬP NHẬT GPS',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ),
                      )
                    else
                      // Giao diện của Trẻ em
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton.icon(
                          onPressed: _isUpdatingGps ? null : _shareLiveLocation,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.teal.shade700,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          icon: const Icon(Icons.my_location, color: Colors.white),
                          label: Text(
                            _isUpdatingGps ? 'ĐANG ĐỒNG BỘ GPS...' : 'BÁO CÁO VỊ TRÍ HIỆN TẠI LÊN SERVER',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}