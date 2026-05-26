Only clock with mode changing i.e setting time and alarm
Alarm runs for 10 secs
*Display will show RTC inbuilt time*
*Scroll to bottom for going further questions*
```cpp
#include <Wire.h>
#include <LiquidCrystal.h>
#define DS1307_ADDRESS 0x68
LiquidCrystal lcd(7,6,5,4,3,2);
int buzzerPin=9;
int row1=10;
int row2=11;
int col1=12;
int col2=13;
int mode=0;
int setHour=0;
int setMinute=0;
int setSecond=0;
int alarmHour=6;
int alarmMinute=0;
bool alarmEnabled=true;
int curHour=0,curMinute=0,curSecond=0;
int lastMode=-1;

byte decToBcd(byte val){return ((val/10*16)+(val%10));}
byte bcdToDec(byte val){return ((val/16*10)+(val%10));}

void clearCH(){
Wire.beginTransmission(DS1307_ADDRESS);
Wire.write(0x00);
Wire.endTransmission();
Wire.requestFrom(DS1307_ADDRESS,1);
byte reg0=Wire.read();
if(reg0&0x80){
Wire.beginTransmission(DS1307_ADDRESS);
Wire.write(0x00);
Wire.write(reg0&0x7F);
Wire.endTransmission();
}
}

bool readTime(int &h,int &m,int &s){
Wire.beginTransmission(DS1307_ADDRESS);
Wire.write(0);
Wire.endTransmission();
Wire.requestFrom(DS1307_ADDRESS,3);
if(Wire.available()<3)return false;
int rs=bcdToDec(Wire.read()&0x7F);
int rm=bcdToDec(Wire.read());
int rh=bcdToDec(Wire.read()&0x3F);
if(rh>23||rm>59||rs>59)return false;
h=rh;
m=rm;
s=rs;
return true;
}

void setRTCTime(int h,int m,int s){
Wire.beginTransmission(DS1307_ADDRESS);
Wire.write(0);
Wire.write(decToBcd(s));
Wire.write(decToBcd(m));
Wire.write(decToBcd(h));
Wire.endTransmission();
}

char scanKeypad(){
char key='N';
digitalWrite(row1,LOW);
digitalWrite(row2,HIGH);
delayMicroseconds(500);
if(digitalRead(col1)==LOW)key='+';
else if(digitalRead(col2)==LOW)key='M';
digitalWrite(row1,HIGH);
if(key=='N'){
digitalWrite(row2,LOW);
delayMicroseconds(500);
if(digitalRead(col1)==LOW)key='-';
else if(digitalRead(col2)==LOW)key='S';
digitalWrite(row2,HIGH);
}
return key;
}

char getKey(){
char k=scanKeypad();
if(k=='N')return 'N';
delay(40);
if(scanKeypad()!=k)return 'N';
while(scanKeypad()==k);
return k;
}

void incrementValue(){
switch(mode){
case 1: if(++setHour>23)setHour=0; break;
case 2: if(++setMinute>59)setMinute=0; break;
case 3: if(++setSecond>59)setSecond=0; break;
case 4: if(++alarmHour>23)alarmHour=0; break;
case 5: if(++alarmMinute>59)alarmMinute=0; break;
}
}

void decrementValue(){
switch(mode){
case 1: if(--setHour<0)setHour=23; break;
case 2: if(--setMinute<0)setMinute=59; break;
case 3: if(--setSecond<0)setSecond=59; break;
case 4: if(--alarmHour<0)alarmHour=23; break;
case 5: if(--alarmMinute<0)alarmMinute=59; break;
}
}

void pad2(int v){
if(v<10)lcd.print("0");
lcd.print(v);
}

void drawAll(){
lcd.setCursor(0,0);
switch(mode){
case 0: lcd.print("MODE:TIME "); break;
case 1: lcd.print("SET HOURS "); break;
case 2: lcd.print("SET MINUTES "); break;
case 3: lcd.print("SET SECONDS "); break;
case 4: lcd.print("ALARM HOUR "); break;
case 5: lcd.print("ALARM MIN "); break;
}
lcd.setCursor(0,1);
if(mode==4||mode==5){
pad2(alarmHour);
lcd.print(":");
pad2(alarmMinute);
lcd.print(" ");
}
else if(mode>=1&&mode<=3){
pad2(setHour);
lcd.print(":");
pad2(setMinute);
lcd.print(":");
pad2(setSecond);
lcd.print(" ");
}
else{
pad2(curHour);
lcd.print(":");
pad2(curMinute);
lcd.print(":");
pad2(curSecond);
lcd.print(" ");
}
}

void setup(){
Wire.begin();
lcd.begin(16,2);
pinMode(buzzerPin,OUTPUT);
pinMode(row1,OUTPUT);
pinMode(row2,OUTPUT);
pinMode(col1,INPUT_PULLUP);
pinMode(col2,INPUT_PULLUP);
digitalWrite(row1,HIGH);
digitalWrite(row2,HIGH);
digitalWrite(buzzerPin,LOW);
clearCH();
delay(200);
readTime(curHour,curMinute,curSecond);
setHour=curHour;
setMinute=curMinute;
setSecond=curSecond;
lcd.clear();
lcd.print(" RTC Clock ");
delay(1000);
lcd.clear();
// setRTCTime(12,0,0);
}

void loop(){
static unsigned long lastRTCread=0;
if(millis()-lastRTCread>=1000){
lastRTCread=millis();
int h,m,s;
if(readTime(h,m,s)){
curHour=h;
curMinute=m;
curSecond=s;
if(mode==0)drawAll();
}
}

char key=getKey();

if(key=='M'){
mode++;
if(mode>5)mode=0;
if(mode>=1&&mode<=3){
setHour=curHour;
setMinute=curMinute;
setSecond=curSecond;
}
lcd.clear();
drawAll();
}

if(key=='+'){
incrementValue();
drawAll();
}

if(key=='-'){
decrementValue();
drawAll();
}

if(key=='S'){
if(mode>=1&&mode<=3){
setRTCTime(setHour,setMinute,setSecond);
delay(200);
readTime(curHour,curMinute,curSecond);
setHour=curHour;
setMinute=curMinute;
setSecond=curSecond;
mode=0;
lcd.clear();
drawAll();
lastRTCread=millis();
}
}

if(alarmEnabled&&curHour==alarmHour&&curMinute==alarmMinute&&curSecond<10){
tone(buzzerPin,1000);
}
else{
noTone(buzzerPin);
}
}

```

