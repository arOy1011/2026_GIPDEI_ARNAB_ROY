const byte dacPins[8] = {2,3,4,5,6,7,8,9};

void setup()
{
  Serial.begin(115200);

  for(int i=0; i<8; i++)
  {
    pinMode(dacPins[i], OUTPUT);
  }
}

void outputDAC(byte sample)
{
  for(int i=0; i<8; i++)
  {
    digitalWrite(dacPins[i], bitRead(sample, i));
  }
}

void loop()
{
  if(Serial.available())
  {
    byte sample = Serial.read();

    outputDAC(sample);

    Serial.write(sample);   // optional echo back
  }
}