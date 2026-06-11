#include <Wire.h>
#include <LSM6DS3.h>
#include <ThreeWire.h>
#include <RtcDS1302.h>
#include <SdFat.h>
#define BUTTON_PIN D3
#define SD_CS D7
// RTC
ThreeWire myWire(D1, D2, D0);   // DAT, CLK, RST
RtcDS1302<ThreeWire> rtc(myWire);
// IMU
LSM6DS3 imu(I2C_MODE, 0x6A);
// SD
SdFat sd;
File32 logFile;
// Logging
bool logging = false;
bool lastButtonState = HIGH;
unsigned long lastSampleTime = 0;
const unsigned long SAMPLE_INTERVAL = 100; // 10 Hz
// --------------------------------------------------
// INDEX.TXT
// --------------------------------------------------
uint16_t loadIndex() {
  uint16_t idx = 0;
  if (sd.exists("INDEX.TXT")) {
    File32 f = sd.open("INDEX.TXT", O_RDONLY);
    if (f) {
      idx = f.parseInt();
      f.close();
    }
  }
  return idx;
}
void saveIndex(uint16_t idx) {
  sd.remove("INDEX.TXT");
  File32 f = sd.open("INDEX.TXT", O_RDWR | O_CREAT);
  if (f) {
    f.println(idx);
    f.close();
  }
}
// --------------------------------------------------
// SESSION MANAGEMENT
// --------------------------------------------------
// GLOBAL VARIABLES
uint8_t currentDay = 0;
uint8_t currentMonth = 0;
uint16_t currentYear = 0;

void startLogging() {
  // Re-initialize SD card
  if (!sd.begin(SD_CS)) {
    Serial.println("SD NOT FOUND");
    return;
  }
  uint16_t idx = loadIndex();
  idx = idx % 120;
  char filename[20];
  sprintf(filename, "LOG%03u.CSV", idx);
  sd.remove(filename);
  logFile = sd.open(filename, O_RDWR | O_CREAT);
  if (!logFile) {
    Serial.println("FILE CREATE FAILED");
    return;
  }
  logFile.println("Date,Time,Millis,Ax,Ay,Az,Gx,Gy,Gz");
  saveIndex((idx + 1) % 120);
  logging = true;
  RtcDateTime now = rtc.GetDateTime();
  currentDay = now.Day();
  currentMonth = now.Month();
  currentYear = now.Year();
  Serial.print("Started: ");
  Serial.println(filename);
}
void stopLogging() {
  if (logFile) {
    logFile.flush();
    logFile.close();
  }
  logging = false;
  Serial.println("Logging Stopped");
}
void checkForNewDay() {
  if (!logging)
    return;
  RtcDateTime now = rtc.GetDateTime();
  if (now.Day() != currentDay ||
      now.Month() != currentMonth ||
      now.Year() != currentYear) {
    Serial.println("NEW DAY DETECTED");
    stopLogging();
    delay(100);
    startLogging();
  }
}
// --------------------------------------------------
// SETUP
// --------------------------------------------------
void setup() {
  Serial.begin(115200);
  pinMode(BUTTON_PIN, INPUT_PULLUP);
  // RTC
  rtc.Begin();
  if (!rtc.GetIsRunning()) {
    rtc.SetIsRunning(true);
  }
  // IMU
  if (imu.begin() != 0) {
    Serial.println("IMU FAIL");
    while (1);
  }
  // SD
  if (!sd.begin(SD_CS)) {
    Serial.println("SD FAIL");
    while (1);
  }
  Serial.println("READY");
}
// --------------------------------------------------
// LOOP
// --------------------------------------------------
void loop() {
  checkForNewDay();
  // Button Toggle
  bool buttonState = digitalRead(BUTTON_PIN);
  if (lastButtonState == HIGH &&
      buttonState == LOW) {
    delay(50);
    if (!logging)
      startLogging();
    else
      stopLogging();
  }
  lastButtonState = buttonState;
  // 10 Hz Logging
  if (logging &&
      millis() - lastSampleTime >= SAMPLE_INTERVAL) {
    lastSampleTime = millis();
    RtcDateTime now = rtc.GetDateTime();
    float ax = imu.readFloatAccelX();
    float ay = imu.readFloatAccelY();
    float az = imu.readFloatAccelZ();
    float gx = imu.readFloatGyroX();
    float gy = imu.readFloatGyroY();
    float gz = imu.readFloatGyroZ();
    if (logFile) {
      // Date
      logFile.print(now.Year());
      logFile.print("-");
      if (now.Month() < 10) logFile.print("0");
      logFile.print(now.Month());
      logFile.print("-");
      if (now.Day() < 10) logFile.print("0");
      logFile.print(now.Day());
      logFile.print(",");
      // Time
      if (now.Hour() < 10) logFile.print("0");
      logFile.print(now.Hour());
      logFile.print(":");
      if (now.Minute() < 10) logFile.print("0");
      logFile.print(now.Minute());
      logFile.print(":");
      if (now.Second() < 10) logFile.print("0");
      logFile.print(now.Second());
      logFile.print(",");
      // millis
      logFile.print(millis());
      logFile.print(",");
      logFile.print(ax, 4);
      logFile.print(",");
      logFile.print(ay, 4);
      logFile.print(",");
      logFile.print(az, 4);
      logFile.print(",");
      logFile.print(gx, 4);
      logFile.print(",");
      logFile.print(gy, 4);
      logFile.print(",");
      logFile.println(gz, 4);
      // Write to card periodically
      static uint32_t flushCounter = 0;
      flushCounter++;
      if (flushCounter >= 50) { // every ~5 seconds
        logFile.flush();
        flushCounter = 0;
      }
    }
  }
}