import 'package:mqtt_client/mqtt_browser_client.dart';
import 'package:mqtt_client/mqtt_client.dart';

MqttClient createPlatformMqttClient(String host, int port, String clientId) {
  // GitHub Pages is HTTPS, so the browser must use HiveMQ's secure WebSocket
  // endpoint instead of the ESP32's plain MQTT/TCP port 1883.
  final isHiveMq = host == 'broker.hivemq.com';
  final wsPort = port == 1883 && isHiveMq ? 8884 : port;
  final server = isHiveMq ? 'wss://$host/mqtt' : 'wss://$host';
  final client = MqttBrowserClient(server, clientId);
  client.port = wsPort;
  client.setProtocolV311();
  client.websocketProtocols = MqttClientConstants.protocolsSingleDefault;
  return client;
}
