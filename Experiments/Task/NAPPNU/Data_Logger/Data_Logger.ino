// Include the I2C communication library.
#include <Wire.h>

// Include the onboard LSM6DS3 IMU driver.
#include <LSM6DS3.h>

// Include the DS3231 Real-Time Clock library.
#include <RtcDS3231.h>

// Include the SD card filesystem library.
#include <SdFat.h>

// Include the Bluetooth Low Energy library.
#include <bluefruit.h>

// Include Nordic SoftDevice power management functions.
#include <nrf_soc.h>

// Include Nordic GPIO configuration functions.
#include <nrf_gpio.h>

// Define the user push-button pin.
#define BUTTON_PIN D3

/* Optional status LED on D0. If you want to disable it entirely, you can
   just comment out this block and the related calls in setup(), loop(),
   and enterDeepSleep(). */
// #define STATUS_LED_PIN D0

// Define the SD card Chip Select (CS) pin.
#define SD_CS D7

/*
  Data Logger sketch (brief):
  ...
*/

// Create the DS3231 Real-Time Clock object.
RtcDS3231<TwoWire> rtc(Wire);

// Create the onboard LSM6DS3 IMU object.
LSM6DS3 imu(I2C_MODE, 0x6A);

// Create the SD card interface object.
SdFat sd;

// File handle for the active log file.
File32 logFile;

// Create the primary BLE service.
BLEService motionService("12345678-1234-1234-1234-1234567890AB");

// BLE characteristic used for live IMU data.
BLECharacteristic imuChar("12345678-1234-1234-1234-1234567890AC");

// BLE characteristic used to receive commands from the mobile application.
BLECharacteristic cmdChar("12345678-1234-1234-1234-1234567890AE");

// BLE characteristic used for file transfer.
BLECharacteristic fileChar("12345678-1234-1234-1234-1234567890AD");

// Indicates whether data logging is currently active.
bool logging = false;

// Stores the previous button state.
bool lastButtonState = HIGH;

// Stores the timestamp of the previous sensor sample.
unsigned long lastSampleTime = 0;

// IMU sampling interval in milliseconds (10 Hz).
const unsigned long SAMPLE_INTERVAL = 100;

// Records when the current button press started.
unsigned long pressStartTime = 0;

// Prevents multiple detections of the same long press.
bool longPressActive = false;

// Duration required to trigger deep sleep.
const unsigned long LONG_PRESS_TIME = 1500;

/* Status LED state kept here only if the LED block is enabled. */
// unsigned long lastStatusBlink = 0;
// bool statusLedOn = false;

/* -------------------------------------------------- */
/* SESSION MANAGEMENT */
/* -------------------------------------------------- */

// Stores the current logging day.
uint8_t currentDay = 0;

// Stores the current logging month.
uint8_t currentMonth = 0;

// Stores the current logging year.
uint16_t currentYear = 0;

// Indicates whether an active file transfer should be cancelled.
volatile bool cancelTransfer = false;

// Indicates whether BLE advertising is currently enabled.
bool bleEnabled = false;

// Stores filenames returned during the LIST command.
char listedFiles[100][64];

// Number of valid filenames stored in listedFiles[].
uint8_t listedFileCount = 0;

// Timestamp of the previous button release.
unsigned long lastPressTime = 0;

// Counts button presses for single/double-click detection.
uint8_t pressCount = 0;

// Records when BLE advertising started.
unsigned long advertiseStartTime = 0;

// Prevents false button events immediately after boot.
bool waitForButtonRelease = true;

