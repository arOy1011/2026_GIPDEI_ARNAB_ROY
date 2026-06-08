#include <DHT.h>

#define DHTPIN 2
#define DHTTYPE DHT22

DHT dht(DHTPIN, DHTTYPE);

void setup(){

  Serial.begin(9600);

  dht.begin();

  pinMode(3, OUTPUT); //Cooling Led
  pinMode(5, OUTPUT); //Heater led
  pinMode(8, OUTPUT); //2A
  pinMode(7, OUTPUT); //1A
  pinMode(9, OUTPUT); //EN
}

void loop() {

  float temp = dht.readTemperature();

  Serial.println(temp);

  if (isnan(temp)) {

    digitalWrite(3, LOW);
    digitalWrite(5, LOW);
    digitalWrite(9, LOW);

    return;
  }

  // HOT
  if(temp > 35)
  {
      digitalWrite(3, HIGH);   // cooling LED
      digitalWrite(5, LOW);
      digitalWrite(9, HIGH);   // motor ON
      digitalWrite(7, HIGH);
      digitalWrite(8, LOW);
  }
  // COLD
  else if(temp < 25) {

    digitalWrite(5, HIGH);
    digitalWrite(3, LOW);
    digitalWrite(9, LOW);
  }

  // NORMAL
  else {

    digitalWrite(3, LOW);
    digitalWrite(5, LOW);
    digitalWrite(9, LOW);
  }

  delay(1000);
}