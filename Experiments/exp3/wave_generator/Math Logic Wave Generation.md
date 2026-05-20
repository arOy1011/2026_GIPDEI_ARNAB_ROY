*These are the mathematical logics used to create waveforms, they can be implemented individually.*
# TRIANGLE
```Cpp
int dacPins[8] = {6,7,8,9,10,11,12,13};

int value = 0;

int direction = 1;

void setup() {

  for(int i=0;i<8;i++) {

    pinMode(dacPins[i], OUTPUT);

  }

}

void loop() {

  outputDAC(value);

  value += direction * 8;

  if(value >= 255) {

    value = 255;

    direction = -1;

  }

  if(value <= 0) {

    value = 0;

    direction = 1;

  }

  delayMicroseconds(20);

}

void outputDAC(int number) {

  for(int i=0;i<8;i++) {

    digitalWrite(dacPins[i], (number >> i) & 1);

  }

}
```

# SINE
```cpp
#include <math.h>

int dacPins[8] = {6,7,8,9,10,11,12,13};

float angle = 0;

void setup() {

  for(int i=0;i<8;i++) {

    pinMode(dacPins[i], OUTPUT);

  }

}

void loop() {

  int sineValue = 127 + 127 * sin(angle);

  outputDAC(sineValue);

  angle += 0.2;

  if(angle >= 6.283) {

    angle = 0;

  }

  delayMicroseconds(50);

}

void outputDAC(int value) {

  for(int i=0;i<8;i++) {

    digitalWrite(dacPins[i], (value >> i) & 1);

  }

}
```

# PWM
```cpp
int pwmPin = 5;

void setup() {

  pinMode(pwmPin, OUTPUT);

}

void loop() {

  digitalWrite(pwmPin, HIGH);

  delayMicroseconds(500);

  digitalWrite(pwmPin, LOW);

  delayMicroseconds(500);

}
```

# How These Three Sketches Are Combined

## The Problem With Combining Directly

Each sketch uses `delayMicroseconds()` which **freezes the entire CPU** for its duration.
When merged into one loop, the PWM's 500µs delay blocks the DAC, and the DAC delays
block the PWM toggle — all three fight over the same CPU and corrupt each other's timing.

---

## Step 1 — Identify What Each Sketch Owns

| Sketch | Pins Used | Delay | State Variables |
|---|---|---|---|
| Triangle | D6–D13 (DAC) | 20 µs | `value`, `direction` |
| Sine | D6–D13 (DAC) | 50 µs | `angle` |
| PWM | D5 only | 500 µs | HIGH / LOW |

Key observation:
- Triangle and Sine share the same DAC pins → they **cannot run simultaneously**
- PWM is on its own pin D5 → it **never conflicts** with the DAC

---

## Step 2 — Replace delayMicroseconds() With micros() Timers

Instead of blocking the CPU, each wave checks if enough time has passed:

```cpp
// BEFORE (blocks everything):
delayMicroseconds(20);

// AFTER (non-blocking, CPU stays free):
if (micros() - lastDac >= dacDelay) {
    lastDac = micros();
    // wave logic here
}
````

This means every part of `loop()` runs every iteration. Nothing waits. Nothing blocks anything else.

---

## Step 3 — Gate Sine and Triangle With a Button Switch

Since both use D6–D13, only one runs at a time. A variable `activeWave` holds `'S'`, `'T'`, or `'P'`. Buttons on D2, D3, D4 set it:

```cpp
if (digitalRead(btnSine) == LOW) activeWave = 'S';
if (digitalRead(btnTri)  == LOW) activeWave = 'T';
if (digitalRead(btnPWM)  == LOW) activeWave = 'P';
```

The DAC block only runs the selected wave:

```cpp
if (activeWave == 'S') {
    // exact original sine logic
} else if (activeWave == 'T') {
    // exact original triangle logic
}
```

---

## Step 4 — Give PWM Its Own Independent Timer

PWM runs on a completely separate `lastPwm` timer, independent of the DAC timer — so it never interferes:

```cpp
if (micros() - lastPwm >= PWM_HALF) {
    lastPwm = micros();
    // toggle D5
}
```

PWM stays fixed at 500µs half-period (1 kHz) exactly as the original sketch. The potentiometer only controls the DAC delay (sine/triangle frequency).

---

## Step 5 — Final Combined Loop Structure

```
loop() runs continuously:
│
├── Read buttons → set activeWave
│
├── PWM timer (independent, fixed 500µs)
│    └── toggles D5 HIGH/LOW regardless of activeWave
│
├── DAC timer (pot-controlled delay)
│    ├── if activeWave == 'S' → sine logic on D6–D13
│    └── if activeWave == 'T' → triangle logic on D6–D13
│
└── Display timer (every 300ms)
     └── update LCD with waveform info
```

---

## What Was NOT Changed

These are kept exactly as the original standalone sketches:

```cpp
// Triangle — unchanged
value += direction * 8;
if (value >= 255) { value = 255; direction = -1; }
if (value <= 0)   { value = 0;   direction =  1; }

// Sine — unchanged
int sineValue = 127 + 127 * sin(angle);
angle += 0.2;
if (angle >= 6.283) angle = 0;

// PWM — unchanged
digitalWrite(pwmPin, HIGH); // 500µs
digitalWrite(pwmPin, LOW);  // 500µs
```

Only the **timing mechanism** changed from `delayMicroseconds()` to `micros()`. The math, step sizes, and pin assignments are identical to the originals.
