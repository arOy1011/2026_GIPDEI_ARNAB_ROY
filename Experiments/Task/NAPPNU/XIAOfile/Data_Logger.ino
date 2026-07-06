#include <Wire.h>
#include <LSM6DS3.h>
#include <RtcDS3231.h>
#include <SdFat.h>
#include <bluefruit.h>
#include <nrf_soc.h>
#include <nrf_gpio.h>
#define BUTTON_PIN D3
/* Optional status LED on D0. If you want to disable it entirely, you can
   just comment out this block and the related calls in setup(), loop(),
   and enterDeepSleep(). */
// #define STATUS_LED_PIN D0
#define SD_CS D7

/*
  Data Logger sketch (brief):
  - Samples IMU at `SAMPLE_INTERVAL` and timestamps with DS3231 RTC.
  - Logs CSV files to SD card (one file per day: LOG_YYYY_MM_DD.CSV).
  - Exposes BLE commands for START/STOP, STATUS, LIST, DELETE (D:<n>) and
    GET (G:<n>) to transfer files using a simple BEGIN/END protocol.
  - Single button on `BUTTON_PIN` supports: single press (start/stop),
    double press (BLE advertise toggle), long press (>LONG_PRESS_TIME) to
    enter deep sleep. `STATUS_LED_PIN` shows logging/advertising state.
*/

/* RTC */
RtcDS3231<TwoWire> rtc(Wire);

/* IMU */
LSM6DS3 imu(I2C_MODE, 0x6A);

/* SD */
SdFat sd;
File32 logFile;

/* BLUETOOTH */
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

/* Logging */
bool logging = false;
bool lastButtonState = HIGH;
unsigned long lastSampleTime = 0;
const unsigned long SAMPLE_INTERVAL = 100; /* 10 Hz */

unsigned long pressStartTime = 0;
bool longPressActive = false;
const unsigned long LONG_PRESS_TIME = 1500;

/* Status LED state kept here only if the LED block is enabled. */
// unsigned long lastStatusBlink = 0;
// bool statusLedOn = false;

/* -------------------------------------------------- */
/* SESSION MANAGEMENT */
/* -------------------------------------------------- */

/* GLOBAL VARIABLES */
uint8_t currentDay = 0;
uint8_t currentMonth = 0;
uint16_t currentYear = 0;
volatile bool cancelTransfer = false;
bool bleEnabled = false;

char listedFiles[100][64];
uint8_t listedFileCount = 0;

unsigned long lastPressTime = 0;
uint8_t pressCount = 0;
unsigned long advertiseStartTime = 0;

