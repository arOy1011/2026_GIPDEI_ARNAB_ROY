int rowPins[8] = {2,3,4,5,6,7,8,9};
int colPins[8] = {10,11,12,13,A3,A2,A1,A0};

// Letter T
byte T[8] = {
  B11111111,
  B00011000,
  B00011000,
  B00011000,
  B00011000,
  B00011000,
  B00011000,
  B00011000
};

void setup()
{
  for(int i=0; i<8; i++)
  {
    pinMode(rowPins[i], OUTPUT);
    pinMode(colPins[i], OUTPUT);
  }
}

void loop()
{
  for(int row=0; row<8; row++)
  {
    // turn OFF all rows
    for(int i=0; i<8; i++)
    {
      digitalWrite(rowPins[i], LOW);
    }

    // set columns
    for(int col=0; col<8; col++)
    {
      if(bitRead(T[row], 7-col))
      {
        digitalWrite(colPins[col], LOW);
      }
      else
      {
        digitalWrite(colPins[col], HIGH);
      }
    }

    // activate current row
    digitalWrite(rowPins[row], HIGH);

    delay(2);
  }
}