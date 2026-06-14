$$
Motion\ Data\ Logger\ using\ Seeed\ XIAO\ nRF52840\ Sense
$$

## Overview

This project is a motion data logger built using the Seeed XIAO nRF52840 Sense. The system reads motion data from the onboard IMU sensor, adds a timestamp using a DS1302 RTC module, and stores the data on a microSD card. The stored data can later be transferred to a smartphone or laptop using Bluetooth Low Energy (BLE).

---

## Hardware Used

1. Seeed XIAO nRF52840 Sense
2. DS1302 RTC Module
3. MicroSD Card Module
4. Push Button
5. Smartphone (for BLE data transfer)
6. Laptop

---

## System Block Diagram
![[BLE Motion Logger.excalidraw]]

---

## Pin Connections

### RTC Module

| RTC Pin | XIAO Pin |
|----------|----------|
| DAT | D1 |
| CLK | D2 |
| RST | D0 |

### Push Button

| Button Pin | XIAO Pin |
| ---------- | -------- |
| One Side   | D3       |
| Other Side | GND      |

### SD Card Module

| SD Pin | XIAO Pin |
|---------|---------|
| CS | D7 |
| MOSI | D10 |
| MISO | D9 |
| SCK | D8 |

---

## Working of the System

### System Initialization

When the device is powered on, the microcontroller initializes the Real-Time Clock (RTC), Inertial Measurement Unit (IMU), microSD card, and Bluetooth Low Energy (BLE) services. Bluetooth remains disabled by default to reduce power consumption. The system then enters an idle state and waits for user input.

### Data Logging Operation

The system uses a single push button to control data logging.

A single press of the button starts a logging session. The current date and time are obtained from the RTC, and a CSV file is created on the microSD card using the current date as the filename. If a file for that date already exists, new data is appended to the existing file.

During logging, the IMU continuously measures:

- Acceleration along the X, Y, and Z axes
- Angular velocity along the X, Y, and Z axes

Sensor readings are sampled at a rate of 10 Hz. Each record is stored together with the current date, time, and system timestamp, creating a complete motion history for later analysis.

Pressing the button again stops the logging process. The collected data is written safely to the microSD card, and the file is closed to prevent data corruption.

### Bluetooth Communication

Bluetooth communication is activated using a double press of the push button.

When enabled, the device starts BLE advertising under the name **MotionLogger**. The device remains discoverable for up to 30 seconds. If no client connects during this period, Bluetooth is automatically disabled to conserve power.

Once connected, a computer or mobile device can communicate with the logger wirelessly. A custom [Python script](connect.py) is used to send commands and receive data.

### Remote Control Functions

The BLE interface supports several commands:

- **STATUS** – Displays the current logging state.
- **START** – Starts data logging remotely.
- **STOP** – Stops data logging remotely.
- **LIST** – Displays all CSV files stored on the microSD card.
- **GET:\<filename\>** – Downloads a selected log file from the device.

These commands allow complete access to recorded data without physically removing the microSD card.

### Real-Time Monitoring

While a BLE connection is active, the device also transmits live accelerometer and gyroscope readings. This enables real-time monitoring of motion data on a connected computer or mobile device.

### Automatic File Management

The system continuously monitors the current date using the RTC. *When a new day begins, the current log file is closed automatically and a new file is created for the new date*. This ensures that data from different days is stored in separate files, simplifying data organization and analysis.

---

## Data Format and File Management

### Data Format

Sensor data is stored in CSV format on the microSD card. Each record contains the date, time, timestamp, accelerometer readings, and gyroscope readings.

### CSV Format

```csv
csv Date,Time,Millis,Ax,Ay,Az,Gx,Gy,Gz 2026-06-12,14:30:21,125431,0.0200,-0.0100,0.9800,1.2100,-0.5300,0.0700 
```

Session markers are automatically added to indicate the start and end of each logging session.

```txt
# SESSION START ...
# SESSION STOP 
```

### File Management

Log files are automatically created using the current date.

#### File Naming Format

```txt
LOG_YYYY_MM_DD.CSV 
```

Example:

```txt
LOG_2026_06_12.CSV 
```

#### Automatic Daily Rollover

If the logger continues running past midnight, the current file is closed automatically and a new file is created for the next day. This allows continuous multi-day logging without user intervention.

Example:

```txt
LOG_2026_06_12.CSV       
		↓  
LOG_2026_06_13.CSV 
```

