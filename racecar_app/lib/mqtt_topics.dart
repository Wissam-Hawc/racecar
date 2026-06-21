import 'package:mqtt_client/mqtt_client.dart' show MqttQos;

class Topics {
  static String status(String id) => 'cars/$id/status';
  static String driveCmd(String id) => 'cars/$id/cmd/drive';
  static String modeCmd(String id) => 'cars/$id/cmd/mode';
  static String cameraCmd(String id) => 'cars/$id/cmd/camera';
  static String telemetry(String id) => 'cars/$id/telemetry';

  static String ip(String id) => 'cars/$id/ip';

  static const String allStatus = 'cars/+/status';
  static const String allIp = 'cars/+/ip';

  /// Extract the car id from a concrete `cars/<id>/status` or `cars/<id>/ip`.
  static final RegExp statusPattern = RegExp(r'^cars/([^/]+)/status$');
  static final RegExp ipPattern = RegExp(r'^cars/([^/]+)/ip$');

  // --- race namespace -------------------------------------------------------
  static String racePlayer(String code, String color) =>
      'race/$code/players/$color';
  static String racePlayersWildcard(String code) => 'race/$code/players/+';
  static String raceStart(String code) => 'race/$code/start';

  /// Host publishes the match config here when starting; the finish-line judge
  /// ESP subscribes to learn who is racing. JSON: {code, red, blue}.
  static const String raceMatch = 'race/match';

  /// The judge ESP publishes one message per finisher here.
  /// JSON: `{time: seconds, playerName: "...", playerColor: "red"|"blue"}`.
  static const String raceResult = 'race/result';

  static const MqttQos qosDrive = MqttQos.atMostOnce; // QoS 0, ephemeral
  static const MqttQos qosEvent = MqttQos.atLeastOnce; // QoS 1, must arrive
}
