#include <math.h>

// Ramp variable
int rampValue=0;

// Triangle variables
int triValue=0;
int triDir=1;

// Sine variable
int angle=0;

void setup(){

// Output pins
pinMode(6,OUTPUT); // CH1 Ramp
pinMode(5,OUTPUT); // CH2 Triangle
pinMode(9,OUTPUT); // CH3 Sine

// TIMER0
// D6 -> OCR0A
// D5 -> OCR0B

TCCR0A=
(1<<COM0A1)|
(1<<COM0B1)|
(1<<WGM00)|
(1<<WGM01);

TCCR0B=
(1<<CS00);

// TIMER1
// D9 -> OCR1A

TCCR1A=
(1<<COM1A1)|
(1<<WGM10);

TCCR1B=
(1<<WGM12)|
(1<<CS10);
}

void loop(){

// CH1 RAMP ON D6

OCR0A=rampValue;

rampValue++;

if(rampValue>255){
rampValue=0;
}

// CH2 TRIANGLE ON D5

OCR0B=triValue;

triValue+=triDir;

if(triValue>=255){
triDir=-1;
}

if(triValue<=0){
triDir=1;
}

// CH3 SINE ON D9

float rad=angle*0.0174533;

OCR1A=127+127*sin(rad);

angle++;

if(angle>=360){
angle=0;
}

delayMicroseconds(20);
}