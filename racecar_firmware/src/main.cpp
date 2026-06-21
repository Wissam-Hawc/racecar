#include <Arduino.h>
#include <WiFi.h>

#include "soc/rtc_cntl_reg.h" 
#include "soc/soc.h"

#include "AutoPilot.h"
#include "Camera.h"
#include "Motors.h"
#include "MqttLink.h"
#include "ServoScanner.h"
#include "Ultrasonic.h"

static const char* WIFI_SSID = "My Test Router";
static const char* WIFI_PASSWORD = "wissam123";

// Gateway PC running the broker (same network). Update to its current IP.
static const char* MQTT_HOST = "192.168.1.64";

// This car's name -> its topics become cars/<name>/...
// Set per car by the PlatformIO env (-D CAR_NAME). Defaults to "wissam".
#ifndef CAR_NAME
#define CAR_NAME "wissam"
#endif
static const char* CAR_ID = CAR_NAME;

Camera camera;
Motors motors(13, 14, 32, 33);
Ultrasonic sonar(2, 12);
ServoScanner scanner(15);
AutoPilot autopilot(motors, sonar, scanner);

// The app <-> car link (commands, status, telemetry).
MqttLink mqtt(motors, camera, sonar, CAR_ID, MQTT_HOST);

bool prevAuto = false;

static void connectWifi() {
  WiFi.mode(WIFI_STA);
  WiFi.setSleep(false);         // critical: keeps streaming latency low
  WiFi.setAutoReconnect(true);  // auto re-join the AP if the car leaves range
  WiFi.persistent(true);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);

  Serial.print("Connecting WiFi");
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }
  WiFi.setTxPower(WIFI_POWER_19_5dBm);
  Serial.printf("\nWiFi OK  IP=%s  RSSI=%d\n",
                WiFi.localIP().toString().c_str(), WiFi.RSSI());
}

void setup() {
  WRITE_PERI_REG(RTC_CNTL_BROWN_OUT_REG, 0);  // avoid brownout resets

  // Stop the motors FIRST (drives the IN pins LOW) so the wheels don't twitch
  // during boot while the camera/Wi-Fi are still initialising.
  motors.begin();

  Serial.begin(9600);
  Serial.setDebugOutput(true);
  Serial.println("\nBooting race-car firmware...");

  if (!camera.begin()) {
    Serial.println("HALTED — fix camera init before continuing.");
    while (true) delay(1000);
  }

  sonar.begin();    // just pin modes — harmless, no LEDC
  scanner.begin();  // attach servo on LEDC timer 1 (clear of the camera) + center

  connectWifi();
  camera.startStream(80);
  mqtt.begin();  // connect to broker, subscribe to commands, announce status
  Serial.println("STREAM READY -> http://<IP>:80/stream");
}

void loop() {
  mqtt.loop(); 

  const bool a = mqtt.isAuto();
  if (a && !prevAuto) autopilot.begin(); 
  prevAuto = a;
  if (a) autopilot.update();            

  delay(20);
}
