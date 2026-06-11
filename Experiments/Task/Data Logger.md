# Motion Data Logger using Seeed XIAO nRF52840 Sense

## Overview

This project is a wearable motion data logger built using the Seeed XIAO nRF52840 Sense. The system reads motion data from the onboard IMU sensor, adds a timestamp using a DS1302 RTC module, and stores the data on a microSD card. The stored data can later be transferred to a smartphone using Bluetooth Low Energy (BLE).

---

## Hardware Used

1. Seeed XIAO nRF52840 Sense
2. DS1302 RTC Module
3. MicroSD Card Module
4. Push Button
5. Smartphone (for BLE data transfer)

---

## System Block Diagram

```text id="ew70ji"
IMU Sensor
    ↓
RTC Timestamp
    ↓
CSV File Creation
    ↓
SD Card Storage
    ↓
BLE Transfer
    ↓
Smartphone
```

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

## Working

### Starting a Session

When the push button is pressed:

- A new CSV file is created.
- Data logging starts.
- IMU readings are recorded at 10 Hz.

### During Logging

The system reads:

- Accelerometer values (Ax, Ay, Az)
- Gyroscope values (Gx, Gy, Gz)

The RTC provides the current date and time.

All values are stored in a CSV file on the SD card.

### Stopping a Session

When the button is pressed again:

- Logging stops.
- Data is saved.
- The file is closed safely.

---

## Data Format

Example CSV format:

```csv id="h4k9hm"
Date,Time,Millis,Ax,Ay,Az,Gx,Gy,Gz
2026-06-11,14:30:21,125431,0.02,-0.01,0.98,1.21,-0.53,0.07
```

---

## File Management

Each recording session creates a new file.

Example:

```text id="gd2wd2"
LOG000.CSV
LOG001.CSV
LOG002.CSV
...
```

The system stores up to 120 session files.

When the limit is reached:

```text id="qv9hbg"
LOG119.CSV
↓
Next Session
↓
LOG000.CSV overwritten
```

This prevents the SD card from filling up with unlimited files.

---

## Automatic Daily Rollover

If logging continues past midnight:

```text id="hqlgaw"
11-Jun 23:59:59
↓
Current file closed

12-Jun 00:00:00
↓
New file created

Logging continues automatically
```

This keeps data from different dates in separate files.

---

## Bluetooth Transfer

The system first stores all data on the SD card.

After recording, the stored files can be transferred to a smartphone using BLE.

Data flow:

```text id="o95ndh"
IMU
 ↓
SD Card
 ↓
BLE
 ↓
Smartphone
```

This ensures that no data is lost if the phone is disconnected during recording.

---

## Features

- Motion sensing using onboard IMU
- RTC-based timestamping
- Session-wise CSV file storage
- Push button control
- Automatic daily file rollover
- Circular file management (120 sessions)
- BLE file transfer support

---

