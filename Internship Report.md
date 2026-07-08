
**Name:** Arnab Roy  
**Roll Number:** 2024UG010  
**Programme:** BS-MS in Computer Science  
**Institute:** Indian Association for the Cultivation of Science (IACS)  
**Internship:** GIPEDI Internship Programme, IIT Delhi
**Duration:** 18/05/2026-13/07/2026

---

# Table of Contents

- [[#Introduction|Introduction]]

- [[#Hardware and Software Resources|Hardware and Software Resources]]
  - [[#Development Boards|Development Boards]]
  - [[#Sensors|Sensors]]
  - [[#Communication Modules|Communication Modules]]
  - [[#Storage Devices|Storage Devices]]
  - [[#Displays|Displays]]
  - [[#Other Components|Other Components]]

- [[#Development Tools and Libraries|Development Tools and Libraries]]
  - [[#Development Software|Development Software]]
  - [[#Documentation and Design Tools|Documentation and Design Tools]]
  - [[#Arduino Board Support Packages|Arduino Board Support Packages]]
  - [[#Arduino Libraries|Arduino Libraries]]
    - [[#Core Libraries|Core Libraries]]
    - [[#Sensor Libraries|Sensor Libraries]]
    - [[#Communication Libraries|Communication Libraries]]
    - [[#RTC Libraries|RTC Libraries]]
    - [[#Display Libraries|Display Libraries]]
    - [[#Input Libraries|Input Libraries]]
  - [[#Flutter Packages|Flutter Packages]]
  - [[#Development Utilities|Development Utilities]]
  - [[#Programming Languages|Programming Languages]]
  - [[#Bill of Materials (BOM)|Bill of Materials (BOM)]]

- [[#Knowledge and Technologies Acquired|Knowledge and Technologies Acquired]]

- [[#Work Completed During the Internship|Work Completed During the Internship]]
  - [[#Simulation and Practical Application of Embedded Circuits|Simulation and Practical Application of Embedded Circuits]]
  - [[#Motion Data Logger Project|Motion Data Logger Project]]

- [[#Challenges Encountered|Challenges Encountered]]

- [[#Skills Developed|Skills Developed]]
  - [[#Technical Skills|Technical Skills]]

- [[#Conclusion|Conclusion]]

- [[#References|References]]

---
# Introduction

During this internship, I worked on a variety of embedded systems projects using the Arduino Uno, ESP32, and Seeed XIAO nRF52840 Sense development boards. The internship focused on building practical skills in embedded programming, hardware interfacing, sensor integration, communication protocols, and system design through hands-on implementation of multiple projects.

I began by developing a series of embedded applications using the Arduino Uno and ESP32, which included digital output and display interfacing, temperature monitoring and weather alert systems, a scientific calculator, a waveform generator, an RTC-based monitoring and automation system, and an audio playback system. These projects provided practical experience in interfacing different hardware peripherals, implementing control logic, and developing firmware for embedded systems.
Building on the knowledge gained from these projects, I developed a Bluetooth-enabled Motion Data Logger using the **Seeed XIAO nRF52840 Sense**. The system acquires motion data from the onboard IMU sensor, records timestamped data on a microSD card using a Real-Time Clock (RTC), communicates with an Android application over Bluetooth Low Energy (BLE), and incorporates deep sleep functionality for low-power operation. As part of this project, I also developed the companion Android application, designed a custom PCB for the hardware, and prepared comprehensive technical documentation.

This report presents the hardware platforms, software tools, technologies, and libraries used during the internship, along with the projects completed, challenges encountered, and the practical knowledge and skills acquired throughout the internship.

---
# Hardware and Software Resources

## Development Boards

- Arduino Uno
- Seeed XIAO nRF52840 Sense
- Espressif ESP32-WROOM 32

## Sensors

- LSM6DS3 IMU(XIAO inbuilt)
- LM35

## Communication Modules

- Bluetooth Low Energy (BLE)
- USB (microUSB, type-C)

## Storage Devices

- microSD Card Module

## Displays

- Nokia PCD8544 LCD
- 16×2 Character LCD(JHD 162A)
- LT543 Hi-lite(7 segment display)

## Other Components

- Push Buttons
- LEDs
- Buzzer
- Relay Module
- L293 Motor Driver
- Potentiometers
- DS1302 Real-Time Clock
- DHT22 Temperature Sensor
- R-2R DAC
- Breadboard
- Resistors
- Connecting Wires

---

# Development Tools and Libraries

This chapter describes the software tools, development environments, frameworks, board support packages, and software libraries used throughout the internship for firmware development, mobile application development, PCB design, documentation, and version control.
## Development Software

| Software              | Version                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           | Purpose                            |
| --------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------- |
| Arduino IDE           | Version: 2.3.10<br>Date: 2026-06-09T16:44:44.168Z<br>CLI Version: 1.5.1<br><br>Copyright © 2026 Arduino s.r.l. and/or its affiliated companies                                                                                                                                                                                                                                                                                                                                                                                                                    | Embedded firmware development      |
| Visual Studio Code    | Version: 1.127.0 (Universal)<br>Commit: 4fe60c8b1cdac1c4c174f2fb180d0d758272d713<br>Date: 2026-06-30T10:52:33+02:00<br>Electron: 42.2.0<br>ElectronBuildId: 14159160<br>Chromium: 148.0.7778.97<br>Node.js: 24.15.0<br>V8: 14.8.178.14-electron.0<br>OS: Darwin arm64 25.5.0                                                                                                                                                                                                                                                                                      | Source code editing                |
| Flutter SDK<br>(Dart) | Flutter 3.44.4 • channel stable • https://github.com/flutter/flutter.git<br><br>Framework • revision ad70ec4617 (13 days ago) • 2026-06-24 11:07:06 -0700<br><br>Engine • hash 700aebeca4c0e610f109a3979ee3e71b69d666bc (revision a10d8ac38d) (13<br><br>days ago) • 2026-06-23 23:09:55.000Z<br><br>Tools • Dart 3.12.2 • DevTools 2.57.0                                                                                                                                                                                                                        | Android application development    |
| Android Studio        | Quail 1 \| 2026.1.1 Patch                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         | Android build and debugging        |
| Obsidian              | Version 1.12.7 (Installer 1.11.7)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 | Technical documentation            |
| KiCad                 | Version: 10.0.3, release build<br><br>Libraries:<br>	wxWidgets 3.2.8 <br>	FreeType 2.14.3<br>	HarfBuzz 12.3.2<br>	FontConfig 2.17.1<br>	libcurl/8.7.1 (SecureTransport) LibreSSL/3.3.6 zlib/1.2.12 nghttp2/1.68.1<br><br>Platform: macOS Version 26.5.2 (Build 25F84), 64 bit, Little endian, wxMac<br><br>Build Info:<br>	Date: May 13 2026 20:28:11<br>	wxWidgets: 3.2.8 (wchar_t,wx containers)<br>	Boost: 1.90.0<br>	OCC: 7.9.3<br>	Curl: 8.7.1<br>	ngspice: 44.2<br>	Compiler: Clang 17.0.0 with C++ ABI 1002<br>	KICAD_IPC_API=ON<br>	KICAD_USE_PCH=OFF<br> | PCB design                         |
| GitHub                | 2.54.0                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            | Source code management             |
| SimulIDE              | 1.1.0 SR2                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         | Simulation of Circuits             |
| LTSpice               |                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   | Wiring Check                       |
| nRF connect           |                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   | Bluetooth connection to smartphone |

---

## Documentation and Design Tools

| Tool       | Purpose                                   |
| ---------- | ----------------------------------------- |
| Markdown   | Technical documentation                   |
| Mermaid.js | Flowchart and system diagram generation   |
| Obsidian   | Project documentation and note management |
| Git        | Documentation version control             |

---

## Arduino Board Support Packages

| Package                    | Purpose                           |
| -------------------------- | --------------------------------- |
| Arduino AVR Boards         | Arduino Uno development           |
| ESP32 by Espressif Systems | ESP32 firmware development        |
| Seeed nRF52 Boards         | Seeed XIAO nRF52840 Sense support |

---

## Arduino Libraries

### Core Libraries

| Library | Purpose                   |
| ------- | ------------------------- |
| Wire    | I²C communication         |
| SPI     | SPI communication         |
| SdFat   | microSD card interface    |
| EEPROM  | Non-volatile data storage |

---

### Sensor Libraries

| Library           | Purpose                               |
| ----------------- | ------------------------------------- |
| LSM6DS3           | IMU sensor communication              |
| DHT               | DHT22 temperature and humidity sensor |
| OneWire           | OneWire communication protocol        |
| DallasTemperature | DS18B20 temperature sensor            |

---

### Communication Libraries

| Library            | Purpose                                  |
| ------------------ | ---------------------------------------- |
| Adafruit Bluefruit | Bluetooth Low Energy (BLE) communication |

---

### RTC Libraries

| Library                 | Purpose                       |
| ----------------------- | ----------------------------- |
| RtcDS3231 *(or RTClib)* | Real-Time Clock communication |

---

### Display Libraries

| Library          | Purpose                |
| ---------------- | ---------------------- |
| LiquidCrystal    | 16×2 LCD display       |
| Adafruit_GFX     | Graphics rendering     |
| Adafruit_PCD8544 | Nokia 5110 LCD display |

---

### Input Libraries

| Library | Purpose                 |
| ------- | ----------------------- |
| Keypad  | Matrix keypad interface |

---

## Flutter Packages

| Package            | Version | Purpose                                 |
| ------------------ | ------- | --------------------------------------- |
| flutter_blue_plus  | 2.3.10  | Bluetooth Low Energy communication      |
| permission_handler | 12.0.3  | Runtime permission management           |
| file_picker        | 10.3.10 | File selection from device storage      |
| shared_preferences | 2.5.3   | Local application settings              |
| url_launcher       | 6.3.1   | Launch external URLs and file locations |
| path_provider      | 2.1.5   | Access application storage directories  |
| cupertino_icons    | 1.0.8   | iOS-style icon set                      |

---

## Development Utilities

| Utility                           | Purpose                          |
| --------------------------------- | -------------------------------- |
| Arduino Serial Monitor            | Firmware debugging               |
| GitHub                            | Source code repository           |
| USB Serial Communication          | Data monitoring and debugging    |
| BLE Scanner / Android Application | Bluetooth testing and validation |

---

## Programming Languages

| Language | Application |
|----------|-------------|
| C++ | Embedded firmware development |
| Dart | Android application development |
| Markdown | Technical documentation |
| YAML | Flutter project configuration |

---
## Bill of Materials (BOM)

The table below lists the major hardware components used in the development of the Motion Data Logger.

| Sl. No. | Component                                 |  Quantity   | Purpose                                          |
| :-----: | ----------------------------------------- | :---------: | ------------------------------------------------ |
|    1    | Seeed XIAO nRF52840 Sense                 |      1      | Main microcontroller with onboard IMU            |
|    2    | DS3231 Real-Time Clock (RTC) Module       |      1      | Accurate timestamp generation                    |
|    3    | microSD Card Module                       |      1      | Storage interface for logged data                |
|    4    | microSD Card                              |      1      | Motion data storage                              |
|    5    | Li-Po Battery (3.7 V)                     |      1      | Portable power supply                            |
|    6    | Battery Charging/Power Management Circuit |      1      | Battery charging and power management            |
|    7    | Push Button                               |      1      | User input for logging, BLE mode, and deep sleep |
|    8    | Custom Printed Circuit Board (PCB)        |      1      | Hardware integration                             |
|    9    | USB Type-C Connector                      |      1      | Programming and battery charging                 |
|   10    | Pin Headers / Connectors                  | As required | External electrical connections                  |
|   11    | Decoupling Capacitors                     | As required | Power supply filtering and stability             |
|   12    | Pull-up/Pull-down Resistors               | As required | Signal conditioning and input stabilization      |

---

# Knowledge and Technologies Acquired

During the internship, I learned and applied several concepts related to embedded systems and software development.

The major areas covered include:

- Embedded C/C++ Programming
- Arduino Development
- GPIO Programming
- Analog-to-Digital Conversion (ADC)
- PWM Signal Generation
- Digital Input/Output Interfacing
- Sensor Interfacing
- I²C Communication
- SPI Communication
- UART Communication
- Bluetooth Low Energy (BLE)
- SD Card File Handling
- Real-Time Clock Integration
- Power Management
- Deep Sleep Implementation
- Android Application Development using Flutter
- PCB Design using KiCad
- Technical Documentation using Markdown

---

# Work Completed During the Internship

This chapter summarizes the practical work completed throughout the internship.

## 1.Simluation and Practical Application of Embedded circuits

The following embedded system applications were designed and implemented during the initial phase of the internship.

- Digital Output and LED,DISPLAY Interfacing
- Temperature Monitoring and Weather Monitoring System
- Scientific Calculator
- Waveform Generator
- RTC-Based Monitoring System
- Audio Playback System

Each task focused on understanding different hardware interfaces, communication protocols, peripheral integration, and embedded programming techniques.

## 2.Project of Data Recorder

The primary project undertaken during the internship was the development of a Bluetooth-enabled Motion Data Logger.

The project involved designing an embedded system capable of acquiring motion data, storing measurements on a microSD card, communicating with a mobile application over Bluetooth Low Energy, and operating efficiently using deep sleep power management.

Major components of the project include:

- System Architecture
- Hardware Design
- Firmware Development
- IMU Integration
- RTC Integration
- Data Logging
- Bluetooth Communication
- Android Application Development
- Deep Sleep Implementation
- PCB Design
- System Testing and Validation

---

# Challenges Encountered

Throughout the internship, several technical challenges were encountered during both hardware and software development.

Some of the major challenges included:

- Bluetooth communication reliability
- SD card data logging
- RTC synchronization
- Power management
- Deep sleep wake-up implementation
- File transfer over BLE
- PCB routing
- Hardware debugging
- Firmware debugging
- Mobile application debugging

Addressing these challenges significantly improved my understanding of embedded system development and debugging methodologies.

---

# Skills Developed

## Technical Skills

- Embedded Systems Development
- Arduino Programming
- Embedded C/C++
- Bluetooth Low Energy
- Sensor Interfacing
- PCB Design
- Android Application Development
- Version Control using Git
- Technical Documentation
- Debugging
- Problem Solving
- Technical Writing
- Project Planning
- Hardware Integration
- Firmware Development
- Software Development

---

# Conclusion

The internship provided valuable practical experience in embedded systems, firmware development, hardware interfacing, wireless communication, mobile application development, and PCB design.

Through the completion of multiple laboratory tasks and the development of the Motion Data Logger project, I gained hands-on experience in designing complete embedded solutions while improving my debugging, documentation, and software development skills.

The knowledge acquired during this internship has strengthened my understanding of embedded system design and provided a strong foundation for future academic and research work.

---

# References

- [Arduino Documentation](https://robotix.ah-oui.org/user_docs/2003/Arduinodocumentation.pdf)
- [Seeed Studio Documentation](https://wiki.seeedstudio.com/XIAO_BLE/)
- [Flutter](https://docs.flutter.dev/install)
- [KiCad Tutorial](https://youtube.com/playlist?list=PLimTcXK6kSUzTT5V02NmA9vwVjA3je0_Z&si=jcBhqJkpOJ2Hj28Z)
- Component Datasheets([DS1302](https://docs.rs-online.com/46c9/0900766b80025c86.pdf), [DS3231](https://www.analog.com/media/en/technical-documentation/data-sheets/ds3231.pdf), [XIAO nRF52840 Sense](https://files.seeedstudio.com/wiki/XIAO/Seeed-Studio-XIAO-Series-SOM-Datasheet.pdf), [ESP32](https://documentation.espressif.com/esp32_datasheet_en.pdf), [Display](https://www.vishay.com/docs/37484/lcd016n002bcfhet.pdf))
- AI([ChatGPT](https://chatgpt.com/), [Copilot](https://github.com/features/copilot))