/*
  startLogging()
  - Ensure SD card is initialized, open a dated CSV (LOG_YYYY_MM_DD.CSV),
    write header if new, and mark `logging=true`.
*/
void startLogging() {

  /* Re-initialize SD card (may have been unmounted) */
  if (!sd.begin(SD_CS)) {
    Serial.println("SD NOT FOUND");
    return;
  }
  /* Get current date */
  RtcDateTime now = rtc.GetDateTime();
  currentDay   = now.Day();
  currentMonth = now.Month();
  currentYear  = now.Year();
  /* Create filename based on date */
  char filename[32];
  sprintf(filename,
          "LOG_%04u_%02u_%02u.CSV",
          now.Year(),
          now.Month(),
          now.Day());
  bool fileExists = sd.exists(filename);
  /* Open file */
  logFile = sd.open(filename, O_RDWR | O_CREAT);
  if (!logFile) {
    Serial.println("FILE OPEN FAILED");
    return;
  }
  /* Move to end for appending */
  logFile.seekEnd();
  /* Write header only if file is new */
  if (!fileExists) {
    logFile.println("Date,Time,Millis,Ax,Ay,Az,Gx,Gy,Gz");
  }
  /* Optional session marker */
  logFile.println("# SESSION START");
  logFile.flush();
  logging = true;
  Serial.print("Logging to: ");
  Serial.println(filename);
}
/*
  stopLogging()
  - Write a session stop marker, flush buffers and close the file.
*/
void stopLogging() {
  if (logFile) {
    logFile.println("# SESSION STOP");
    logFile.flush();
    logFile.close();
  }
  logging = false;
  Serial.println("Logging Stopped");
}
/*
  checkForNewDay()
  - When logging, detect calendar day rollover and rotate to a new file.
*/
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
  }
}
  /* callback */
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
  if (strcmp(cmd, "START") == 0) /* START */
  {
    if (!logging)
      startLogging();
  }
  else if (strcmp(cmd, "STOP") == 0) /* STOP */
  {
    if (logging)
      stopLogging();
  }
  else if (strcmp(cmd, "STATUS") == 0) /* STATUS */
  {
    if (logging)
    {
      Serial.println("STATUS = LOGGING");
      fileChar.notify("LOGGING");
    }
    else
    {
      Serial.println("STATUS = STOPPED");
      fileChar.notify("STOPPED");
    }
  }
  else if (strcmp(cmd, "LIST") == 0) /* LIST */
  {
    /* LIST: enumerate CSV files on the root and notify each filename
       over `fileChar`. Client expects an "EOF" notification at the end. */
    Serial.println("LIST REQUEST");

    File32 dir;
    dir.open("/");
    listedFileCount = 0;

    File32 entry;

    while (entry.openNext(&dir, O_RDONLY))
    {
        char filename[64];
        entry.getName(filename, sizeof(filename));

        if (strstr(filename, ".CSV") != NULL)
        {
            if (listedFileCount < 100)
            {
                strcpy(listedFiles[listedFileCount], filename);
                listedFileCount++;
            }
            Serial.println(filename);
            fileChar.notify(filename);
            delay(2);
        }
        entry.close();
    }
    fileChar.notify("EOF");
    dir.close();
}
  else if (strncmp(cmd, "D:", 2) == 0) /* DELETE */
{
    int index = atoi(cmd + 2);

    Serial.print("DELETE INDEX: ");
    Serial.println(index);

    /* Prevent deletion while logging to avoid corrupting active file */
    if (logging)
    {
      fileChar.notify("DELETE_DENIED_LOGGING");
      return;
    }

    if (index < 0 || index >= listedFileCount)
    {
        fileChar.notify("DELETE_FAILED");
        return;
    }

    if (sd.remove(listedFiles[index]))
    {
        fileChar.notify("DELETE_OK");
        Serial.println("DELETE SUCCESS");
    }
    else
    {
        fileChar.notify("DELETE_FAILED");
        Serial.println("DELETE FAILED");
    }
}
  else if (strncmp(cmd, "G:", 2) == 0) /* GET */
{
    cancelTransfer = false;

    int index = atoi(cmd + 2);

    Serial.print("GET INDEX: ");
    Serial.println(index);

    if (index < 0 || index >= listedFileCount)
    {
        fileChar.notify("ERROR:FILE_NOT_FOUND");
        return;
    }

    Serial.print("REQUESTED FILE: ");
    Serial.println(listedFiles[index]);

    File32 file = sd.open(listedFiles[index], O_RDONLY);

    if (!file)
    {
        fileChar.notify("ERROR:FILE_NOT_FOUND");

        Serial.println("FILE NOT FOUND");
        return;
    }
    uint32_t fileSize = file.fileSize();

    /* File transfer protocol:
       1) Send a single-line header "BEGIN:<filesize>" so client can prepare.
       2) Stream raw binary chunks (up to `fileChar` max length).
       3) Send an "END" notification to mark completion.
       If `cancelTransfer` becomes true, send "END" and abort. */
    char beginMsg[32];
    sprintf(beginMsg, "BEGIN:%lu", fileSize);
    while (Bluefruit.connected() && !fileChar.notify(beginMsg)) {
      delay(2);
      yield();
    }

    delay(5);

    uint8_t buffer[244];
    uint32_t bytesSent = 0;

    while (file.available())
    {
      /* honor transfer cancel request (set via BLE command) */
      if (cancelTransfer)
      {
        Serial.println("TRANSFER TERMINATED");
        file.close();
        fileChar.notify("END");
        return;
      }

        int n = file.read(buffer, sizeof(buffer));

        if (n > 0)
        {
            while (Bluefruit.connected() && !fileChar.notify(buffer, n))
            {
                delay(2);
                yield();
            }

            bytesSent += n;

            if (bytesSent % 4096 < (uint32_t)n)
            {
                Serial.print("SENT BYTES: ");
                Serial.println(bytesSent);
            }

            delay(1);
            yield();
        }
    }

    file.close();
    delay(20);

    while (Bluefruit.connected() && !fileChar.notify("END"))
    {
        delay(2);
        yield();
    }

    Serial.print("BYTES SENT = ");
    Serial.println(bytesSent);

    Serial.println("FILE SENT");
}
}
/* BLE setup */
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

