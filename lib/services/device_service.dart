import 'dart:convert';
import '../models/child_device.dart';
import 'api_client.dart';

class DeviceService {
  final ApiClient _apiClient = ApiClient();

  String _extractError(String body, int statusCode) {
    if (body.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(body);
        if (decoded is Map && decoded['message'] != null) {
          return decoded['message'].toString();
        }
      } catch (_) {}
    }
    return 'Lỗi máy chủ (HTTP $statusCode)';
  }

  // Lấy danh sách + Tìm kiếm theo tên (Backend tự lọc theo chủ sở hữu dựa trên JWT)
  Future<List<ChildDevice>> getDevices({String? search}) async {
    String endpoint = 'ChildDeviceApi';
    if (search != null && search.trim().isNotEmpty) {
      endpoint += '?search=${Uri.encodeComponent(search.trim())}';
    }
    final response = await _apiClient.get(endpoint);
    if (response.statusCode == 200) {
      List<dynamic> data = jsonDecode(response.body);
      return data.map((item) => ChildDevice.fromJson(item)).toList();
    } else {
      throw Exception(_extractError(response.body, response.statusCode));
    }
  }

  // Tìm kiếm theo ID
  Future<ChildDevice?> getDeviceById(int id) async {
    final response = await _apiClient.get('ChildDeviceApi/$id');
    if (response.statusCode == 200) {
      return ChildDevice.fromJson(jsonDecode(response.body));
    }
    return null;
  }

  // Thêm thiết bị mới
  Future<Map<String, dynamic>> addDevice(ChildDevice device) async {
    final response = await _apiClient.post('ChildDeviceApi', body: device.toJson());
    if (response.statusCode == 201 || response.statusCode == 200) {
      return {"success": true, "message": "Đã thêm thiết bị thành công!"};
    }
    return {
      "success": false,
      "message": _extractError(response.body, response.statusCode),
    };
  }

  // Sửa thông tin thiết bị
  Future<Map<String, dynamic>> updateDevice(ChildDevice device) async {
    final response = await _apiClient.put(
      'ChildDeviceApi/${device.id}',
      body: device.toJson(),
    );
    if (response.statusCode == 204 || response.statusCode == 200) {
      return {"success": true, "message": "Đã cập nhật thiết bị!"};
    }
    return {
      "success": false,
      "message": _extractError(response.body, response.statusCode),
    };
  }

  // Xóa thiết bị
  Future<bool> deleteDevice(int id) async {
    final response = await _apiClient.delete('ChildDeviceApi/$id');
    return response.statusCode == 204 || response.statusCode == 200;
  }

  // Cập nhật tọa độ GPS (Chia sẻ vị trí)
  Future<bool> updateLocation(int id, double lat, double lng) async {
    final response = await _apiClient.put(
      'ChildDeviceApi/$id/location',
      body: {
        "latitude": lat,
        "longitude": lng,
      },
    );
    return response.statusCode == 200;
  }

  // ================== ĐO TIẾNG ỒN ==================

  // Gửi mức tiếng ồn đo được từ điện thoại của trẻ lên Server
  Future<Map<String, dynamic>> reportNoise({
    required int deviceId,
    required double decibel,
    double? peakDecibel,
    int durationSeconds = 1,
  }) async {
    final response = await _apiClient.post(
      'ChildDeviceApi/$deviceId/noise',
      body: {
        "decibel": decibel,
        "peakDecibel": peakDecibel ?? decibel,
        "durationSeconds": durationSeconds,
        "measuredAt": DateTime.now().toUtc().toIso8601String(),
      },
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return {
        "success": true,
        "isAlert": data['isAlert'] == true,
        "thresholdDb": (data['thresholdDb'] as num? ?? 80).toDouble(),
        "parentNotifiedByEmail": data['parentNotifiedByEmail'] == true,
        "message": data['message'] ?? "Đã ghi nhận tiếng ồn.",
      };
    }
    return {
      "success": false,
      "message": _extractError(response.body, response.statusCode),
    };
  }

  // Lấy lịch sử & thống kê tiếng ồn của 1 thiết bị
  Future<Map<String, dynamic>> getNoiseHistory(
    int deviceId, {
    bool alertsOnly = false,
    int take = 50,
  }) async {
    final response = await _apiClient.get(
      'ChildDeviceApi/$deviceId/noise?alertsOnly=$alertsOnly&take=$take',
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final List<dynamic> rawEvents = data['events'] ?? [];
      return {
        "thresholdDb": (data['noiseThresholdDb'] as num? ?? 80).toDouble(),
        "lastNoiseDb": data['lastNoiseDb'] != null
            ? (data['lastNoiseDb'] as num).toDouble()
            : null,
        "count": data['count'] ?? 0,
        "alertCount": data['alertCount'] ?? 0,
        "averageDb": data['averageDb'] != null
            ? (data['averageDb'] as num).toDouble()
            : null,
        "maxDb":
            data['maxDb'] != null ? (data['maxDb'] as num).toDouble() : null,
        "events": rawEvents.map((e) => NoiseEventItem.fromJson(e)).toList(),
      };
    }
    throw Exception(_extractError(response.body, response.statusCode));
  }

  // Phụ huynh đặt ngưỡng dB cảnh báo cho thiết bị
  Future<bool> updateNoiseThreshold(int deviceId, double thresholdDb) async {
    final response = await _apiClient.put(
      'ChildDeviceApi/$deviceId/noise-threshold',
      body: {"thresholdDb": thresholdDb},
    );
    return response.statusCode == 200;
  }

  // Phụ huynh lấy danh sách cảnh báo tiếng ồn chưa xem
  Future<List<NoiseAlertItem>> getUnacknowledgedAlerts() async {
    final response = await _apiClient.get('ChildDeviceApi/noise-alerts');
    if (response.statusCode == 200) {
      final List<dynamic> list = jsonDecode(response.body);
      return list.map((e) => NoiseAlertItem.fromJson(e)).toList();
    }
    return [];
  }

  // Phụ huynh đánh dấu đã xem cảnh báo tiếng ồn
  Future<bool> acknowledgeNoiseAlert(int eventId) async {
    final response = await _apiClient.put(
      'ChildDeviceApi/noise-alerts/$eventId/ack',
      body: {},
    );
    return response.statusCode == 200;
  }
}
