#pragma once

#include <ESP32Servo.h>

#include "Ultrasonic.h"

// A servo that pans the ultrasonic sensor left / forward / right so the car
// can "look around" before deciding where to go.
class ServoScanner {
 private:
  Servo myservo;
  int servoPin;
  int settleMs = 300;  // wait after a move so the reading is stable

 public:
  static const int ANGLE_RIGHT = 0;
  static const int ANGLE_FORWARD = 90;
  static const int ANGLE_LEFT = 180;
  int currentAngle = ANGLE_FORWARD;

  ServoScanner(int sPin);
  void begin(); 

  void lookForward();
  void lookRight();
  void lookLeft();
  void moveTo(int angleDeg);

  // Sweep right/forward/left, fill the three distances, and return true if
  // any direction is clear (>= clearanceCm). Leaves the servo facing forward.
  bool scanAll(Ultrasonic& sonar, float& distRight, float& distForward,
               float& distLeft, float clearanceCm = 30.0f);
};
