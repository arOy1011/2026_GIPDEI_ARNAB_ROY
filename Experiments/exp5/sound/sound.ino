const byte dacPins[8] = {2,3,4,5,6,7,8,9};

const uint8_t sineTable[32] = {
  128,153,177,199,218,234,245,252,
  255,252,245,234,218,199,177,153,
  128,103,79,57,38,22,11,4,
  0,4,11,22,38,57,79,103
};

void writeDAC(uint8_t value)
{
  for(int i=0;i<8;i++)
    digitalWrite(dacPins[i], (value >> i) & 1);
}

void setup()
{
  for(int i=0;i<8;i++)
    pinMode(dacPins[i], OUTPUT);

  Serial.begin(9600);
}

void loop()
{
  int freqPot = analogRead(A0);
  int ampPot  = analogRead(A5);

  // Frequency: 100 Hz to 5000 Hz
  int freq = map(freqPot, 0, 1023, 100, 5000);

  // Amplitude: 0 to 127
  int amp = map(ampPot, 0, 1023, 0, 127);

  unsigned long delayUs =
      1000000UL / (freq * 32UL);

  for(int i=0;i<32;i++)
  {
    int sample = 128 +
                ((sineTable[i]-128) * amp) / 127;

    writeDAC(sample);

    delayMicroseconds(delayUs);
  }

  static unsigned long lastPrint = 0;

  if(millis() - lastPrint > 500)
  {
    Serial.print("Frequency: ");
    Serial.print(freq);
    Serial.print(" Hz    Amplitude: ");
    Serial.println(amp);

    lastPrint = millis();
  }
}