#pragma once

#include <Arduino.h>

#define ULTR_TIMEOUT 30000  // 30 ms echo timeout (~5 m)

// HC-SR04 ultrasonic range sensor. Returns distance in cm, or NO_OBSTACLE
// (1000) when nothing is within range. Averages a few samples to de-noise.
class Ultrasonic {
 private:
  int TRG_PIN, ECH_PIN;
  float NO_OBSTACLE = 1000.0f;
  int MAX_RANGE_CM = 400;
  static const int SAMPLES = 3;

 public:
  Ultrasonic(int trg, int ech);
  void begin();                  // set pin modes (call in setup())
  float get_distance();          // one reading (cm)
  float get_average_distance();  // averaged reading (cm)
};
