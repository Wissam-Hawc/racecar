#pragma once

#include <Arduino.h>
#include <PubSubClient.h>
#include <WiFi.h>

#include "Camera.h"
#include "Motors.h"
#include "Ultrasonic.h"

class MqttLink {
 private:
  WiFiClient net;
  PubSubClient mqtt;
  Motors& motors;
  Camera& camera;
  Ultrasonic& sonar;

  String carId;
  const char* host;
  uint16_t port;

  String clientId;

  // Topics (built from carId in begin(), e.g. "cars/wissam/cmd/drive").
  String tDrive;      // SUB  app -> car   FWD/BACK/LEFT/RIGHT/STOP
  String tMode;       // SUB  app -> car   MANUAL/AUTO
  String tCamera;     // SUB  app -> car   ON/OFF
  String tRaceStart;  // SUB  race/start   (all cars)
  String tStatus;     // PUB  online/offline (retained + Last-Will)
  String tIp;         // PUB  our IP for the camera URL (retained)
  String tTelemetry;  // PUB  distance/rssi/odometer JSON, every 500 ms

  bool autoModeFlag = false;
  String lastCmd = "STOP";
  unsigned long lastCmdMs = 0;
  unsigned long lastTelemetryMs = 0;
  unsigned long lastReconnectMs = 0;  // throttles non-blocking reconnect tries
  float odometerM = 0.0f;  // estimated distance travelled (kilometrage)

  static MqttLink* instance; 
  static void onMessageThunk(char* topic, byte* payload, unsigned int len);

  void onMessage(const String& topic, const String& msg);
  void reconnect();
  void publishTelemetry();
  void applyDrive(const String& cmd);

 public:
  MqttLink(Motors& m, Camera& c, Ultrasonic& s, const char* id,
           const char* brokerHost, uint16_t brokerPort = 1883);

  void begin();
  void loop();
  bool isAuto() const { return autoModeFlag; }
};
