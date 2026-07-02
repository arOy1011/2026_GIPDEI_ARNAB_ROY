#include <Wire.h>
#include <LSM6DS3.h>
#include <ThreeWire.h>
#include <RtcDS1302.h>
#include <SdFat.h>
#include <bluefruit.h>
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

// BLUETOOTH
BLEService motionService(
"12345678-1234-1234-1234-1234567890AB"
);
BLECharacteristic imuChar(
"12345678-1234-1234-1234-1234567890AC"
);
BLECharacteristic cmdChar(
"12345678-1234-1234-1234-1234567890AE"
);
BLECharacteristic fileChar(
"12345678-1234-1234-1234-1234567890AD"
);

// Logging
bool logging = false;
bool lastButtonState = HIGH;
unsigned long lastSampleTime = 0;
const unsigned long SAMPLE_INTERVAL = 100; // 10 Hz

// --------------------------------------------------
// SESSION MANAGEMENT
// --------------------------------------------------

// GLOBAL VARIABLES
uint8_t currentDay = 0;
uint8_t currentMonth = 0;
uint16_t currentYear = 0;
volatile bool cancelTransfer = false;
bool bleEnabled = false;

unsigned long lastPressTime = 0;
uint8_t pressCount = 0;
unsigned long advertiseStartTime = 0;

// LOGGING
void startLogging() {

  // Re-initialize SD card
  if (!sd.begin(SD_CS)) {
    Serial.println("SD NOT FOUND");
    return;
  }
  // Get current date
  RtcDateTime now = rtc.GetDateTime();
  currentDay   = now.Day();
  currentMonth = now.Month();
  currentYear  = now.Year();
  // Create filename based on date
  char filename[32];
  sprintf(filename,
          "LOG_%04u_%02u_%02u.CSV",
          now.Year(),
          now.Month(),
          now.Day());
  bool fileExists = sd.exists(filename);
  // Open file
  logFile = sd.open(filename, O_RDWR | O_CREAT);
  if (!logFile) {
    Serial.println("FILE OPEN FAILED");
    return;
  }
  // Move to end for appending
  logFile.seekEnd();
  // Write header only if file is new
  if (!fileExists) {
    logFile.println("Date,Time,Millis,Ax,Ay,Az,Gx,Gy,Gz");
  }
  // Optional session marker
  logFile.println("# SESSION START");
  logFile.flush();
  logging = true;
  Serial.print("Logging to: ");
  Serial.println(filename);
}
void stopLogging() {
  if (logFile) {
    logFile.println("# SESSION STOP");
    logFile.flush();
    logFile.close();
  }
  logging = false;
  Serial.println("Logging Stopped");
}
// NEW DAY CHECK
void checkForNewDay() {
  if (!logging)
    return;
  RtcDateTime now = rtc.GetDateTime();
  if (now.Day() != currentDay ||
      now.Month() != currentMonth ||
      now.Year() != currentYear) {
    Serial.println("NEW DAY DETECTED");
    if (logFile) {
      logFile.flush();
      logFile.close();
    }
    logging = false;
    delay(100);
    startLogging();
  }}
  // callback
void commandCallback(uint16_t conn_hdl,
                     BLECharacteristic* chr,
                     uint8_t* data,
                     uint16_t len)
  {
  Serial.println("CALLBACK FIRED");
  char cmd[65];
  memcpy(cmd, data, len);
  cmd[len] = '\0';
  Serial.print("CMD: ");
  Serial.println(cmd);
  if (strcmp(cmd, "START") == 0) // START
  {
    if (!logging)
      startLogging();
  }
  else if (strcmp(cmd, "STOP") == 0) // STOP
  {
    if (logging)
      stopLogging();
  }
  else if (strcmp(cmd, "STATUS") == 0) // STATUS
  {
    if (logging)
    {
      Serial.println("STATUS = LOGGING");
      fileChar.write("LOGGING");
      fileChar.notify("LOGGING");
    }
    else
    {
      Serial.println("STATUS = STOPPED");
      fileChar.write("STOPPED");
      fileChar.notify("STOPPED");
    }
  }
  else if (strcmp(cmd, "LIST") == 0) // LIST
  {
    Serial.println("LIST REQUEST");
    File32 dir;
    dir.open("/");
    File32 entry;
    while (entry.openNext(&dir, O_RDONLY))
    {
      char filename[64];
      entry.getName(filename, sizeof(filename));
    if (strstr(filename, ".CSV") != NULL)
    {
        Serial.println(filename);

        fileChar.write(filename);
        fileChar.notify(filename);

        delay(100);
    }
      delay(100);
      entry.close();
    }
    fileChar.write("EOF");
    fileChar.notify("EOF");
    dir.close();
  }
  else if (strncmp(cmd, "DELETE:", 7) == 0) // DELETE
{
    char* filename = cmd + 7;

    Serial.print("DELETE REQUEST: ");
    Serial.println(filename);

    // Prevent deleting while logging
    if (logging)
    {
        fileChar.write("DELETE_DENIED_LOGGING");
        fileChar.notify("DELETE_DENIED_LOGGING");

        Serial.println("DELETE DENIED: LOGGING ACTIVE");
        return;
    }

    if (sd.remove(filename))
    {
        fileChar.write("DELETE_OK");
        fileChar.notify("DELETE_OK");

        Serial.println("DELETE SUCCESS");
    }
    else
    {
        fileChar.write("DELETE_FAILED");
        fileChar.notify("DELETE_FAILED");

        Serial.println("DELETE FAILED");
    }
}
  else if (strncmp(cmd, "GET:", 4) == 0) // GET
  {
    cancelTransfer = false;
    char* filename = cmd + 4;
    Serial.print("GET REQUEST: ");
    Serial.println(filename);
    File32 file = sd.open(filename, O_RDONLY);
    if (!file)
    {
      fileChar.write("ERROR:FILE_NOT_FOUND");
      fileChar.notify("ERROR:FILE_NOT_FOUND");
      Serial.println("FILE NOT FOUND");
      return;
    }
    char line[180];
    uint32_t linesSent = 0;
    while (file.available())
  {
    if (cancelTransfer)
    {
        Serial.println("TRANSFER TERMINATED");
        file.close();
        fileChar.write("TRANSFER_TERMINATED");
        fileChar.notify("TRANSFER_TERMINATED");
        return;
    }
    int n = file.fgets(line, sizeof(line));
    if (n > 0)
    {
        line[strcspn(line, "\r\n")] = '\0';
        Serial.println(line);
        fileChar.write(line);
        fileChar.notify(line);
        linesSent++;
        delay(100);
    }
  }
    file.close();
    Serial.print("LINES SENT = ");
    Serial.println(linesSent);  
    fileChar.write("EOF");
    fileChar.notify("EOF");
    Serial.println("FILE SENT");
  }
}
// BLE setup
void startBLE()
  {
    if (bleEnabled)
      return;
    Bluefruit.Advertising.start(0);
    advertiseStartTime = millis();
    bleEnabled = true;
    Serial.println("BLE ADVERTISING");
  }