/*
void updateStatusLed()
  {
      if (logging)
      {
          digitalWrite(STATUS_LED_PIN, HIGH);
      }
      else if (bleEnabled)
      {
          if (millis() - lastStatusBlink >= 500)
          {
              lastStatusBlink = millis();
              statusLedOn = !statusLedOn;
          }
          digitalWrite(STATUS_LED_PIN, statusLedOn ? HIGH : LOW);
      }
      else
      {
          digitalWrite(STATUS_LED_PIN, LOW);
      }
  }
*/

void enterDeepSleep()
  {
      Serial.println("ENTERING DEEP SLEEP");
      stopBLE();
      if (logging)
      {
          stopLogging();
      }
      /* digitalWrite(STATUS_LED_PIN, LOW); */
      digitalWrite(LED_BUILTIN, LOW);
      pinMode(BUTTON_PIN, INPUT_PULLUP);
      /* Configure wake-on-pin for system-off: convert Arduino pin to MCU pin
        and enable sense for LOW (button to GND). Ensure button wiring
        pulls the pin to GND when pressed. */
      nrf_gpio_cfg_sense_input(digitalPinToPinName(BUTTON_PIN), NRF_GPIO_PIN_PULLUP, NRF_GPIO_PIN_SENSE_LOW);
      delay(10);
      /* Enter system-off deep sleep. Device continues to consume minimal
        power and will wake only from the configured sense input. */
      sd_power_system_off();
      while (1);
  }
/*-------------------------------------------------
  SETUP
  --------------------------------------------------*/