/*
  startLogging()
  ...
*/
void startLogging() {

  // Initialize the SD card before accessing the filesystem.
  if (!sd.begin(SD_CS)) {
    Serial.println("SD NOT FOUND");   // Report SD initialization failure.
    return;                           // Abort logging.
  }

  // Read the current date and time from the RTC.
  RtcDateTime now = rtc.GetDateTime();

  // Store the current date for day rollover detection.
  currentDay   = now.Day();
  currentMonth = now.Month();
  currentYear  = now.Year();

  // Buffer used to generate the daily log filename.
  char filename[32];

  // Generate the filename in LOG_YYYY_MM_DD.CSV format.
  sprintf(filename,
          "LOG_%04u_%02u_%02u.CSV",
          now.Year(),
          now.Month(),
          now.Day());

  // Check whether today's log file already exists.
  bool fileExists = sd.exists(filename);
    // Open the log file in read/write mode or create it if it does not exist.
  logFile = sd.open(filename, O_RDWR | O_CREAT);

  // Verify that the log file was opened successfully.
  if (!logFile) {

    // Report the file opening failure.
    Serial.println("FILE OPEN FAILED");

    // Exit the function if the file cannot be opened.
    return;
  }

  // Move the file pointer to the end of the file for appending new data.
  logFile.seekEnd();

  // Write the CSV header only when a new file is created.
  if (!fileExists) {

    // Store the column names for the logged sensor data.
    logFile.println("Date,Time,Millis,Ax,Ay,Az,Gx,Gy,Gz");
  }

  // Mark the beginning of a new logging session.
  logFile.println("# SESSION START");

  // Flush buffered data to the SD card immediately.
  logFile.flush();

  // Enable the logging state.
  logging = true;

  // Display the active log filename.
  Serial.print("Logging to: ");

  // Print the generated filename.
  Serial.println(filename);
}

/*
  stopLogging()
  - Closes the current logging session safely.
*/
void stopLogging() {

  // Check whether a log file is currently open.
  if (logFile) {

    // Mark the end of the current logging session.
    logFile.println("# SESSION STOP");

    // Write any buffered data to the SD card.
    logFile.flush();

    // Close the log file.
    logFile.close();
  }

  // Disable the logging state.
  logging = false;

  // Notify the user that logging has stopped.
  Serial.println("Logging Stopped");
}

/*
  checkForNewDay()
  - Detects a calendar day change and creates a new daily log file.
*/
void checkForNewDay() {

  // Skip the check when logging is not active.
  if (!logging)
    return;

  // Read the current date from the RTC.
  RtcDateTime now = rtc.GetDateTime();

  // Check whether the calendar date has changed.
  if (now.Day() != currentDay ||
      now.Month() != currentMonth ||
      now.Year() != currentYear) {

    // Notify that a new day has been detected.
    Serial.println("NEW DAY DETECTED");

    // Close the current log file before creating a new one.
    if (logFile) {

      // Flush any pending data to the SD card.
      logFile.flush();

      // Close the existing log file.
      logFile.close();
    }

    // Temporarily disable logging during file rotation.
    logging = false;

    // Allow the SD card time to complete pending operations.
    delay(100);

    // Create and open a new log file for the new day.
    startLogging();
  }
}

