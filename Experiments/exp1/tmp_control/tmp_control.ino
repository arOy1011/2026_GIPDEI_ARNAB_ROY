#include <DHT.h>

#define DHTPIN 2
#define DHTTYPE DHT22

DHT dht(DHTPIN, DHTTYPE);

void setup(){

  Serial.begin(9600);

  dht.begin();

  pinMode(3, OUTPUT);
  pinMode(5, OUTPUT);
  pinMode(8, OUTPUT);
}

void loop() {

  float temp = dht.readTemperature();

  Serial.println(temp);

  if (isnan(temp)) {

    digitalWrite(3, LOW);
    digitalWrite(5, LOW);
    digitalWrite(8, LOW);

    return;
  }

  // HOT
  if(temp > 35) {

    digitalWrite(3, HIGH);
    digitalWrite(8, HIGH);
    digitalWrite(5, LOW);
  }

  // COLD
  else if(temp < 25) {

    digitalWrite(5, HIGH);
    digitalWrite(3, LOW);
    digitalWrite(8, LOW);
  }

  // NORMAL
  else {

    digitalWrite(3, LOW);
    digitalWrite(5, LOW);
    digitalWrite(8, LOW);
  }

  delay(1000);
}