import 'package:mqtt_client/mqtt_browser_client.dart';
import 'package:mqtt_client/mqtt_client.dart';

MqttClient createPlatformMqttClient(String host, int port, String clientId) {
  // HiveMQ's plain MQTT port is 1883; browser clients must use WebSocket MQTT.
  final wsPort = port == 1883 ? 8000 : port;
  final client = MqttBrowserClient('ws://$host', clientId);
  client.port = wsPort;
  client.websocketProtocols = MqttClientConstants.protocolsSingleDefault;
  return client;
}