/* BLE command callback */
void commandCallback(uint16_t conn_hdl,
                     BLECharacteristic* chr,
                     uint8_t* data,
                     uint16_t len)
{
  // Indicate that a BLE command has been received.
  Serial.println("CALLBACK FIRED");

  // Buffer used to store the received command string.
  char cmd[65];

  // Copy the received BLE payload into the local buffer.
  memcpy(cmd, data, len);

  // Append a null terminator to form a valid C-string.
  cmd[len] = '\0';

  // Print the received command.
  Serial.print("CMD: ");

  // Display the command contents.
  Serial.println(cmd);

  // Handle the START command.
  if (strcmp(cmd, "START") == 0)
  {
    // Start logging only if it is currently stopped.
    if (!logging)
      startLogging();
  }

  // Handle the STOP command.
  else if (strcmp(cmd, "STOP") == 0)
  {
    // Stop logging only if it is currently active.
    if (logging)
      stopLogging();
  }

  // Handle the STATUS command.
  else if (strcmp(cmd, "STATUS") == 0)
  {
    // Check the current logging state.
    if (logging)
    {
      // Report the logging status over Serial.
      Serial.println("STATUS = LOGGING");

      // Notify the BLE client that logging is active.
      fileChar.notify("LOGGING");
    }
    else
    {
      // Report the stopped status over Serial.
      Serial.println("STATUS = STOPPED");

      // Notify the BLE client that logging is stopped.
      fileChar.notify("STOPPED");
    }
  }

  // Handle the LIST command.
  else if (strcmp(cmd, "LIST") == 0)
  {
    // Indicate that a file listing has been requested.
    Serial.println("LIST REQUEST");

    // Open the root directory of the SD card.
    File32 dir;

    // Access the root directory.
    dir.open("/");

    // Reset the stored filename count.
    listedFileCount = 0;

    // File object used while iterating through directory entries.
    File32 entry;

    // Iterate through every file in the root directory.
    while (entry.openNext(&dir, O_RDONLY))
    {
        // Buffer used to store the current filename.
        char filename[64];

        // Retrieve the filename of the current directory entry.
        entry.getName(filename, sizeof(filename));

        // Process only CSV log files.
        if (strstr(filename, ".CSV") != NULL)
        {
            // Store the filename if space is available.
            if (listedFileCount < 100)
            {
                // Save the filename in the file list.
                strcpy(listedFiles[listedFileCount], filename);

                // Increment the number of stored files.
                listedFileCount++;
            }

            // Display the filename on the Serial Monitor.
            Serial.println(filename);

            // Send the filename to the BLE client.
            fileChar.notify(filename);

            // Short delay to improve BLE transmission reliability.
            delay(2);
        }

        // Close the current directory entry.
        entry.close();
    }

    // Notify the client that the file list has finished.
    fileChar.notify("EOF");

    // Close the root directory.
    dir.close();
}

/* Handle DELETE command */
else if (strncmp(cmd, "D:", 2) == 0)
{
    // Extract the requested file index.
    int index = atoi(cmd + 2);

    // Display the requested file index.
    Serial.print("DELETE INDEX: ");
    Serial.println(index);

    // Prevent deleting a file while logging is active.
    if (logging)
    {
      // Notify the client that deletion is denied.
      fileChar.notify("DELETE_DENIED_LOGGING");
      return;
    }

    // Validate the requested index.
    if (index < 0 || index >= listedFileCount)
    {
        // Notify the client that deletion failed.
        fileChar.notify("DELETE_FAILED");
        return;
    }

    // Attempt to remove the selected file.
    if (sd.remove(listedFiles[index]))
    {
        // Notify the client that deletion succeeded.
        fileChar.notify("DELETE_OK");

        // Print success message.
        Serial.println("DELETE SUCCESS");
    }
    else
    {
        // Notify the client that deletion failed.
        fileChar.notify("DELETE_FAILED");

        // Print failure message.
        Serial.println("DELETE FAILED");
    }
}

/* Handle GET command */
else if (strncmp(cmd, "G:", 2) == 0)
{
    // Clear any previous transfer cancellation request.
    cancelTransfer = false;

    // Extract the requested file index.
    int index = atoi(cmd + 2);

    // Display the requested file index.
    Serial.print("GET INDEX: ");
    Serial.println(index);

    // Validate the requested index.
    if (index < 0 || index >= listedFileCount)
    {
        // Notify the client that the file was not found.
        fileChar.notify("ERROR:FILE_NOT_FOUND");
        return;
    }

    // Display the selected filename.
    Serial.print("REQUESTED FILE: ");
    Serial.println(listedFiles[index]);

    // Open the requested file in read-only mode.
    File32 file = sd.open(listedFiles[index], O_RDONLY);

    // Verify that the file opened successfully.
    if (!file)
    {
        // Notify the client that the file was not found.
        fileChar.notify("ERROR:FILE_NOT_FOUND");

        // Print an error message.
        Serial.println("FILE NOT FOUND");
        return;
    }

    // Obtain the total file size.
    uint32_t fileSize = file.fileSize();

    // Buffer used for the BEGIN message.
    char beginMsg[32];

    // Create the transfer header containing the file size.
    sprintf(beginMsg, "BEGIN:%lu", fileSize);

    // Wait until the BEGIN message is transmitted.
    while (Bluefruit.connected() && !fileChar.notify(beginMsg)) {
      delay(2);
      yield();
    }

    // Allow the client to prepare for incoming data.
    delay(5);

    // Buffer used for BLE data transmission.
    uint8_t buffer[244];

    // Track the number of bytes transmitted.
    uint32_t bytesSent = 0;

    // Continue until the complete file has been read.
    while (file.available())
    {
      // Stop the transfer if cancellation was requested.
      if (cancelTransfer)
      {
        // Report transfer cancellation.
        Serial.println("TRANSFER TERMINATED");

        // Close the file.
        file.close();

        // Notify the client that the transfer has ended.
        fileChar.notify("END");
        return;
      }

        // Read the next data block from the file.
        int n = file.read(buffer, sizeof(buffer));

        // Transmit only valid data.
        if (n > 0)
        {
            // Retry until the BLE packet is accepted.
            while (Bluefruit.connected() && !fileChar.notify(buffer, n))
            {
                delay(2);
                yield();
            }

            // Update the transmitted byte count.
            bytesSent += n;

            // Print progress every 4096 bytes.
            if (bytesSent % 4096 < (uint32_t)n)
            {
                Serial.print("SENT BYTES: ");
                Serial.println(bytesSent);
            }

            // Small delay between BLE packets.
            delay(1);
            yield();
        }
    }

    // Close the transferred file.
    file.close();

    // Allow the final packets to complete transmission.
    delay(20);

    // Send the transfer completion message.
    while (Bluefruit.connected() && !fileChar.notify("END"))
    {
        delay(2);
        yield();
    }

    // Display the total bytes transmitted.
    Serial.print("BYTES SENT = ");
    Serial.println(bytesSent);

    // Indicate successful file transfer.
    Serial.println("FILE SENT");
}
}
/* BLE setup */

