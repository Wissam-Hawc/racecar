#pragma once

#include "Motors.h"
#include "ServoScanner.h"
#include "Ultrasonic.h"

// Autonomous obstacle avoidance (same logic as the standalone auto sketch):
// drive forward; when something is closer than OBSTACLE_DISTANCE_CM, back up,
// look right and left with the servo, and turn toward the more open side.
// Uses the same Motors as manual mode. Call update() repeatedly in AUTO mode.
class AutoPilot {
 private:
  Motors& motors;
  Ultrasonic& sonar;
  ServoScanner& scanner;

  float distance = 100.0f;
  float OBSTACLE_DISTANCE_CM = 20.0f;  // stop & scan when this close

  float lookRight();  // pan right, read, return to forward
  float lookLeft();
  void turnRight();
  void turnLeft();

 public:
  AutoPilot(Motors& m, Ultrasonic& s, ServoScanner& sc);

  void begin();   // center servo + warm up readings (call entering AUTO)
  void update();  // one pass of the avoidance loop
};
