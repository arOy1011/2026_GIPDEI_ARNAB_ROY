// int segPins[7] = {27,12,2,4,5,25,32}; //{a:d2>d27, b:d3>d13, c:d4>d2, d:d5>d4, e:d6>d5, f:d7>d25, g:d8>d32}

// byte digits[10][7] = {
//   {1,1,1,1,1,1,0}, //0
//   {0,1,1,0,0,0,0}, //1
//   {1,1,0,1,1,0,1}, //2
//   {1,1,1,1,0,0,1}, //3
//   {0,1,1,0,0,1,1}, //4
//   {1,0,1,1,0,1,1}, //5
//   {1,0,1,1,1,1,1}, //6
//   {1,1,1,0,0,0,0}, //7
//   {1,1,1,1,1,1,1}, //8
//   {1,1,1,1,0,1,1}  //9
// };

// void displayDigit(int num)
// {
//   for(int i=0; i<7; i++)
//   {
//     digitalWrite(segPins[i], digits[num][i]);
//   }
// }

// void setup()
// {
//   for(int i=0; i<7; i++)
//   {
//     pinMode(segPins[i], OUTPUT);
//   }
// pinMode(21, OUTPUT);  
// }

// void loop()
// {
//   for(int count=0; count<=9; count++)
//   {
//     displayDigit(count);
//     delay(333);
//   digitalWrite(21, HIGH);
//   delay(333);
//   digitalWrite(21, LOW);
//   delay(1200);
//   }

int segPins[7] = {27,12,2,4,5,25,32};
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
const int ledPin = 21;
const int buttonPin = 18;
bool countUp = true;
bool lastButtonState = HIGH;
void displayDigit(int num)
{
  for(int i = 0; i < 7; i++)
  {
    digitalWrite(segPins[i], digits[num][i]);
  }
}
void checkButton()
{
  bool currentState = digitalRead(buttonPin);
  // Detect button press
  if(lastButtonState == HIGH && currentState == LOW)
  {
    countUp = !countUp;   // Toggle direction
    delay(50);            // Debounce
  }
  lastButtonState = currentState;
}
void setup()
{
  for(int i = 0; i < 7; i++)
  {
    pinMode(segPins[i], OUTPUT);
  }
  pinMode(ledPin, OUTPUT);
  pinMode(buttonPin, INPUT_PULLUP);
}
void loop()
{
  if(countUp)
  {
    for(int count = 0; count <= 9; count++)
    {
      checkButton();
      if(!countUp) break;
      displayDigit(count);
      digitalWrite(ledPin, HIGH);
      delay(333);
      digitalWrite(ledPin, LOW);
      delay(1200);
    }
  }
  else
  {
    for(int count = 9; count >= 0; count--)
    {
      checkButton();
      if(countUp) break;
      displayDigit(count);
      digitalWrite(ledPin, HIGH);
      delay(333);
      digitalWrite(ledPin, LOW);
      delay(1200);
    }
  }
}