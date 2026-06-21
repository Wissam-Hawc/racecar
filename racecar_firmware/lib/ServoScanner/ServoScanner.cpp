#include "ServoScanner.h"

ServoScanner::ServoScanner(int sPin) {
  // Only store the pin; the servo is attached in begin() (global object).
  servoPin = sPin;
}

void ServoScanner::begin() {
  // Put the servo on LEDC timer 1 so it never fights the camera (timer 0).
  // Without this, enabling the camera glitches the servo signal -> buzzing.
  ESP32PWM::allocateTimer(1);
  myservo.setPeriodHertz(50);            // standard 50 Hz servo signal
  myservo.attach(servoPin, 500, 2500);   // min/max pulse widths (us)
  moveTo(ANGLE_FORWARD);                  // start centered
}

void ServoScanner::lookForward() { moveTo(ANGLE_FORWARD); }
void ServoScanner::lookRight() { moveTo(ANGLE_RIGHT); }
void ServoScanner::lookLeft() { moveTo(ANGLE_LEFT); }

void ServoScanner::moveTo(int angleDeg) {
  angleDeg = constrain(angleDeg, 0, 180);
  myservo.write(angleDeg);
  delay(settleMs);  // let it physically reach the angle before reading
  currentAngle = angleDeg;
}

bool ServoScanner::scanAll(Ultrasonic& sonar, float& distRight,
                           float& distForward, float& distLeft,
                           float clearanceCm) {
  lookRight();
  distRight = sonar.get_average_distance();
  lookForward();
  distForward = sonar.get_average_distance();
  lookLeft();
  distLeft = sonar.get_average_distance();
  lookForward();  // leave it centered

  return (distRight >= clearanceCm || distForward >= clearanceCm ||
          distLeft >= clearanceCm);
}
