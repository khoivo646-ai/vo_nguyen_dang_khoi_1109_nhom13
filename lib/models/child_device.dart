class ChildDevice {
  final int? id;
  final String childName;
  final String deviceName;
  final int screenTimeLimitMinutes;
  final String blockedApps;
  final bool isLocked;
  final double latitude;
  final double longitude;
  final String? parentUsername;
  final String? childUsername;
  final DateTime? locationUpdatedAt;
  final double noiseThresholdDb;
  final double? lastNoiseDb;
  final DateTime? lastNoiseAt;

  ChildDevice({
    this.id,
    required this.childName,
    required this.deviceName,
    required this.screenTimeLimitMinutes,
    required this.blockedApps,
    required this.isLocked,
    required this.latitude,
    required this.longitude,
    this.parentUsername,
    this.childUsername,
    this.locationUpdatedAt,
    this.noiseThresholdDb = 80.0,
    this.lastNoiseDb,
    this.lastNoiseAt,
  });

  factory ChildDevice.fromJson(Map<String, dynamic> json) {
    return ChildDevice(
      id: json["id"],
      childName: json["childName"] ?? "Chưa đặt tên",
      deviceName: json["deviceName"] ?? "Thiết bị di động",
      screenTimeLimitMinutes: json["screenTimeLimitMinutes"] ?? 120,
      blockedApps: json["blockedApps"] ?? "Không có",
      isLocked: json["isLocked"] ?? false,
      latitude: (json["latitude"] ?? 10.8018).toDouble(),
      longitude: (json["longitude"] ?? 106.7144).toDouble(),
      parentUsername: json["parentUsername"],
      childUsername: json["childUsername"],
      locationUpdatedAt: json["locationUpdatedAt"] != null
          ? DateTime.tryParse(json["locationUpdatedAt"].toString())
          : null,
      noiseThresholdDb: (json["noiseThresholdDb"] ?? 80.0).toDouble(),
      lastNoiseDb: json["lastNoiseDb"] != null
          ? (json["lastNoiseDb"] as num).toDouble()
          : null,
      lastNoiseAt: json["lastNoiseAt"] != null
          ? DateTime.tryParse(json["lastNoiseAt"].toString())
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        if (id != null) "id": id,
        "childName": childName,
        "deviceName": deviceName,
        "screenTimeLimitMinutes": screenTimeLimitMinutes,
        "blockedApps": blockedApps,
        "isLocked": isLocked,
        "latitude": latitude,
        "longitude": longitude,
        if (parentUsername != null && parentUsername!.trim().isNotEmpty)
          "parentUsername": parentUsername!.trim(),
        "childUsername": childUsername?.trim() ?? "",
        "noiseThresholdDb": noiseThresholdDb,
      };
}

class NoiseEventItem {
  final int id;
  final int childDeviceId;
  final double decibel;
  final double? peakDecibel;
  final int durationSeconds;
  final double thresholdDb;
  final bool isAlert;
  final bool isAcknowledged;
  final DateTime measuredAt;

  NoiseEventItem({
    required this.id,
    required this.childDeviceId,
    required this.decibel,
    this.peakDecibel,
    required this.durationSeconds,
    required this.thresholdDb,
    required this.isAlert,
    required this.isAcknowledged,
    required this.measuredAt,
  });

  factory NoiseEventItem.fromJson(Map<String, dynamic> json) {
    return NoiseEventItem(
      id: (json["id"] as num).toInt(),
      childDeviceId: (json["childDeviceId"] as num? ?? 0).toInt(),
      decibel: (json["decibel"] as num? ?? 0).toDouble(),
      peakDecibel: json["peakDecibel"] != null
          ? (json["peakDecibel"] as num).toDouble()
          : null,
      durationSeconds: (json["durationSeconds"] as num? ?? 0).toInt(),
      thresholdDb: (json["thresholdDb"] as num? ?? 80).toDouble(),
      isAlert: json["isAlert"] == true,
      isAcknowledged: json["isAcknowledged"] == true,
      measuredAt: DateTime.tryParse(json["measuredAt"]?.toString() ?? "") ??
          DateTime.now(),
    );
  }
}

class NoiseAlertItem {
  final int id;
  final int childDeviceId;
  final String childName;
  final String deviceName;
  final double decibel;
  final double? peakDecibel;
  final int durationSeconds;
  final double thresholdDb;
  final DateTime measuredAt;

  NoiseAlertItem({
    required this.id,
    required this.childDeviceId,
    required this.childName,
    required this.deviceName,
    required this.decibel,
    this.peakDecibel,
    required this.durationSeconds,
    required this.thresholdDb,
    required this.measuredAt,
  });

  factory NoiseAlertItem.fromJson(Map<String, dynamic> json) {
    return NoiseAlertItem(
      id: (json["id"] as num).toInt(),
      childDeviceId: (json["childDeviceId"] as num).toInt(),
      childName: json["childName"] ?? "",
      deviceName: json["deviceName"] ?? "",
      decibel: (json["decibel"] as num).toDouble(),
      peakDecibel: json["peakDecibel"] != null
          ? (json["peakDecibel"] as num).toDouble()
          : null,
      durationSeconds: (json["durationSeconds"] as num? ?? 0).toInt(),
      thresholdDb: (json["thresholdDb"] as num? ?? 80).toDouble(),
      measuredAt: DateTime.tryParse(json["measuredAt"]?.toString() ?? "") ??
          DateTime.now(),
    );
  }
}
