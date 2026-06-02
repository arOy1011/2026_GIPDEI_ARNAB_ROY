![[Pasted image 20260602111519.png]]
Board pin breakdown:
## **Arduino Uno Pin Breakdown**

### **Digital Pins (D0–D13)**

|**Pin**|**Function**|
|---|---|
|D0|RX (Serial Receive)|
|D1|TX (Serial Transmit)|
|D2|Digital I/O, External Interrupt 0|
|D3|Digital I/O, PWM, External Interrupt 1|
|D4|Digital I/O|
|D5|Digital I/O, PWM|
|D6|Digital I/O, PWM|
|D7|Digital I/O|
|D8|Digital I/O|
|D9|Digital I/O, PWM|
|D10|Digital I/O, PWM, SPI SS|
|D11|Digital I/O, PWM, SPI MOSI|
|D12|Digital I/O, SPI MISO|
|D13|Digital I/O, SPI SCK, Built-in LED|

### **PWM Pins**

Pins marked `~` can generate PWM using `analogWrite()`:

```text
D3, D5, D6, D9, D10, D11
```

---

### **Analog Pins (A0–A5)**

|**Pin**|**Function**|
|---|---|
|A0|Analog Input 0|
|A1|Analog Input 1|
|A2|Analog Input 2|
|A3|Analog Input 3|
|A4|Analog Input, I²C SDA|
|A5|Analog Input, I²C SCL|

**Note:** A0–A5 can also be used as digital pins D14–D19.

---

### **Power Pins**

|**Pin**|**Function**|
|---|---|
|VIN|External supply input (7–12 V recommended)|
|5V|Regulated 5 V output|
|3.3V|3.3 V output (~50 mA max)|
|GND|Ground|
|RESET|Reset pin|
|IOREF|Reference voltage for shields|

---

### **Communication Pins**

#### **UART (Serial)**

|**Pin**|**Function**|
|---|---|
|D0|RX|
|D1|TX|

#### **I²C**

|**Pin**|**Function**|
|---|---|
|A4|SDA|
|A5|SCL|

#### **SPI**

|**Pin**|**Function**|
|---|---|
|D10|SS|
|D11|MOSI|
|D12|MISO|
|D13|SCK|

(Also available on the ICSP header.)

---

### **External Interrupt Pins**

|**Pin**|**Interrupt**|
|---|---|
|D2|INT0|
|D3|INT1|

Example:

```cpp
attachInterrupt(digitalPinToInterrupt(2), ISR_Function, RISING);
```

---

### **ATmega328P Port Mapping**

|**Arduino Pin**|**MCU Port**|
|---|---|
|D0–D7|PORTD|
|D8–D13|PORTB|
|A0–A5|PORTC|

This mapping is useful when doing direct register programming (`PORTB`, `PORTC`, `PORTD`) for faster I/O.