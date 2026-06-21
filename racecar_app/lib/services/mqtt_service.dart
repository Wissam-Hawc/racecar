import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

import '../mqtt_topics.dart';

/// Connection state of the broker link, exposed to the UI.
enum BrokerStatus { disconnected, connecting, connected, error }

/// A single message we received from the broker, kept for the on-screen log.
class MqttLogEntry {
  final String topic;
  final String payload;
  MqttLogEntry(this.topic, this.payload);
}

class MqttService extends ChangeNotifier {
  MqttServerClient? _client;

  BrokerStatus status = BrokerStatus.disconnected;
  String? lastError;

  /// Rolling log of the most recent messages, newest first.
  final List<MqttLogEntry> log = [];

  /// Each car's online/offline status. Filled from the retained `cars/<id>/status`
  final Map<String, bool> cars = {};

  /// Each car's IP address, from the retained `cars/<id>/ip`
  final Map<String, String> carIp = {};

  bool get isConnected => status == BrokerStatus.connected;

  /// Subscribe to every car's status + IP so the broker replays them.
  void discoverCars() {
    subscribe(Topics.allStatus);
    subscribe(Topics.allIp);
  }

  /// Manually set a car's IP (used until the car publishes it over MQTT).
  void setCarIp(String id, String ip) {
    carIp[id] = ip;
    notifyListeners();
  }

  Future<void> connect({
    required String host,
    int port = 1883,
    required String clientId,
  }) async {
    // Tear down any previous client before starting a new connection.
    disconnect();

    final client = MqttServerClient.withPort(host, clientId, port);
    client.keepAlivePeriod = 20;
    client.autoReconnect = true;
    client.connectTimeoutPeriod = 5000; // ms
    client.logging(on: false);
    client.onConnected = _onConnected;
    client.onDisconnected = _onDisconnected;

    // Clean session: we don't want the broker queuing stale drive commands
    // for us while we were away.
    client.connectionMessage = MqttConnectMessage()
        .withClientIdentifier(clientId) 
        .startClean();

    _client = client;
    _setStatus(BrokerStatus.connecting);

    try {
      await client.connect();
    } catch (e) {
      lastError = e.toString();
      _setStatus(BrokerStatus.error);
      client.disconnect();
      return;
    }

    if (client.connectionStatus?.state == MqttConnectionState.connected) {
      // Listen for all incoming messages on subscribed topics.
      client.updates?.listen(_onMessage);
    } else {
      lastError = 'Connect failed: ${client.connectionStatus?.state}';
      _setStatus(BrokerStatus.error);
    }
  }

  void disconnect() {
    _client?.disconnect();
    _client = null;
    if (status != BrokerStatus.disconnected) {
      _setStatus(BrokerStatus.disconnected);
    }
  }

  /// Subscribe to a topic (wildcards like `cars/+/status/#` are allowed).
  void subscribe(String topic, {MqttQos qos = MqttQos.atMostOnce}) {
    _client?.subscribe(topic, qos);
  }

  void publish(
    String topic,
    String message, {
    MqttQos qos = MqttQos.atMostOnce,
    bool retain = false,
  }) {
    final client = _client;
    if (client == null || !isConnected) return;
    final builder = MqttClientPayloadBuilder()..addString(message);
    client.publishMessage(topic, qos, builder.payload!, retain: retain);
  }

  void _onMessage(List<MqttReceivedMessage<MqttMessage>> events) {
    for (final event in events) {
      final recMsg = event.payload as MqttPublishMessage;
      final payload =
          MqttPublishPayload.bytesToStringAsString(recMsg.payload.message);
      log.insert(0, MqttLogEntry(event.topic, payload));
      if (log.length > 50) log.removeLast();

      // Track car presence from retained status topics.
      final match = Topics.statusPattern.firstMatch(event.topic);
      if (match != null) {
        cars[match.group(1)!] = payload.trim().toLowerCase() == 'online';
      }

      // Track car IPs (for the camera stream URL).
      final ipMatch = Topics.ipPattern.firstMatch(event.topic);
      if (ipMatch != null && payload.trim().isNotEmpty) {
        carIp[ipMatch.group(1)!] = payload.trim();
      }
    }
    notifyListeners();
  }

  void _onConnected() => _setStatus(BrokerStatus.connected);

  void _onDisconnected() {
    // autoReconnect handles transient drops; only reflect a hard disconnect.
    if (_client == null) return;
    _setStatus(BrokerStatus.disconnected);
  }

  void _setStatus(BrokerStatus s) {
    status = s;
    notifyListeners();
  }

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}
