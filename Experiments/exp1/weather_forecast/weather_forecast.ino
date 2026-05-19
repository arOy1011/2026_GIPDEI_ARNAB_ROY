#include <DHT.h>
#include <LiquidCrystal.h>

LiquidCrystal lcd(A0, A1, A2, A3, A4, A5);

#define DHTPIN 2
#define DHTTYPE DHT22

DHT t(DHTPIN, DHTTYPE);

void setup() {

  Serial.begin(9600);

  t.begin();

  lcd.begin(16,2);

  pinMode(3, OUTPUT);
  pinMode(5, OUTPUT);
  pinMode(8, OUTPUT);
  pinMode(9, OUTPUT);
}

void loop() {

  float temp = t.readTemperature();
  float humid = t.readHumidity();

  Serial.print("Temperature: ");
  Serial.println(temp);

  Serial.print("Humidity: ");
  Serial.println(humid);

  if(isnan(temp) || isnan(humid)) {

    digitalWrite(3, LOW);
    digitalWrite(5, LOW);
    digitalWrite(8, LOW);

    noTone(9);

    lcd.clear();

    lcd.setCursor(0,0);
    lcd.print("SENSOR ERROR");

    delay(1000);

    return;
  }

  if(temp > 45) {

    tone(9,1000);

    digitalWrite(3, HIGH);
    digitalWrite(8, HIGH);
    digitalWrite(5, LOW);

    lcd.clear();

    lcd.setCursor(0,0);
    lcd.print("EXTREME TEMP");

    lcd.setCursor(0,1);
    lcd.print("ALERT");
  }

  else if(temp > 40 && humid < 30) {

    noTone(9);

    digitalWrite(3, HIGH);
    digitalWrite(8, HIGH);
    digitalWrite(5, LOW);

    lcd.clear();

    lcd.setCursor(0,0);
    lcd.print("HEAT WAVE");

    lcd.setCursor(0,1);
    lcd.print("DRY WEATHER");
  }

  else if(temp > 35) {

    noTone(9);

    digitalWrite(3, HIGH);
    digitalWrite(8, HIGH);
    digitalWrite(5, LOW);

    lcd.clear();

    lcd.setCursor(0,0);
    lcd.print("HOT WEATHER");

    lcd.setCursor(0,1);
    lcd.print("TEMP HIGH");
  }

  else if(temp < 15) {

    noTone(9);

    digitalWrite(3, LOW);
    digitalWrite(8, LOW);
    digitalWrite(5, HIGH);

    lcd.clear();

    lcd.setCursor(0,0);
    lcd.print("COLD WEATHER");

    lcd.setCursor(0,1);
    lcd.print("TEMP LOW");
  }

  else if(humid > 80) {

    noTone(9);

    digitalWrite(3, LOW);
    digitalWrite(5, LOW);
    digitalWrite(8, LOW);

    lcd.clear();

    lcd.setCursor(0,0);
    lcd.print("RAIN");

    lcd.setCursor(0,1);
    lcd.print("POSSIBILITY");
  }

  else {

    noTone(9);

    digitalWrite(3, LOW);
    digitalWrite(5, LOW);
    digitalWrite(8, LOW);

    lcd.clear();

    lcd.setCursor(0,0);
    lcd.print("NORMAL");

    lcd.setCursor(0,1);
    lcd.print("WEATHER");
  }

  delay(1000);
}