Code with pump, runs for an hour when there is water supply, it turns off after 10 sec of water supply lost.

```cpp
#include <Wire.h>
#include <LiquidCrystal.h>
#define DS1307_ADDRESS 0x68
LiquidCrystal lcd(7,6,5,4,3,2);
int motorPin=8;
int buzzerPin=9;
int row1=10;
int row2=11;
int col1=12;
int col2=13;
int waterPin=A1;
int mode=0;
int setHour=0;
int setMinute=0;
int setSecond=0;
int alarmHour=6;
int alarmMinute=0;
bool alarmEnabled=true;
bool motorState=false;
unsigned long motorStartTime=0;
unsigned long waterLostTime=0;
bool waterPreviouslyPresent=false;
int curHour=0;
int curMinute=0;
int curSecond=0;

byte decToBcd(byte val){
return ((val/10*16)+(val%10));
}

byte bcdToDec(byte val){
return ((val/16*10)+(val%16));
}

void clearCH(){
Wire.beginTransmission(DS1307_ADDRESS);
Wire.write(0x00);
Wire.endTransmission();
Wire.requestFrom(DS1307_ADDRESS,1);
byte reg0=Wire.read();
if(reg0&0x80){
Wire.beginTransmission(DS1307_ADDRESS);
Wire.write(0x00);
Wire.write(reg0&0x7F);
Wire.endTransmission();
}
}

bool readTime(int &h,int &m,int &s){
Wire.beginTransmission(DS1307_ADDRESS);
Wire.write(0);
Wire.endTransmission();
Wire.requestFrom(DS1307_ADDRESS,3);
if(Wire.available()<3)return false;
int rs=bcdToDec(Wire.read()&0x7F);
int rm=bcdToDec(Wire.read());
int rh=bcdToDec(Wire.read()&0x3F);
if(rh>23||rm>59||rs>59)return false;
h=rh;
m=rm;
s=rs;
return true;
}

void setRTCTime(int h,int m,int s){
Wire.beginTransmission(DS1307_ADDRESS);
Wire.write(0);
Wire.write(decToBcd(s));
Wire.write(decToBcd(m));
Wire.write(decToBcd(h));
Wire.endTransmission();
}

char scanKeypad(){
char key='N';
digitalWrite(row1,LOW);
digitalWrite(row2,HIGH);
delayMicroseconds(500);
if(digitalRead(col1)==LOW)key='+';
else if(digitalRead(col2)==LOW)key='M';
digitalWrite(row1,HIGH);
if(key=='N'){
digitalWrite(row2,LOW);
delayMicroseconds(500);
if(digitalRead(col1)==LOW)key='-';
else if(digitalRead(col2)==LOW)key='S';
digitalWrite(row2,HIGH);
}
return key;
}

char getKey(){
char k=scanKeypad();
if(k=='N')return 'N';
delay(40);
if(scanKeypad()!=k)return 'N';
while(scanKeypad()==k);
return k;
}

void incrementValue(){
switch(mode){
case 1:
if(++setHour>23)setHour=0;
break;
case 2:
if(++setMinute>59)setMinute=0;
break;
case 3:
if(++setSecond>59)setSecond=0;
break;
case 4:
if(++alarmHour>23)alarmHour=0;
break;
case 5:
if(++alarmMinute>59)alarmMinute=0;
break;
}
}

void decrementValue(){
switch(mode){
case 1:
if(--setHour<0)setHour=23;
break;
case 2:
if(--setMinute<0)setMinute=59;
break;
case 3:
if(--setSecond<0)setSecond=59;
break;
case 4:
if(--alarmHour<0)alarmHour=23;
break;
case 5:
if(--alarmMinute<0)alarmMinute=59;
break;
}
}

void pad2(int v){
if(v<10)lcd.print("0");
lcd.print(v);
}

void drawAll(){
lcd.setCursor(0,0);
switch(mode){
case 0:
lcd.print("MODE:TIME    ");
break;
case 1:
lcd.print("SET HOURS    ");
break;
case 2:
lcd.print("SET MINUTES  ");
break;
case 3:
lcd.print("SET SECONDS  ");
break;
case 4:
lcd.print("ALARM HOUR   ");
break;
case 5:
lcd.print("ALARM MIN    ");
break;
}
lcd.setCursor(0,1);
if(mode==4||mode==5){
pad2(alarmHour);
lcd.print(":");
pad2(alarmMinute);
}
else if(mode>=1&&mode<=3){
pad2(setHour);
lcd.print(":");
pad2(setMinute);
lcd.print(":");
pad2(setSecond);
}
else{
pad2(curHour);
lcd.print(":");
pad2(curMinute);
lcd.print(":");
pad2(curSecond);
}
lcd.setCursor(12,1);
if(motorState)lcd.print("ON ");
else lcd.print("OFF");
}

void handlePumpControl(){
bool waterPresent=(digitalRead(waterPin)==LOW);
if(waterPresent && !motorState){
digitalWrite(motorPin,HIGH);
motorState=true;
motorStartTime=millis();
}
if(!waterPresent && waterPreviouslyPresent){
waterLostTime=millis();
}
if(!waterPresent && motorState && millis()-waterLostTime>=600000){
digitalWrite(motorPin,LOW);
motorState=false;
}
if(motorState && millis()-motorStartTime>=600000UL){
digitalWrite(motorPin,LOW);
motorState=false;
}
waterPreviouslyPresent=waterPresent;
}

void setup(){
Wire.begin();
lcd.begin(16,2);
pinMode(motorPin,OUTPUT);
pinMode(buzzerPin,OUTPUT);
pinMode(row1,OUTPUT);
pinMode(row2,OUTPUT);
pinMode(col1,INPUT_PULLUP);
pinMode(col2,INPUT_PULLUP);
pinMode(waterPin,INPUT_PULLUP);
digitalWrite(row1,HIGH);
digitalWrite(row2,HIGH);
digitalWrite(motorPin,LOW);
digitalWrite(buzzerPin,LOW);
clearCH();
delay(200);
readTime(curHour,curMinute,curSecond);
setHour=curHour;
setMinute=curMinute;
setSecond=curSecond;
lcd.clear();
lcd.print("RTC CLOCK");
delay(1000);
lcd.clear();
// setRTCTime(12,0,0);
}

void loop(){
static unsigned long lastRTCread=0;
if(millis()-lastRTCread>=1000){
lastRTCread=millis();
int h,m,s;
if(readTime(h,m,s)){
curHour=h;
curMinute=m;
curSecond=s;
if(mode==0)drawAll();
}
}
char key=getKey();
if(key=='M'){
mode++;
if(mode>5)mode=0;
if(mode>=1&&mode<=3){
setHour=curHour;
setMinute=curMinute;
setSecond=curSecond;
}
lcd.clear();
drawAll();
}
if(key=='+'){
incrementValue();
drawAll();
}
if(key=='-'){
decrementValue();
drawAll();
}
if(key=='S'){
if(mode>=1&&mode<=3){
setRTCTime(setHour,setMinute,setSecond);
delay(200);
readTime(curHour,curMinute,curSecond);
setHour=curHour;
setMinute=curMinute;
setSecond=curSecond;
mode=0;
lcd.clear();
drawAll();
lastRTCread=millis();
}
}
if(alarmEnabled&&curHour==alarmHour&&curMinute==alarmMinute&&curSecond<10){
tone(buzzerPin,1000);
}
else{
noTone(buzzerPin);
}
handlePumpControl();
}
```

 Code with previous funtionality, added temperature logging, temperature is logged through serial monitor after every 15 mins.
 **Final code**
 
