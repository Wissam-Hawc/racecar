#include "Ultrasonic.h"

Ultrasonic::Ultrasonic(int trg, int ech) {
  // Only store pins; pin modes are set in begin() (this object is a global).
  TRG_PIN = trg;
  ECH_PIN = ech;
}

void Ultrasonic::begin() {
  pinMode(TRG_PIN, OUTPUT);
  pinMode(ECH_PIN, INPUT);
  digitalWrite(TRG_PIN, LOW);
}

float Ultrasonic::get_distance() {
  // 10 us trigger pulse, then time the echo high pulse.
  digitalWrite(TRG_PIN, LOW);
  delayMicroseconds(2);
  digitalWrite(TRG_PIN, HIGH);
  delayMicroseconds(10);
  digitalWrite(TRG_PIN, LOW);

  unsigned long pingTime = pulseIn(ECH_PIN, HIGH, ULTR_TIMEOUT);
  if (pingTime == 0) return NO_OBSTACLE;  // nothing echoed back in time

  float distance = (float)pingTime * 0.0343f / 2.0f;  // speed of sound, /2
  return (distance > MAX_RANGE_CM) ? NO_OBSTACLE : distance;
}

float Ultrasonic::get_average_distance() {
  float sum = 0;
  int valid = 0;
  for (int i = 0; i < SAMPLES; i++) {
    float d = get_distance();
    if (d < NO_OBSTACLE) {
      sum += d;
      valid++;
    }
    if (i < SAMPLES - 1) delay(10);
  }
  return (valid > 0) ? (sum / valid) : NO_OBSTACLE;
}
