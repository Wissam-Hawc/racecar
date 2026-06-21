#include "AutoPilot.h"

#define TURN_MS 500       // turn duration (tune for ~90 deg pivot)
#define BACKWARD_MS 300   // reverse duration before scanning

AutoPilot::AutoPilot(Motors& m, Ultrasonic& s, ServoScanner& sc)
    : motors(m), sonar(s), scanner(sc) {}

void AutoPilot::begin() {
  scanner.lookForward();
  // warm up a few sensor readings so the first decision is stable
  for (int i = 0; i < 4; i++) {
    distance = sonar.get_average_distance();
    delay(100);
  }
}

float AutoPilot::lookRight() {
  scanner.lookRight();
  float d = sonar.get_average_distance();
  delay(100);
  scanner.lookForward();
  return d;
}

float AutoPilot::lookLeft() {
  scanner.lookLeft();
  float d = sonar.get_average_distance();
  delay(100);
  scanner.lookForward();
  return d;
}

void AutoPilot::turnRight() {
  motors.moveRight();
  delay(TURN_MS);
  motors.stop();
}

void AutoPilot::turnLeft() {
  motors.moveLeft();
  delay(TURN_MS);
  motors.stop();
}

void AutoPilot::update() {
  if (distance <= OBSTACLE_DISTANCE_CM) {
    motors.stop();
    delay(100);

    motors.moveBackward();
    delay(BACKWARD_MS);
    motors.stop();
    delay(200);

    float distanceR = lookRight();
    delay(200);
    float distanceL = lookLeft();
    delay(200);

    Serial.printf("[SCAN] R:%.1f  L:%.1f\n", distanceR, distanceL);

    if (distanceR >= distanceL) {
      turnRight();
    } else {
      turnLeft();
    }

    // re-check before deciding to drive again
    distance = sonar.get_average_distance();
    return;
  }

  motors.moveForward();
  distance = sonar.get_average_distance();
}
