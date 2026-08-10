import 'package:shared_preferences/shared_preferences.dart';

/// 연결 방식.
/// - demo: 기기 없이 앱 단독 시뮬레이션
/// - mqtt: 브로커 경유 원격 확인 (외출 중에도 확인 가능)
/// - websocket: 같은 Wi-Fi에서 ESP32에 직접 연결
enum ConnectionMode { demo, mqtt, websocket }

/// 앱 설정 (로컬 영구 저장).
class AppSettings {
  ConnectionMode mode;
  String mqttHost;
  int mqttPort;
  String deviceId;
  String wsUrl;
  bool vibrationEnabled;
  bool flashEnabled;
  double confidenceThreshold;

  AppSettings({
    this.mode = ConnectionMode.demo,
    this.mqttHost = 'broker.hivemq.com',
    this.mqttPort = 1883,
    this.deviceId = 'BABY_MONITOR_01',
    this.wsUrl = 'ws://192.168.0.10:81',
    this.vibrationEnabled = true,
    this.flashEnabled = true,
    this.confidenceThreshold = 0.6,
  });

  /// ESP32가 발행하고 앱이 구독하는 MQTT 토픽.
  String get mqttTopic => 'tiramisu/babycry/$deviceId';

  static Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return AppSettings(
      mode: ConnectionMode.values[prefs.getInt('mode') ?? 0],
      mqttHost: prefs.getString('mqttHost') ?? 'broker.hivemq.com',
      mqttPort: prefs.getInt('mqttPort') ?? 1883,
      deviceId: prefs.getString('deviceId') ?? 'BABY_MONITOR_01',
      wsUrl: prefs.getString('wsUrl') ?? 'ws://192.168.0.10:81',
      vibrationEnabled: prefs.getBool('vibrationEnabled') ?? true,
      flashEnabled: prefs.getBool('flashEnabled') ?? true,
      confidenceThreshold: prefs.getDouble('confidenceThreshold') ?? 0.6,
    );
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('mode', mode.index);
    await prefs.setString('mqttHost', mqttHost);
    await prefs.setInt('mqttPort', mqttPort);
    await prefs.setString('deviceId', deviceId);
    await prefs.setString('wsUrl', wsUrl);
    await prefs.setBool('vibrationEnabled', vibrationEnabled);
    await prefs.setBool('flashEnabled', flashEnabled);
    await prefs.setDouble('confidenceThreshold', confidenceThreshold);
  }
}
