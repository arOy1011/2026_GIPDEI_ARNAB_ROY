void setup() {
  pinMode(14, OUTPUT);// put your setup code here, to run once:

}

void loop() {
  digitalWrite(14, HIGH);
  delay(1200);
  digitalWrite(14, LOW);
  delay(1400);// put your main code here, to run repeatedly:
}
// #define LED_BUILTIN 2

// void setup() {
//   pinMode(LED_BUILTIN, OUTPUT);
// }

// void loop() {
//   digitalWrite(LED_BUILTIN, HIGH); // LED ON
//   delay(1000);

//   digitalWrite(LED_BUILTIN, LOW);  // LED OFF
//   delay(1000);
// }