import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

MqttClient createPlatformMqttClient(String host, int port, String clientId) {
  final client = MqttServerClient(host, clientId);
  client.port = port;
  return client;
}