/* Start BLE advertising if it is currently disabled. */
void startBLE()
{
    // Exit if BLE advertising is already active.
    if (bleEnabled)
      return;

    // Start BLE advertising indefinitely.
    Bluefruit.Advertising.start(0);

    // Record the advertising start time.
    advertiseStartTime = millis();

    // Update the BLE state flag.
    bleEnabled = true;

    // Notify through Serial Monitor.
    Serial.println("BLE ADVERTISING");
}

/* Stop BLE advertising and disconnect any active client. */
void stopBLE()
{
      // Disconnect the connected BLE client.
      if (Bluefruit.connected())
      {
          Bluefruit.disconnect(0);
      }

      // Stop BLE advertising.
      Bluefruit.Advertising.stop();

      // Reset the advertising timer.
      advertiseStartTime = 0;

      // Update the BLE state flag.
      bleEnabled = false;

      // Notify through Serial Monitor.
      Serial.println("BLE OFF");
}

/* Enter low-power system-off mode. */
void enterDeepSleep()
{
      // Notify that deep sleep is being entered.
      Serial.println("ENTERING DEEP SLEEP");

      // Stop BLE before entering sleep.
      stopBLE();

      // Stop logging if it is currently active.
      if (logging)
      {
          stopLogging();
      }

      // Configure the button as an input with pull-up.
      pinMode(BUTTON_PIN, INPUT_PULLUP);

      // Wait until the button is released.
      while (digitalRead(BUTTON_PIN) == LOW)
      {
          delay(10);
      }

      // Debounce delay.
      delay(20);

      // Configure the button as the wake-up source.
      nrf_gpio_cfg_sense_input(
          digitalPinToPinName(BUTTON_PIN),
          NRF_GPIO_PIN_PULLUP,
          NRF_GPIO_PIN_SENSE_LOW);

      // Allow GPIO configuration to settle.
      delay(10);

      // Enter Nordic System OFF mode.
      sd_power_system_off();

      // Safety loop (normally never reached).
      while (1)
      {
          delay(1000);
      }
}
/*-------------------------------------------------
  SETUP
  --------------------------------------------------*/
