import 'package:mqtt_client/mqtt_client.dart';

import 'mqtt_client_adapter_io.dart'
    if (dart.library.html) 'mqtt_client_adapter_web.dart';

MqttClient createMqttClient(String host, int port, String clientId) =>
    createPlatformMqttClient(host, port, clientId);
