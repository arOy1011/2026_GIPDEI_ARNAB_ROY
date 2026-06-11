#include <DHT.h>
#include <LiquidCrystal.h>

LiquidCrystal lcd(32, 33, 26, 27, 14, 13);

// #define DHTPIN 2
// #define DHTTYPE DHT22

// DHT t(DHTPIN, DHTTYPE);

// ---------------------
// Motor Control Functions
// ---------------------
void motorON() {
  digitalWrite(12, HIGH); // Enable
  digitalWrite(10, HIGH); // 1A
  digitalWrite(11, LOW);  // 2A
}

void motorOFF() {
  digitalWrite(12, LOW);
  digitalWrite(10, LOW);
  digitalWrite(11, LOW);
}

void setup() {

  Serial.begin(9600);

  t.begin();

  lcd.begin(16, 2);

  pinMode(3, OUTPUT);   // Warning LED
  pinMode(5, OUTPUT);   // Heater LED
  pinMode(9, OUTPUT);   // Buzzer

  pinMode(10, OUTPUT);  // L293 1A
  pinMode(11, OUTPUT);  // L293 2A
  pinMode(12, OUTPUT);  // L293 EN

  motorOFF();
}

void loop() {

  float temp = t.readTemperature();
  float humid = t.readHumidity();

  Serial.print("Temperature: ");
  Serial.println(temp);

  Serial.print("Humidity: ");
  Serial.println(humid);

  if (isnan(temp) || isnan(humid)) {

    digitalWrite(3, LOW);
    digitalWrite(5, LOW);

    motorOFF();

    noTone(9);

    lcd.clear();
    lcd.setCursor(0, 0);
    lcd.print("SENSOR ERROR");

    delay(1000);
    return;
  }

  // EXTREME TEMPERATURE
  if (temp > 45) {

    tone(9, 1000);

    digitalWrite(3, HIGH);
    digitalWrite(5, LOW);

    motorON();

    lcd.clear();
    lcd.setCursor(0, 0);
    lcd.print("EXTREME TEMP");

    lcd.setCursor(0, 1);
    lcd.print("ALERT");
  }

  // HEAT WAVE
  else if (temp > 40 && humid < 30) {

    noTone(9);

    digitalWrite(3, HIGH);
    digitalWrite(5, LOW);

    motorON();

    lcd.clear();
    lcd.setCursor(0, 0);
    lcd.print("HEAT WAVE");

    lcd.setCursor(0, 1);
    lcd.print("DRY WEATHER");
  }

  // HOT WEATHER
  else if (temp > 35) {

    noTone(9);

    digitalWrite(3, HIGH);
    digitalWrite(5, LOW);

    motorON();

    lcd.clear();
    lcd.setCursor(0, 0);
    lcd.print("HOT WEATHER");

    lcd.setCursor(0, 1);
    lcd.print("TEMP HIGH");
  }

  // COLD WEATHER
  else if (temp < 15) {

    noTone(9);

    digitalWrite(3, LOW);
    digitalWrite(5, HIGH);

    motorOFF();

    lcd.clear();
    lcd.setCursor(0, 0);
    lcd.print("COLD WEATHER");

    lcd.setCursor(0, 1);
    lcd.print("TEMP LOW");
  }

  // HIGH HUMIDITY
  else if (humid > 80) {

    noTone(9);

    digitalWrite(3, LOW);
    digitalWrite(5, LOW);

    motorOFF();

    lcd.clear();
    lcd.setCursor(0, 0);
    lcd.print("RAIN");

    lcd.setCursor(0, 1);
    lcd.print("POSSIBILITY");
  }

  // NORMAL WEATHER
  else {

    noTone(9);

    digitalWrite(3, LOW);
    digitalWrite(5, LOW);

    motorOFF();

    lcd.clear();
    lcd.setCursor(0, 0);
    lcd.print("NORMAL");

    lcd.setCursor(0, 1);
    lcd.print("WEATHER");
  }

  delay(1000);
}