void setup()
  {
    Serial.begin(115200);
    while (!Serial)
    {
      delay(10);
    }

    delay(500);
    Serial.println("BOOT");

    pinMode(BUTTON_PIN, INPUT_PULLUP);
    
    /* pinMode(STATUS_LED_PIN, OUTPUT); */
    /* digitalWrite(STATUS_LED_PIN, LOW); */

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

  // Ignore button events immediately after boot until the button is released.
  if (waitForButtonRelease)
  {
    // Check whether the button has been released.
    if (digitalRead(BUTTON_PIN) == HIGH)
    {
      // Enable normal button processing.
      waitForButtonRelease = false;
    }
    else
    {
      // Skip the current loop iteration while the button remains pressed.
      return;
    }
  }

  // Detect whether the calendar day has changed.
  checkForNewDay();

  /* BUTTON HANDLING
     - Single press : Start/Stop logging
     - Double press : Enable/Disable BLE advertising
     - Long press   : Enter deep sleep
  */

  // Read the current button state.
  bool buttonState = digitalRead(BUTTON_PIN);

  // Detect the beginning of a button press.
  if (lastButtonState == HIGH &&
      buttonState == LOW)
  {
    // Record the press start time.
    pressStartTime = millis();
  }

  // Detect a valid long press.
  if (buttonState == LOW &&
      !longPressActive &&
      millis() - pressStartTime >= LONG_PRESS_TIME)
  {
    // Prevent repeated long-press detection.
    longPressActive = true;

    // Enter low-power sleep mode.
    enterDeepSleep();
  }

  // Detect button release.
  if (lastButtonState == LOW &&
      buttonState == HIGH)
  {
    // Ignore releases that already triggered a long press.
    if (!longPressActive)
    {
      // Record the current timestamp.
      unsigned long now = millis();

      // Determine whether this press belongs to the current sequence.
      if (now - lastPressTime < 500)
      {
        // Increment the press count.
        pressCount++;
      }
      else
      {
        // Start a new press sequence.
        pressCount = 1;
      }

      // Save the release time.
      lastPressTime = now;
    }

    // Reset the long-press flag.
    longPressActive = false;
  }

  // Save the current button state for edge detection.
  lastButtonState = buttonState;

  // Wait until the double-click timeout expires.
  if (pressCount > 0 &&
      millis() - lastPressTime > 500)
  {
    // Handle a single button press.
    if (pressCount == 1)
    {
      // Start logging if it is currently stopped.
      if (!logging)
        startLogging();
      else
        // Otherwise stop logging.
        stopLogging();
    }

    // Handle a double button press.
    else if (pressCount == 2)
    {
      // Enable BLE advertising if disabled.
      if (!bleEnabled)
      {
          startBLE();
      }
      else
      {
          // Otherwise disable BLE advertising.
          stopBLE();
      }
    }

    // Reset the press counter.
    pressCount = 0;
  }

  // Sample and log sensor data at the configured rate.
  if (logging &&
      millis() - lastSampleTime >= SAMPLE_INTERVAL)
  {
    // Record the current sampling time.
    lastSampleTime = millis();

    // Read the current RTC timestamp.
    RtcDateTime now = rtc.GetDateTime();

    // Read accelerometer measurements.
    float ax = imu.readFloatAccelX();
    float ay = imu.readFloatAccelY();
    float az = imu.readFloatAccelZ();

    // Read gyroscope measurements.
    float gx = imu.readFloatGyroX();
    float gy = imu.readFloatGyroY();
    float gz = imu.readFloatGyroZ();

    // Buffer used for BLE live streaming.
    char bleData[80];

    // Format the IMU data as a comma-separated string.
    snprintf(
      bleData,
      sizeof(bleData),
      "%.2f,%.2f,%.2f,%.2f,%.2f,%.2f",
      ax, ay, az,
      gx, gy, gz
    );

    // Store the timestamp of the previous BLE update.
    static unsigned long lastBleTime = 0;

    // Limit BLE updates to approximately 5 Hz.
    if (Bluefruit.connected() &&
        millis() - lastBleTime >= 200)
    {
      // Update the BLE transmission timer.
      lastBleTime = millis();

      // Update the characteristic value.
      imuChar.write(bleData);

      // Notify the connected BLE client.
      imuChar.notify(bleData);
    }

    // Continue only if the log file is open.
    if (logFile)
    {
      // Write the current date.
      logFile.print(now.Year());
      logFile.print("-");
      if (now.Month() < 10) logFile.print("0");
      logFile.print(now.Month());
      logFile.print("-");
      if (now.Day() < 10) logFile.print("0");
      logFile.print(now.Day());
      logFile.print(",");

      // Write the current time.
      if (now.Hour() < 10) logFile.print("0");
      logFile.print(now.Hour());
      logFile.print(":");
      if (now.Minute() < 10) logFile.print("0");
      logFile.print(now.Minute());
      logFile.print(":");
      if (now.Second() < 10) logFile.print("0");
      logFile.print(now.Second());
      logFile.print(",");

      // Write the Arduino uptime in milliseconds.
      logFile.print(millis());
      logFile.print(",");

      // Write accelerometer values.
      logFile.print(ax, 4);
      logFile.print(",");
      logFile.print(ay, 4);
      logFile.print(",");
      logFile.print(az, 4);
      logFile.print(",");

      // Write gyroscope values.
      logFile.print(gx, 4);
      logFile.print(",");
      logFile.print(gy, 4);
      logFile.print(",");
      logFile.println(gz, 4);

      // Count the number of logged samples.
      static uint32_t flushCounter = 0;
      flushCounter++;

      // Flush buffered data approximately every five seconds.
      if (flushCounter >= 50)
      {
        // Write pending data to the SD card.
        logFile.flush();

        // Reset the flush counter.
        flushCounter = 0;
      }
    }
  }

  // Automatically stop BLE advertising after 30 seconds if no client connects.
  if (bleEnabled &&
      !Bluefruit.connected() &&
      millis() - advertiseStartTime > 30000)
  {
      // Disable BLE advertising.
      stopBLE();
  }
}
