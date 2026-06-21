#pragma once

#include <Arduino.h>

class Motors {
 private:
  int in1, in2, in3, in4;

 public:
  Motors(int i1, int i2, int i3, int i4);

  void begin();         // set the pins as outputs and stop (call in setup())
  void moveForward();
  void moveBackward();
  void moveLeft();      // pivot left  (left side stop, right side forward)
  void moveRight();     // pivot right (right side stop, left side forward)
  void stop();          // both sides LOW -> L298N brakes
};