```cpp
#include <Wire.h>
#include <LiquidCrystal.h>
#include <OneWire.h>
#include <DallasTemperature.h>

#define DS1307_ADDRESS 0x68
#define ONE_WIRE_BUS A2

LiquidCrystal lcd(7,6,5,4,3,2);
OneWire oneWire(ONE_WIRE_BUS);
DallasTemperature sensors(&oneWire);

int motorPin=8;
int buzzerPin=9;
int row1=10;
int row2=11;
int col1=12;
int col2=13;
int waterPin=A1;

int mode=0;
int setHour=0;
int setMinute=0;
int setSecond=0;

int alarmHour=6;
int alarmMinute=0;

bool alarmEnabled=true;
bool motorState=false;
bool waterPreviouslyPresent=false;
bool alreadyLogged=false;

unsigned long motorStartTime=0;
unsigned long waterLostTime=0;

int curHour=0;
int curMinute=0;
int curSecond=0;

float currentTemp=0;

// Decimal to BCD conversion
byte decToBcd(byte val){
return ((val/10*16)+(val%10));
}

// BCD to decimal conversion
byte bcdToDec(byte val){
return ((val/16*10)+(val%16));
}

// Clear clock halt bit in RTC
void clearCH(){
Wire.beginTransmission(DS1307_ADDRESS);
Wire.write(0x00);
Wire.endTransmission();
Wire.requestFrom(DS1307_ADDRESS,1);
byte reg0=Wire.read();
if(reg0&0x80){
Wire.beginTransmission(DS1307_ADDRESS);
Wire.write(0x00);
Wire.write(reg0&0x7F);
Wire.endTransmission();
}
}

// Read current RTC time
bool readTime(int &h,int &m,int &s){
Wire.beginTransmission(DS1307_ADDRESS);
Wire.write(0);
Wire.endTransmission();
Wire.requestFrom(DS1307_ADDRESS,3);
if(Wire.available()<3)return false;
int rs=bcdToDec(Wire.read()&0x7F);
int rm=bcdToDec(Wire.read());
int rh=bcdToDec(Wire.read()&0x3F);
if(rh>23||rm>59||rs>59)return false;
h=rh;
m=rm;
s=rs;
return true;
}

// Manually set RTC time
void setRTCTime(int h,int m,int s){
Wire.beginTransmission(DS1307_ADDRESS);
Wire.write(0);
Wire.write(decToBcd(s));
Wire.write(decToBcd(m));
Wire.write(decToBcd(h));
Wire.endTransmission();
}

// Scan keypad matrix
char scanKeypad(){
char key='N';
digitalWrite(row1,LOW);
digitalWrite(row2,HIGH);
delayMicroseconds(500);
if(digitalRead(col1)==LOW)key='+';
else if(digitalRead(col2)==LOW)key='M';
digitalWrite(row1,HIGH);
if(key=='N'){
digitalWrite(row2,LOW);
delayMicroseconds(500);
if(digitalRead(col1)==LOW)key='-';
else if(digitalRead(col2)==LOW)key='S';
digitalWrite(row2,HIGH);
}
return key;
}

// Debounced keypad read
char getKey(){
char k=scanKeypad();
if(k=='N')return 'N';
delay(40);
if(scanKeypad()!=k)return 'N';
while(scanKeypad()==k);
return k;
}

// Increase editable values
void incrementValue(){
switch(mode){
case 1:
if(++setHour>23)setHour=0;
break;
case 2:
if(++setMinute>59)setMinute=0;
break;
case 3:
if(++setSecond>59)setSecond=0;
break;
case 4:
if(++alarmHour>23)alarmHour=0;
break;
case 5:
if(++alarmMinute>59)alarmMinute=0;
break;
}
}

// Decrease editable values
void decrementValue(){
switch(mode){
case 1:
if(--setHour<0)setHour=23;
break;
case 2:
if(--setMinute<0)setMinute=59;
break;
case 3:
if(--setSecond<0)setSecond=59;
break;
case 4:
if(--alarmHour<0)alarmHour=23;
break;
case 5:
if(--alarmMinute<0)alarmMinute=59;
break;
}
}

// Print two digit number
void pad2(int v){
if(v<10)lcd.print("0");
lcd.print(v);
}

// Update LCD display
void drawAll(){
lcd.setCursor(0,0);
switch(mode){
case 0:
lcd.print("TIME ");
pad2(curHour);
lcd.print(":");
pad2(curMinute);
lcd.print(":");
pad2(curSecond);
lcd.print(" ");
break;
case 1:
lcd.print("SET HOURS    ");
break;
case 2:
lcd.print("SET MINUTES  ");
break;
case 3:
lcd.print("SET SECONDS  ");
break;
case 4:
lcd.print("ALARM HOUR   ");
break;
case 5:
lcd.print("ALARM MIN    ");
break;
}
lcd.setCursor(0,1);
if(mode==4||mode==5){
pad2(alarmHour);
lcd.print(":");
pad2(alarmMinute);
lcd.print(" ");
}
else if(mode>=1&&mode<=3){
pad2(setHour);
lcd.print(":");
pad2(setMinute);
lcd.print(":");
pad2(setSecond);
}
else{
lcd.print(currentTemp);
lcd.print((char)223);
lcd.print("C ");
}
lcd.setCursor(12,1);
if(motorState)lcd.print("ON ");
else lcd.print("OFF");
}

// Automatic pump control logic
void handlePumpControl(){
bool waterPresent=(digitalRead(waterPin)==LOW);
if(waterPresent && !waterPreviouslyPresent){
digitalWrite(motorPin,HIGH);
motorState=true;
motorStartTime=millis();
}
if(!waterPresent && waterPreviouslyPresent){
waterLostTime=millis();
}
if(!waterPresent && motorState && millis()-waterLostTime>=60000){
digitalWrite(motorPin,LOW);
motorState=false;
}
if(motorState && millis()-motorStartTime>=60000UL){
digitalWrite(motorPin,LOW);
motorState=false;
}
waterPreviouslyPresent=waterPresent;
}

// Read and log temperature
void handleTemperatureLogging(){
static unsigned long lastTempRead=0;
if(millis()-lastTempRead>=1000){
lastTempRead=millis();
sensors.requestTemperatures();
delay(750);
currentTemp=sensors.getTempCByIndex(0);
}
if((curMinute%15==0)&&curSecond==0){
if(!alreadyLogged){
Serial.print("TIME: ");
if(curHour<10)Serial.print("0");
Serial.print(curHour);
Serial.print(":");
if(curMinute<10)Serial.print("0");
Serial.print(curMinute);
Serial.print(":");
if(curSecond<10)Serial.print("0");
Serial.print(curSecond);
Serial.print(" TEMP: ");
Serial.print(currentTemp);
Serial.println(" C");
alreadyLogged=true;
}
}
else{
alreadyLogged=false;
}
}

// Initial setup
void setup(){
Wire.begin();
sensors.begin();
Serial.begin(9600);
lcd.begin(16,2);
pinMode(motorPin,OUTPUT);
pinMode(buzzerPin,OUTPUT);
pinMode(row1,OUTPUT);
pinMode(row2,OUTPUT);
pinMode(col1,INPUT_PULLUP);
pinMode(col2,INPUT_PULLUP);
pinMode(waterPin,INPUT_PULLUP);
digitalWrite(row1,HIGH);
digitalWrite(row2,HIGH);
digitalWrite(motorPin,LOW);
digitalWrite(buzzerPin,LOW);
clearCH();
delay(200);

readTime(curHour,curMinute,curSecond);
setHour=curHour;
setMinute=curMinute;
setSecond=curSecond;
lcd.clear();
lcd.print("RTC TEMP SYS");
Serial.println("TEMP LOGGER");
delay(1000);
lcd.clear();
}

// Main loop
void loop(){
static unsigned long lastRTCread=0;
if(millis()-lastRTCread>=1000){
lastRTCread=millis();
int h,m,s;
if(readTime(h,m,s)){
curHour=h;
curMinute=m;
curSecond=s;
drawAll();
}
}

char key=getKey();

if(key=='M'){
mode++;
if(mode>5)mode=0;
if(mode>=1&&mode<=3){
setHour=curHour;
setMinute=curMinute;
setSecond=curSecond;
}
lcd.clear();
drawAll();
}

if(key=='+'){
incrementValue();
drawAll();
}

if(key=='-'){
decrementValue();
drawAll();
}

if(key=='S'){
if(mode>=1&&mode<=3){
setRTCTime(setHour,setMinute,setSecond);
delay(200);
readTime(curHour,curMinute,curSecond);
setHour=curHour;
setMinute=curMinute;
setSecond=curSecond;
mode=0;
lcd.clear();
drawAll();
lastRTCread=millis();
}
}

if(alarmEnabled && curHour==alarmHour && curMinute==alarmMinute && curSecond<10){
tone(buzzerPin,1000);
}
else{
noTone(buzzerPin);
}

handleTemperatureLogging();
handlePumpControl();
}
```