void stopBLE()
  {
      if (Bluefruit.connected())
      {
          Bluefruit.disconnect(0);
      }
      Bluefruit.Advertising.stop();
      advertiseStartTime = 0;
      bleEnabled = false;
      Serial.println("BLE OFF");
  }
//-------------------------------------------------
// SETUP
// --------------------------------------------------
void setup()
  {
    Serial.begin(115200);
    pinMode(BUTTON_PIN, INPUT_PULLUP);

    // RTC
    rtc.Begin();

    if (!rtc.GetIsRunning())
    {
      rtc.SetIsRunning(true);
    }

    // IMU
    if (imu.begin() != 0)
    {
      Serial.println("IMU FAIL");
      while (1);
    }

    // SD
    if (!sd.begin(SD_CS))
    {
      Serial.println("SD FAIL");
      while (1);
    }

    // BLE STACK ONLY
    Bluefruit.begin();
    Bluefruit.setTxPower(4);
    Bluefruit.setName("MotionLogger");
    motionService.begin();

    // IMU CHARACTERISTIC
    imuChar.setProperties(
      CHR_PROPS_NOTIFY |
      CHR_PROPS_READ
    );
    imuChar.setPermission(
      SECMODE_OPEN,
      SECMODE_NO_ACCESS
    );

    imuChar.setMaxLen(80);
    imuChar.begin();

    // COMMAND CHARACTERISTIC
    cmdChar.setProperties(
      CHR_PROPS_WRITE |
      CHR_PROPS_WRITE_WO_RESP
    );
    cmdChar.setPermission(
      SECMODE_OPEN,
      SECMODE_OPEN
    );
    cmdChar.setMaxLen(64);
    cmdChar.setWriteCallback(
      commandCallback
    );
    cmdChar.begin();

    // FILE CHARACTERISTIC
    fileChar.setProperties(
      CHR_PROPS_NOTIFY |
      CHR_PROPS_READ
    );

    fileChar.setPermission(
      SECMODE_OPEN,
      SECMODE_NO_ACCESS
    );

    fileChar.setMaxLen(200);

    fileChar.begin();

    // Configure advertising
    Bluefruit.Advertising.addFlags(
      BLE_GAP_ADV_FLAGS_LE_ONLY_GENERAL_DISC_MODE
    );

    Bluefruit.Advertising.addService(
      motionService
    );

    Bluefruit.Advertising.addName();

    // IMPORTANT
    Bluefruit.Advertising.stop();

    Serial.println("READY");
    Serial.println("BLE OFF");
  }
// --------------------------------------------------
// LOOP
// --------------------------------------------------
void loop() {
  checkForNewDay();

  // BUTTON HANDLING
  bool buttonState = digitalRead(BUTTON_PIN);
  if (lastButtonState == HIGH &&
      buttonState == LOW)
  {
    unsigned long now = millis();
    if (now - lastPressTime < 500)
    {
      pressCount++;
    }
    else
    {
      pressCount = 1;
    }
    lastPressTime = now;
  }
  lastButtonState = buttonState;
  // Process press sequence
  if (pressCount > 0 &&
      millis() - lastPressTime > 500)
  {
    if (pressCount == 1)
    {
      if (!logging)
        startLogging();
      else
        stopLogging();
    }
    else if (pressCount == 2)
    {
      if (!bleEnabled)
      {
          startBLE();
      }
      else
      {
          stopBLE();
      }
    }
    pressCount = 0;
  }

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

    // BLE LIVE STREAM
    char bleData[80];
    snprintf(
      bleData,
      sizeof(bleData),
      "%.2f,%.2f,%.2f,%.2f,%.2f,%.2f",
      ax, ay, az,
      gx, gy, gz
    );
    static unsigned long lastBleTime = 0;
    if (Bluefruit.connected() &&
        millis() - lastBleTime >= 200) {
      lastBleTime = millis();
      imuChar.write(bleData);
      imuChar.notify(bleData);
    }
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
  if (bleEnabled &&
    !Bluefruit.connected() &&
    millis() - advertiseStartTime > 30000)
  {
      stopBLE();
  }
}