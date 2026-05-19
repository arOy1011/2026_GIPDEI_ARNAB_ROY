#include <DHT.h>
#define DHTPIN 2
#define DHTTYPE DHT22
DHT t(DHTPIN,DHTTYPE);

void setup() {
  Serial.begin(9600);
  t.begin();
  pinMode(3, OUTPUT);
  pinMode(5, OUTPUT);
  pinMode(8, OUTPUT);
  pinMode(9, OUTPUT);
}

void loop() {
  float temp = t.readTemperature();
  Serial.println(temp);
  if(isnan(temp)){
    digitalWrite(3, LOW);
    digitalWrite(5, LOW);
    digitalWrite(8, LOW);
    digitalWrite(9, LOW);
    return;
  }
  if (temp>45){
    tone(9, 1000);
    digitalWrite(3, HIGH);
    digitalWrite(8, HIGH);
    digitalWrite(5, LOW);
  }
  else {
    noTone(9);
  }
  if (temp>35){
    digitalWrite(3, HIGH);
    digitalWrite(8, HIGH);
    digitalWrite(5, LOW);
  } else if(temp<25){
    digitalWrite(3, LOW);
    digitalWrite(8, LOW);
    digitalWrite(5, HIGH);    
  } else {
    digitalWrite(3, LOW);
    digitalWrite(8, LOW);
    digitalWrite(5, LOW);    
  }
delay(500);
}
