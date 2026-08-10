/// 하드웨어(XIAO ESP32S3)로부터 수신하는 아기 울음 데이터 모델.
///
/// ESP32가 MQTT/WebSocket으로 전송하는 JSON 패킷 형식:
/// ```json
/// {
///   "device_id": "BABY_MONITOR_01",
///   "timestamp": "2026-07-14T14:15:00Z",
///   "detected_sound": "Neh",
///   "confidence_score": 0.92,
///   "decibel_level": 65
/// }
/// ```
class BabyCryData {
  final String deviceId;
  final DateTime timestamp;
  final String detectedSound;
  final double confidenceScore;
  final int decibelLevel;

  const BabyCryData({
    required this.deviceId,
    required this.timestamp,
    required this.detectedSound,
    required this.confidenceScore,
    required this.decibelLevel,
  });

  factory BabyCryData.fromJson(Map<String, dynamic> json) {
    return BabyCryData(
      deviceId: json['device_id'] as String? ?? 'UNKNOWN_MONITOR',
      timestamp: json['timestamp'] != null
          ? DateTime.tryParse(json['timestamp'] as String)?.toLocal() ??
              DateTime.now()
          : DateTime.now(),
      detectedSound: json['detected_sound'] as String? ?? 'Unknown',
      // num으로 받아 정수/실수 혼입으로 인한 연동 버그를 방지한다.
      confidenceScore: (json['confidence_score'] as num? ?? 0.0).toDouble(),
      decibelLevel: (json['decibel_level'] as num? ?? 0).toInt(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'device_id': deviceId,
      'timestamp': timestamp.toIso8601String(),
      'detected_sound': detectedSound,
      'confidence_score': confidenceScore,
      'decibel_level': decibelLevel,
    };
  }
}
