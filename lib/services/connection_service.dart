import 'dart:async';
import 'dart:convert';

import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:web_socket_channel/io.dart';

import '../models/baby_cry_data.dart';
import 'app_settings.dart';

enum ConnectionStatus { disconnected, connecting, connected, error }

/// 하드웨어 데이터 수신 서비스 공통 인터페이스.
abstract class ConnectionService {
  final _dataController = StreamController<BabyCryData>.broadcast();
  final _statusController = StreamController<ConnectionStatus>.broadcast();

  ConnectionStatus _status = ConnectionStatus.disconnected;

  Stream<BabyCryData> get dataStream => _dataController.stream;
  Stream<ConnectionStatus> get statusStream => _statusController.stream;
  ConnectionStatus get status => _status;

  Future<void> connect();
  Future<void> disconnect();

  void emitData(BabyCryData data) {
    if (!_dataController.isClosed) _dataController.add(data);
  }

  void setStatus(ConnectionStatus s) {
    _status = s;
    if (!_statusController.isClosed) _statusController.add(s);
  }

  /// ESP32에서 온 JSON 문자열을 파싱해 스트림으로 흘려보낸다.
  void handleRawJson(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        emitData(BabyCryData.fromJson(decoded));
      }
    } catch (_) {
      // 손상된 패킷은 무시 (하드웨어 전송 중 노이즈 가능성)
    }
  }

  void dispose() {
    _dataController.close();
    _statusController.close();
  }

  factory ConnectionService.forSettings(AppSettings settings) {
    switch (settings.mode) {
      case ConnectionMode.mqtt:
        return MqttConnectionService(settings);
      case ConnectionMode.websocket:
        return WebSocketConnectionService(settings);
      case ConnectionMode.demo:
        return DemoConnectionService();
    }
  }

  ConnectionService._();
}

/// MQTT 브로커 경유 원격 수신.
/// ESP32: publish → tiramisu/babycry/{deviceId}, 앱: subscribe.
/// 집 밖에서도 브로커만 접근 가능하면 아기 상태를 확인할 수 있다.
class MqttConnectionService extends ConnectionService {
  final AppSettings settings;
  MqttServerClient? _client;

  MqttConnectionService(this.settings) : super._();

  @override
  Future<void> connect() async {
    setStatus(ConnectionStatus.connecting);
    final client = MqttServerClient(
      settings.mqttHost,
      'tiramisu_app_${DateTime.now().millisecondsSinceEpoch}',
    );
    client.port = settings.mqttPort;
    client.keepAlivePeriod = 30;
    client.autoReconnect = true;
    client.logging(on: false);
    client.onDisconnected = () {
      if (status != ConnectionStatus.error) {
        setStatus(ConnectionStatus.disconnected);
      }
    };
    client.onAutoReconnected = () => setStatus(ConnectionStatus.connected);
    _client = client;

    try {
      await client.connect();
      if (client.connectionStatus?.state == MqttConnectionState.connected) {
        client.subscribe(settings.mqttTopic, MqttQos.atLeastOnce);
        client.updates?.listen((events) {
          for (final event in events) {
            final message = event.payload;
            if (message is MqttPublishMessage) {
              final raw = MqttPublishPayload.bytesToStringAsString(
                message.payload.message,
              );
              handleRawJson(raw);
            }
          }
        });
        setStatus(ConnectionStatus.connected);
      } else {
        setStatus(ConnectionStatus.error);
      }
    } catch (_) {
      setStatus(ConnectionStatus.error);
      client.disconnect();
    }
  }

  @override
  Future<void> disconnect() async {
    _client?.autoReconnect = false;
    _client?.disconnect();
    setStatus(ConnectionStatus.disconnected);
  }
}

/// 같은 Wi-Fi에서 ESP32의 WebSocket 서버(기본 포트 81)에 직접 연결.
class WebSocketConnectionService extends ConnectionService {
  final AppSettings settings;
  IOWebSocketChannel? _channel;
  StreamSubscription? _sub;

  WebSocketConnectionService(this.settings) : super._();

  @override
  Future<void> connect() async {
    setStatus(ConnectionStatus.connecting);
    try {
      final channel = IOWebSocketChannel.connect(
        Uri.parse(settings.wsUrl),
        connectTimeout: const Duration(seconds: 8),
      );
      _channel = channel;
      await channel.ready;
      setStatus(ConnectionStatus.connected);
      _sub = channel.stream.listen(
        (event) => handleRawJson(event.toString()),
        onError: (_) => setStatus(ConnectionStatus.error),
        onDone: () {
          if (status == ConnectionStatus.connected) {
            setStatus(ConnectionStatus.disconnected);
          }
        },
      );
    } catch (_) {
      setStatus(ConnectionStatus.error);
    }
  }

  @override
  Future<void> disconnect() async {
    await _sub?.cancel();
    await _channel?.sink.close();
    setStatus(ConnectionStatus.disconnected);
  }
}

/// 기기 없이 앱 단독으로 체험하는 데모 모드.
/// 홈 화면의 샌드박스 버튼으로 울음 이벤트를 발생시킨다.
class DemoConnectionService extends ConnectionService {
  DemoConnectionService() : super._();

  @override
  Future<void> connect() async {
    setStatus(ConnectionStatus.connecting);
    // 실제 기기 연결처럼 보이는 짧은 지연 연출
    await Future.delayed(const Duration(milliseconds: 800));
    setStatus(ConnectionStatus.connected);
  }

  @override
  Future<void> disconnect() async {
    setStatus(ConnectionStatus.disconnected);
  }

  /// 샌드박스 버튼에서 호출: 모의 하드웨어 이벤트 주입.
  void trigger(String sound, double confidence, int decibel) {
    emitData(BabyCryData(
      deviceId: 'BABY_MONITOR_01',
      timestamp: DateTime.now(),
      detectedSound: sound,
      confidenceScore: confidence,
      decibelLevel: decibel,
    ));
  }
}
