int segPins[7] = {2,3,4,5,6,7,8};

byte digits[10][7] = {
  {1,1,1,1,1,1,0}, //0
  {0,1,1,0,0,0,0}, //1
  {1,1,0,1,1,0,1}, //2
  {1,1,1,1,0,0,1}, //3
  {0,1,1,0,0,1,1}, //4
  {1,0,1,1,0,1,1}, //5
  {1,0,1,1,1,1,1}, //6
  {1,1,1,0,0,0,0}, //7
  {1,1,1,1,1,1,1}, //8
  {1,1,1,1,0,1,1}  //9
};

void displayDigit(int num)
{
  for(int i=0; i<7; i++)
  {
    digitalWrite(segPins[i], digits[num][i]);
  }
}

void setup()
{
  for(int i=0; i<7; i++)
  {
    pinMode(segPins[i], OUTPUT);
  }
}

void loop()
{
  for(int count=0; count<=9; count++)
  {
    displayDigit(count);
    delay(1000);
  }
}