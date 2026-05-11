// ============================================================
//  RIPHAH INTERNATIONAL UNIVERSITY
//  Department of Electrical & Computer Engineering
//  Subject  : Digital Logic Design
//  Project  : Ultrasonic Radar with Pin-2 Lock System
//  Instructor   : Syed Hassaan
//  Authors:
//    Hanan Shafay  — SAP ID: 72442
//    Mohid Ahmed   — SAP ID: 73410
//    Umair Hassan  — SAP ID: 74825
// ============================================================
//
//  WIRING:
//    Servo Signal  → Pin 12
//    TRIG          → Pin 10
//    ECHO          → Pin 11
//    LOCK          → Pin 2
//      Pin 2 LOW (buttons held) = toggles radar ON
//      Pin 2 LOW again          = toggles radar OFF
//
//  HOW THE LOCK WORKS:
//    INPUT_PULLUP is used on pin 2.
//    Falling edge on pin 2 (HIGH → LOW) toggles radar state.
//    Holding pin 2 LOW does nothing after the first toggle.
// ============================================================

#include <Servo.h>

#define LOCK_PIN         2
#define TRIG_PIN        10
#define ECHO_PIN        11
#define SERVO_PIN       12

#define MAX_ANGLE        180
#define MIN_ANGLE          0
#define SWEEP_STEP         2
#define STEP_DELAY        30
#define STATUS_REPEAT_MS 500

Servo radarServo;

bool isLocked       = true;
bool radarOn        = false;
bool lastPinState   = true;   // HIGH = unpressed (INPUT_PULLUP default)

unsigned long lastStatusTime = 0;
int sweepAngle = 0;
int sweepDir   = 1;

// ─────────────────────────────────────────────────────────────
// sendStatus: sends "LOCKED." or "ACTIVE." — no newline ever.
// Processing buffers until '.' so the dot alone is enough.
// ─────────────────────────────────────────────────────────────
void sendStatus(bool locked) {
  Serial.print(locked ? "LOCKED." : "ACTIVE.");
}

// ─────────────────────────────────────────────────────────────
// sendData: sends "angle,distance." — no newline ever.
// ─────────────────────────────────────────────────────────────
void sendData(int angle, int distance) {
  Serial.print(angle);
  Serial.print(',');
  Serial.print(distance);
  Serial.print('.');
}

// ─────────────────────────────────────────────────────────────
int measureDistance() {
  digitalWrite(TRIG_PIN, LOW);
  delayMicroseconds(2);
  digitalWrite(TRIG_PIN, HIGH);
  delayMicroseconds(10);
  digitalWrite(TRIG_PIN, LOW);
  long dur = pulseIn(ECHO_PIN, HIGH, 25000UL);
  if (dur == 0) return 999;
  return (int)(dur * 0.01715);
}

// ─────────────────────────────────────────────────────────────
// activateRadar: called on falling edge when radar is OFF
// ─────────────────────────────────────────────────────────────
void activateRadar() {
  isLocked   = false;
  radarOn    = true;
  sweepAngle = 0;
  sweepDir   = 1;
  sendStatus(false);
}

// ─────────────────────────────────────────────────────────────
// lockRadar: called on falling edge when radar is ON
// ─────────────────────────────────────────────────────────────
void lockRadar() {
  isLocked = true;
  radarOn  = false;
  radarServo.write(0);
  sendStatus(true);
}

// ─────────────────────────────────────────────────────────────
void setup() {
  Serial.begin(9600);

  pinMode(LOCK_PIN, INPUT_PULLUP);
  pinMode(TRIG_PIN, OUTPUT);
  pinMode(ECHO_PIN, INPUT);
  radarServo.attach(SERVO_PIN);
  radarServo.write(0);

  lastStatusTime = millis();
  sendStatus(true);
}

// ─────────────────────────────────────────────────────────────
void loop() {
  unsigned long now = millis();
  bool currentPin = digitalRead(LOCK_PIN);  // HIGH = unpressed, LOW = pressed

  // ── 1. Detect falling edge (HIGH → LOW) and toggle ─────
  if (lastPinState == HIGH && currentPin == LOW) {
    lastStatusTime = now;
    if (radarOn) {
      lockRadar();
    } else {
      activateRadar();
    }
  }

  lastPinState = currentPin;

  // ── 2. While locked: keep telling Processing ───────────
  if (isLocked) {
    if (now - lastStatusTime >= STATUS_REPEAT_MS) {
      sendStatus(true);
      lastStatusTime = now;
    }
    return;
  }

  // ── 3. While active: sweep and send data ───────────────
  radarServo.write(sweepAngle);
  delay(STEP_DELAY);

  int dist = measureDistance();
  sendData(sweepAngle, dist);

  sweepAngle += sweepDir * SWEEP_STEP;
  if (sweepAngle >= MAX_ANGLE) { sweepAngle = MAX_ANGLE; sweepDir = -1; }
  if (sweepAngle <= MIN_ANGLE) { sweepAngle = MIN_ANGLE; sweepDir =  1; }
}