#include "Motors.h"

Motors::Motors(int i1, int i2, int i3, int i4) {
  in1 = i1;
  in2 = i2;
  in3 = i3;
  in4 = i4;
}

void Motors::begin() {
  pinMode(in1, OUTPUT);
  pinMode(in2, OUTPUT);
  pinMode(in3, OUTPUT);
  pinMode(in4, OUTPUT);
  stop();
}

void Motors::stop() {
 //this brakes the motors.
  digitalWrite(in1, LOW);
  digitalWrite(in2, LOW);
  digitalWrite(in3, LOW);
  digitalWrite(in4, LOW);
}

void Motors::moveForward() {
  digitalWrite(in1, HIGH);  // left forward
  digitalWrite(in2, LOW);
  digitalWrite(in3, HIGH);  // right forward
  digitalWrite(in4, LOW);
}

void Motors::moveBackward() {
  digitalWrite(in1, LOW);   // left reverse
  digitalWrite(in2, HIGH);
  digitalWrite(in3, LOW);   // right reverse
  digitalWrite(in4, HIGH);
}

// Swapped to match the wiring: IN1/IN2 turned out to be the RIGHT side.
void Motors::moveRight() {
  digitalWrite(in1, LOW);
  digitalWrite(in2, LOW);
  digitalWrite(in3, HIGH);
  digitalWrite(in4, LOW);
}

void Motors::moveLeft() {
  digitalWrite(in1, HIGH);
  digitalWrite(in2, LOW);
  digitalWrite(in3, LOW);
  digitalWrite(in4, LOW);
}