void setup()
  {
    Serial.begin(115200);
    pinMode(BUTTON_PIN, INPUT_PULLUP);
    /* pinMode(STATUS_LED_PIN, OUTPUT); */
    pinMode(LED_BUILTIN, OUTPUT);
    /* digitalWrite(STATUS_LED_PIN, LOW); */
    digitalWrite(LED_BUILTIN, LOW);

     /* RTC: force I2C pins to match wiring (SDA=D2, SCL=D1).
       Some nRF52 cores use different default Wire pins; setting pins
       explicitly avoids I2C communication issues with the DS3231. */
     Wire.setPins(D2, D1);
     Wire.begin();
     rtc.Begin();

    if (!rtc.IsDateTimeValid())
    {
      Serial.println("RTC INVALID - SETTING BUILD TIME");
      rtc.SetDateTime(RtcDateTime(__DATE__, __TIME__));
    }

    if (!rtc.GetIsRunning())
    {
      Serial.println("RTC STOPPED - STARTING RTC");
      rtc.SetIsRunning(true);
    }

    RtcDateTime compiled(__DATE__, __TIME__);
    RtcDateTime now = rtc.GetDateTime();

    if (now < compiled)
    {
      Serial.println("RTC OLDER THAN BUILD TIME - UPDATING");
      rtc.SetDateTime(compiled);
    }

    now = rtc.GetDateTime();
    Serial.print("RTC TIME: ");
    Serial.print(now.Year());
    Serial.print("-");
    Serial.print(now.Month());
    Serial.print("-");
    Serial.print(now.Day());
    Serial.print(" ");
    Serial.print(now.Hour());
    Serial.print(":");
    Serial.print(now.Minute());
    Serial.print(":");
    Serial.println(now.Second());

    /* IMU */
    if (imu.begin() != 0)
    {
      Serial.println("IMU FAIL");
      while (1);
    }

    /* SD */
    if (!sd.begin(SD_CS))
    {
      Serial.println("SD FAIL");
      while (1);
    }

    /* BLE STACK ONLY */
    Bluefruit.configPrphBandwidth(BANDWIDTH_MAX);
    Bluefruit.begin();
    Bluefruit.Periph.setConnInterval(6, 6);
    Bluefruit.setTxPower(4);
    Bluefruit.setName("MotionLogger");
    motionService.begin();

    /* IMU CHARACTERISTIC */
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

    /* COMMAND CHARACTERISTIC */
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

    /* FILE CHARACTERISTIC */
    fileChar.setProperties(
      CHR_PROPS_NOTIFY |
      CHR_PROPS_READ
    );

    fileChar.setPermission(
      SECMODE_OPEN,
      SECMODE_NO_ACCESS
    );

    fileChar.setMaxLen(244);

    fileChar.begin();

    /* Configure advertising */
    Bluefruit.Advertising.addFlags(
      BLE_GAP_ADV_FLAGS_LE_ONLY_GENERAL_DISC_MODE
    );

    Bluefruit.Advertising.addService(
      motionService
    );

    Bluefruit.Advertising.addName();

    /* IMPORTANT */
    Bluefruit.Advertising.stop();

    Serial.println("READY");
    Serial.println("BLE OFF");
  }
/* -------------------------------------------------- */
/* LOOP */
/* -------------------------------------------------- */
void loop() {
  checkForNewDay();

  /* BUTTON HANDLING
    - Single press: toggle logging (start/stop)
    - Double press (two presses within 500ms): toggle BLE advertising
    - Long press (> LONG_PRESS_TIME): enter deep sleep
    The code measures press timing and counts presses to distinguish actions. */
  bool buttonState = digitalRead(BUTTON_PIN);
  if (lastButtonState == HIGH &&
      buttonState == LOW)
  {
    pressStartTime = millis();
  }

  if (buttonState == LOW &&
      !longPressActive &&
      millis() - pressStartTime >= LONG_PRESS_TIME)
  {
    longPressActive = true;
    enterDeepSleep();
  }

  if (lastButtonState == LOW &&
      buttonState == HIGH)
  {
    if (!longPressActive)
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
    longPressActive = false;
  }
  lastButtonState = buttonState;

  /* Process press sequence */
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

  /* Status LED updates are disabled. If you want them back, uncomment the
     updateStatusLed() function and the related calls. */

  /* 10 Hz Logging */
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

    /* BLE LIVE STREAM */
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
      /* Date */
      logFile.print(now.Year());
      logFile.print("-");
      if (now.Month() < 10) logFile.print("0");
      logFile.print(now.Month());
      logFile.print("-");
      if (now.Day() < 10) logFile.print("0");
      logFile.print(now.Day());
      logFile.print(",");
      /* Time */
      if (now.Hour() < 10) logFile.print("0");
      logFile.print(now.Hour());
      logFile.print(":");
      if (now.Minute() < 10) logFile.print("0");
      logFile.print(now.Minute());
      logFile.print(":");
      if (now.Second() < 10) logFile.print("0");
      logFile.print(now.Second());
      logFile.print(",");
      /* millis */
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
      /* Write to card periodically */
      static uint32_t flushCounter = 0;
      flushCounter++;
      if (flushCounter >= 50) { /* every ~5 seconds */
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