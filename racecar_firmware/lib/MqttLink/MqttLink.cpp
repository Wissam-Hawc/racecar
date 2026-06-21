#include "MqttLink.h"

#define ASSUMED_SPEED_MPS 0.35f  // rough speed for the odometer estimate
#define DEADMAN_MS 400           // stop if no manual command arrives in time
#define TELEMETRY_MS 500

MqttLink* MqttLink::instance = nullptr;

MqttLink::MqttLink(Motors& m, Camera& c, Ultrasonic& s, const char* id,
                   const char* brokerHost, uint16_t brokerPort)
    : mqtt(net), motors(m), camera(c), sonar(s) {
  carId = id;
  host = brokerHost;
  port = brokerPort;
  instance = this;
}

void MqttLink::onMessageThunk(char* topic, byte* payload, unsigned int len) {
  if (!instance) return;
  String msg;
  for (unsigned int i = 0; i < len; i++) msg += (char)payload[i];
  msg.trim();
  instance->onMessage(String(topic), msg);
}

void MqttLink::begin() {
  clientId = "esp32-" + carId;
  tDrive = "cars/" + carId + "/cmd/drive";
  tMode = "cars/" + carId + "/cmd/mode";
  tCamera = "cars/" + carId + "/cmd/camera";
  tTelemetry = "cars/" + carId + "/telemetry";
  tStatus = "cars/" + carId + "/status";
  tIp = "cars/" + carId + "/ip";
  tRaceStart = "race/start";

  mqtt.setServer(host, port);
  mqtt.setCallback(onMessageThunk);
  reconnect();
}

void MqttLink::reconnect() {
  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("WiFi down -> reconnecting");
    WiFi.reconnect();
    return;
  }

  Serial.print("MQTT connecting...");
  // Last Will: if we drop off, the broker publishes "offline" (retained)
  // so the app's car list sees it instantly. (id, willTopic, qos, retain, msg)
  if (mqtt.connect(clientId.c_str(), tStatus.c_str(), 1, true, "offline")) {
    Serial.println("OK");
    mqtt.publish(tStatus.c_str(), "online", true);  // retained
    mqtt.publish(tIp.c_str(), WiFi.localIP().toString().c_str(), true);
    mqtt.subscribe(tDrive.c_str());
    mqtt.subscribe(tMode.c_str());
    mqtt.subscribe(tCamera.c_str());
    mqtt.subscribe(tRaceStart.c_str());
  } else {
    Serial.printf("failed rc=%d\n", mqtt.state());
  }
}

void MqttLink::applyDrive(const String& cmd) {
  if (cmd == "FWD") {
    motors.moveForward();
  } else if (cmd == "BACK") {
    motors.moveBackward();
  } else if (cmd == "LEFT") {
    motors.moveLeft();
  } else if (cmd == "RIGHT") {
    motors.moveRight();
  } else {
    motors.stop();
  }
}

void MqttLink::onMessage(const String& topic, const String& msg) {
  if (topic == tDrive) {
    if (autoModeFlag) return;  // self-driving: ignore manual commands
    lastCmd = msg;
    lastCmdMs = millis();
    applyDrive(msg);
  } else if (topic == tMode) {
    autoModeFlag = (msg == "AUTO");
    motors.stop();
    Serial.printf("MODE -> %s\n", msg.c_str());
  } else if (topic == tCamera) {
    if (msg == "ON") {
      camera.startStream(80);
    } else {
      camera.stopStream();
    }
  } else if (topic == tRaceStart) {
    autoModeFlag = true;  // fair simultaneous start -> self-drive
    motors.stop();
    Serial.println("RACE START");
  }
}

void MqttLink::publishTelemetry() {
  const bool moving = autoModeFlag || (lastCmd != "STOP");
  if (moving) odometerM += ASSUMED_SPEED_MPS * (TELEMETRY_MS / 1000.0f);

  const float distance = sonar.get_distance();
  const char* mode = autoModeFlag ? "auto" : "manual";

  char buf[170];
  snprintf(buf, sizeof(buf),
           "{\"car\":\"%s\",\"mode\":\"%s\",\"distance_cm\":%.1f,\"rssi\":%d,"
           "\"odometer_m\":%.2f,\"moving\":%s}",
           carId.c_str(), mode, distance, WiFi.RSSI(), odometerM,
           moving ? "true" : "false");
  mqtt.publish(tTelemetry.c_str(), buf);
}

void MqttLink::loop() {
  if (WiFi.status() != WL_CONNECTED || !mqtt.connected()) {
    motors.stop();
    lastCmd = "STOP";
    reconnect();
    return;
  }

  mqtt.loop();

  // Dead-man: in manual mode, if commands stop arriving, brake.
  if (!autoModeFlag && lastCmd != "STOP" && millis() - lastCmdMs > DEADMAN_MS) {
    motors.stop();
    lastCmd = "STOP";
  }

  if (millis() - lastTelemetryMs > TELEMETRY_MS) {
    lastTelemetryMs = millis();
    publishTelemetry();
  }
}
