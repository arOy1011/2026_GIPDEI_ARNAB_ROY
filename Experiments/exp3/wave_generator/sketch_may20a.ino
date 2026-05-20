#include <math.h>
#include <Adafruit_GFX.h>
#include <Adafruit_PCD8544.h>

Adafruit_PCD8544 display = Adafruit_PCD8544(A4, A3, A2, A1, A0);

// ── Exact original pin setup ──────────────────────────────────────────────────
int dacPins[8] = {6, 7, 8, 9, 10, 11, 12, 13};
int pwmPin = 5;

// ── Buttons ───────────────────────────────────────────────────────────────────
const int btnSine = 2;
const int btnTri  = 3;
const int btnPWM  = 4;
const int potPin  = A5;

// ── Wave select ───────────────────────────────────────────────────────────────
char activeWave = 'S';

// ── Exact original triangle state ─────────────────────────────────────────────
int value     = 0;
int direction = 1;

// ── Exact original sine state ─────────────────────────────────────────────────
float angle = 0;

// ── Exact original PWM state ──────────────────────────────────────────────────
bool pwmState = false;

// ── Timing (replaces delayMicroseconds) ───────────────────────────────────────
unsigned long lastDac     = 0;
unsigned long lastPwm     = 0;
unsigned long lastDisplay = 0;

// ── Original delays, now pot-controlled ───────────────────────────────────────
// Pot LOW  → small delay → fast wave
// Pot HIGH → large delay → slow & visible on simulator
// Range chosen so simulator scope can render it clearly (5–50 Hz)
unsigned long getDacDelay(int potVal) {
  return (unsigned long)map(potVal, 0, 1023, 200, 500); // µs
}

// PWM stays fixed at original 500µs each side — it already worked
const unsigned long PWM_HALF = 8000;

// ─────────────────────────────────────────────────────────────────────────────
void outputDAC(int number) {
  for (int i = 0; i < 8; i++) {
    digitalWrite(dacPins[i], (number >> i) & 1);
  }
}

void updateDisplay(char wave, int potVal) {
  display.clearDisplay();
  display.setTextSize(1);
  display.setTextColor(BLACK);

  display.setCursor(0, 0);
  switch (wave) {
    case 'S': display.print(F("Waveform: SINE")); break;
    case 'T': display.print(F("Waveform: TRI"));  break;
    case 'P': display.print(F("Waveform: PWM"));  break;
  }

  display.setCursor(0, 10);
  display.print(F("Pot: "));
  display.print(potVal);

  display.setCursor(0, 20);
  switch (wave) {
    case 'S':
    case 'T': display.print(F("Amp: 127 DAC")); break;
    case 'P': display.print(F("Duty: 50%"));    break;
  }

  display.setCursor(0, 30);
  switch (wave) {
    case 'S': display.print(F("Step: 0.2 rad")); break;
    case 'T': display.print(F("Step: 8"));       break;
    case 'P': display.print(F("Period: 1ms"));   break;
  }

  display.setCursor(0, 40);
  switch (wave) {
    case 'S':
    case 'T': display.print(F("Out: D6-D13 DAC")); break;
    case 'P': display.print(F("Out: D5"));          break;
  }

  display.display();
}

void setup() {
  for (int i = 0; i < 8; i++) pinMode(dacPins[i], OUTPUT);
  pinMode(pwmPin,  OUTPUT);
  pinMode(btnSine, INPUT_PULLUP);
  pinMode(btnTri,  INPUT_PULLUP);
  pinMode(btnPWM,  INPUT_PULLUP);

  display.begin();
  display.setContrast(57);
  display.clearDisplay();
  display.display();

  Serial.begin(9600);
  updateDisplay(activeWave, 512);
}

void loop() {
  unsigned long now = micros();
  int potVal        = analogRead(potPin);
  unsigned long dacDelay = getDacDelay(potVal);

  // ── Buttons ───────────────────────────────────────────────────────────────
  if (digitalRead(btnSine) == LOW && activeWave != 'S') {
    activeWave = 'S';
    angle = 0;               // reset sine to start
    delay(50);               // debounce
  } else if (digitalRead(btnTri) == LOW && activeWave != 'T') {
    activeWave = 'T';
    value = 0; direction = 1; // reset triangle to start
    delay(50);
  } else if (digitalRead(btnPWM) == LOW && activeWave != 'P') {
    activeWave = 'P';
    outputDAC(0);            // silence DAC when switching to PWM
    pwmState = false;
    delay(50);
  }

  // ── PWM: always runs on its own pin, unaffected by DAC wave ───────────────
  // Exact original logic: HIGH 500µs, LOW 500µs
  if (now - lastPwm >= PWM_HALF) {
    lastPwm = now;
    if (activeWave == 'P') {
      pwmState = !pwmState;
      digitalWrite(pwmPin, pwmState ? HIGH : LOW);
    } else {
      digitalWrite(pwmPin, LOW);
    }
  }

  // ── DAC: runs sine OR triangle, never both ────────────────────────────────
  if (now - lastDac >= dacDelay) {
    lastDac = now;

    if (activeWave == 'S') {
      // ── Exact original sine logic ─────────────────────────────────────────
      int sineValue = 127 + 127 * sin(angle);
      outputDAC(sineValue);
      angle += 0.2;
      if (angle >= 6.283) angle = 0;

    } else if (activeWave == 'T') {
      // ── Exact original triangle logic ─────────────────────────────────────
      outputDAC(value);
      value += direction * 8;
      if (value >= 255) { value = 255; direction = -1; }
      if (value <= 0)   { value = 0;   direction =  1; }
    }
    // PWM does not touch the DAC
  }

  // ── Display refresh every 300ms ───────────────────────────────────────────
  if (millis() - lastDisplay >= 300) {
    lastDisplay = millis();
    updateDisplay(activeWave, potVal);
  }
}