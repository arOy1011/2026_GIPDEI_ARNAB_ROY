#include <Adafruit_GFX.h>
#include <Adafruit_PCD8544.h>
#include <Keypad.h>
#include <math.h>
#include <string.h>
#include <stdlib.h>

// ======================================================
// DISPLAY
// ======================================================

// CLK, DIN, DC, CE, RST

Adafruit_PCD8544 display(
  A4,
  A3,
  A2,
  A1,
  A0
);

// ======================================================
// EXPRESSIONS
// ======================================================

char expr[31] = "";

char prefixExpr[31] = "";

char tempExpr[31] = "";

int exprLen = 0;

int cursorPos = 0;

float ans = 0;

// ======================================================
// LOCK
// ======================================================

bool locked = false;

char entered[4] = "";

int passPos = 0;

// ======================================================
// HISTORY
// ======================================================

char history[5][31];

int historyCount = 0;

int historyIndex = 0;

bool historyMode = false;

// ======================================================
// STACKS
// ======================================================

float valueStack[20];

char opStack[20];

int vTop;

int oTop;

// ======================================================
// KEYPAD
// ======================================================

const byte ROWS = 6;
const byte COLS = 5;

char keys[ROWS][COLS] = {

  {'1','2','3','+','-'},
  {'4','5','6','*','/'},
  {'7','8','9','(',')'},
  {'C','0','.','=','R'},
  {'H','{','}','L','%'},
  {'^','<','>','B','A'}
};

byte rowPins[ROWS] = {
  2,3,4,5,6,7
};

byte colPins[COLS] = {
  8,9,10,11,12
};

Keypad keypad = Keypad(
  makeKeymap(keys),
  rowPins,
  colPins,
  ROWS,
  COLS
);

// ======================================================
// DISPLAY
// ======================================================

void renderDisplay() {

  display.clearDisplay();

  display.setTextSize(1);

  display.setTextColor(BLACK);

  display.setCursor(0,0);

  display.println("Calculator");

  display.drawLine(
    0,
    8,
    83,
    8,
    BLACK
  );

  int start = 0;

  int visibleChars = 14;

  if(cursorPos >= visibleChars) {

    start =
      cursorPos -
      visibleChars +
      1;
  }

  display.setCursor(0,18);

  for(
    int i=start;
    i<exprLen &&
    i<start+visibleChars;
    i++
  ) {

    display.print(expr[i]);
  }

  int localCursor =
    cursorPos - start;

  int cursorX =
    localCursor * 6;

  display.drawLine(
    cursorX,
    35,
    cursorX + 5,
    35,
    BLACK
  );

  display.display();
}

// ======================================================
// MESSAGE
// ======================================================

void showMessage(
  const char* msg
) {

  display.clearDisplay();

  display.setTextSize(1);

  display.setCursor(0,20);

  display.println(msg);

  display.display();

  delay(700);

  renderDisplay();
}

// ======================================================
// HELPERS
// ======================================================

bool isOperator(char c) {

  return (
    c=='+' ||
    c=='-' ||
    c=='*' ||
    c=='/' ||
    c=='^'
  );
}

int precedence(char op) {

  if(op=='+' || op=='-')
    return 1;

  if(op=='*' || op=='/')
    return 2;

  if(op=='^')
    return 3;

  return 0;
}

float applyOp(
  float a,
  float b,
  char op
) {

  switch(op) {

    case '+':
      return a+b;

    case '-':
      return a-b;

    case '*':
      return a*b;

    case '/':

      if(b!=0)
        return a/b;

      return 0;

    case '^':

      return pow(a,b);
  }

  return 0;
}

// ======================================================
// REVERSE STRING
// ======================================================

void reverseString(
  char src[],
  char dest[]
) {

  int len =
    strlen(src);

  for(
    int i=0;
    i<len;
    i++
  ) {

    dest[i] =
      src[len-1-i];
  }

  dest[len] = '\0';
}

// ======================================================
// INFIX TO PREFIX
// ======================================================

void infixToPrefix() {

  reverseString(
    expr,
    tempExpr
  );

  // ===== SWAP BRACKETS =====

  for(
    int i=0;
    tempExpr[i]!='\0';
    i++
  ) {

    if(tempExpr[i]=='(')
      tempExpr[i]=')';

    else if(tempExpr[i]==')')
      tempExpr[i]='(';

    else if(tempExpr[i]=='{')
      tempExpr[i]='}';

    else if(tempExpr[i]=='}')
      tempExpr[i]='{';
  }

  char postfix[31] = "";

  int p = 0;

  oTop = -1;

  int i = 0;

  while(tempExpr[i]!='\0') {

    // ===== OPERAND =====

    if(
      isDigit(tempExpr[i]) ||
      tempExpr[i]=='.'
    ) {

      postfix[p++] =
        tempExpr[i];
    }

    // ===== OPEN =====

    else if(
      tempExpr[i]=='(' ||
      tempExpr[i]=='{'
    ) {

      opStack[++oTop] =
        tempExpr[i];
    }

    // ===== CLOSE =====

    else if(
      tempExpr[i]==')' ||
      tempExpr[i]=='}'
    ) {

      while(
        oTop >= 0 &&
        opStack[oTop] != '(' &&
        opStack[oTop] != '{'
      ) {

        postfix[p++] =
          opStack[oTop--];
      }

      oTop--;
    }

    // ===== OPERATOR =====

    else {

      while(
        oTop >= 0 &&
        precedence(
          opStack[oTop]
        ) >
        precedence(
          tempExpr[i]
        )
      ) {

        postfix[p++] =
          opStack[oTop--];
      }

      opStack[++oTop] =
        tempExpr[i];
    }

    i++;
  }

  while(oTop >= 0) {

    postfix[p++] =
      opStack[oTop--];
  }

  postfix[p] = '\0';

  reverseString(
    postfix,
    prefixExpr
  );
}

// ======================================================
// PREFIX EVALUATION
// ======================================================

float evaluatePrefix() {

  vTop = -1;

  int len =
    strlen(prefixExpr);

  for(
    int i=len-1;
    i>=0;
    i--
  ) {

    // ===== NUMBER =====

    if(isDigit(prefixExpr[i])) {

      float val =
        prefixExpr[i]-'0';

      valueStack[++vTop] =
        val;
    }

    // ===== OPERATOR =====

    else if(
      isOperator(
        prefixExpr[i]
      )
    ) {

      float a =
        valueStack[vTop--];

      float b =
        valueStack[vTop--];

      valueStack[++vTop] =
        applyOp(
          a,
          b,
          prefixExpr[i]
        );
    }
  }

  return valueStack[vTop];
}

// ======================================================
// INSERT
// ======================================================

void insertChar(char c) {

  if(exprLen >= 30)
    return;

  if(
    cursorPos > 0 &&
    isOperator(c) &&
    isOperator(
      expr[cursorPos-1]
    )
  ) {

    return;
  }

  for(
    int i=exprLen;
    i>cursorPos;
    i--
  ) {

    expr[i] = expr[i-1];
  }

  expr[cursorPos] = c;

  exprLen++;

  cursorPos++;

  expr[exprLen] = '\0';
}

// ======================================================
// BACKSPACE
// ======================================================

void backspace() {

  if(
    exprLen <= 0 ||
    cursorPos <= 0
  ) return;

  for(
    int i=cursorPos-1;
    i<exprLen-1;
    i++
  ) {

    expr[i] = expr[i+1];
  }

  exprLen--;

  cursorPos--;

  expr[exprLen] = '\0';
}

// ======================================================
// CLEAR
// ======================================================

void clearExpr() {

  exprLen = 0;

  cursorPos = 0;

  expr[0] = '\0';
}

// ======================================================
// SAVE HISTORY
// ======================================================

void saveHistory() {

  if(historyCount < 5) {

    strcpy(
      history[historyCount++],
      expr
    );
  }

  else {

    for(int i=1;i<5;i++) {

      strcpy(
        history[i-1],
        history[i]
      );
    }

    strcpy(
      history[4],
      expr
    );
  }
}

// ======================================================
// SHOW HISTORY
// ======================================================

void showHistory() {

  display.clearDisplay();

  display.setTextSize(1);

  display.setCursor(0,0);

  display.println("HISTORY");

  display.setCursor(0,20);

  display.println(
    history[historyIndex]
  );

  display.display();
}

// ======================================================
// LOAD HISTORY
// ======================================================

void loadHistory() {

  strcpy(
    expr,
    history[historyIndex]
  );

  exprLen =
    strlen(expr);

  cursorPos =
    exprLen;

  historyMode = false;

  renderDisplay();
}

// ======================================================
// SHOW PREFIX
// ======================================================

void showPrefix() {

  display.clearDisplay();

  display.setTextSize(1);

  display.setCursor(0,0);

  display.println("PREFIX");

  display.setCursor(0,20);

  display.println(
    prefixExpr
  );

  display.display();

  delay(1000);
}

// ======================================================
// SETUP
// ======================================================

void setup() {

  display.begin();

  display.setContrast(60);

  clearExpr();

  renderDisplay();
}

// ======================================================
// LOOP
// ======================================================

void loop() {

  char key =
    keypad.getKey();

  if(!key)
    return;

  // ==================================================
  // LOCK MODE
  // ==================================================

  if(locked) {

    if(isDigit(key)) {

      if(passPos < 3) {

        entered[passPos++] =
          key;

        entered[passPos] =
          '\0';
      }
    }

    else if(key == '=') {

      if(
        strcmp(
          entered,
          "123"
        ) == 0
      ) {

        locked = false;

        passPos = 0;

        entered[0] = '\0';

        renderDisplay();
      }

      else {

        passPos = 0;

        entered[0] = '\0';

        showMessage(
          "INVALID"
        );
      }
    }

    display.clearDisplay();

    display.setCursor(0,0);

    display.println(
      "ENTER PSWD"
    );

    display.display();

    return;
  }

  // ==================================================
  // HISTORY MODE
  // ==================================================

  if(historyMode) {

    if(key=='<') {

      if(historyIndex > 0)
        historyIndex--;
    }

    else if(key=='>') {

      if(
        historyIndex <
        historyCount-1
      ) {

        historyIndex++;
      }
    }

    else if(key=='=') {

      loadHistory();

      return;
    }

    else if(key=='C') {

      historyMode = false;

      renderDisplay();

      return;
    }

    showHistory();

    return;
  }

  // ==================================================
  // NORMAL MODE
  // ==================================================

  switch(key) {

    // ===== CLEAR =====

    case 'C':

      clearExpr();

      break;

    // ===== BACKSPACE =====

    case 'B':

      backspace();

      break;

    // ===== LEFT =====

    case '<':

      if(cursorPos > 0)
        cursorPos--;

      break;

    // ===== RIGHT =====

    case '>':

      if(cursorPos < exprLen)
        cursorPos++;

      break;

    // ===== LOCK =====

    case 'L':

      locked = true;

      passPos = 0;

      entered[0] = '\0';

      break;

    // ===== HISTORY =====

    case 'H':

      if(historyCount > 0) {

        historyMode = true;

        historyIndex =
          historyCount-1;

        showHistory();
      }

      return;

    // ===== SQRT =====

    case 'R':

      ans =
        sqrt(
          evaluatePrefix()
        );

      dtostrf(
        ans,
        0,
        2,
        expr
      );

      exprLen =
        strlen(expr);

      cursorPos =
        exprLen;

      break;

    // ===== PERCENT =====

    case '%':

      ans =
        evaluatePrefix()/100.0;

      dtostrf(
        ans,
        0,
        2,
        expr
      );

      exprLen =
        strlen(expr);

      cursorPos =
        exprLen;

      break;

    // ===== EVALUATE =====

    case '=':

      if(exprLen == 0)
        break;

      infixToPrefix();

      showPrefix();

      ans =
        evaluatePrefix();

      saveHistory();

      dtostrf(
        ans,
        0,
        2,
        expr
      );

      exprLen =
        strlen(expr);

      cursorPos =
        exprLen;

      break;

    // ===== DEFAULT =====

    default:

      insertChar(key);
  }

  renderDisplay();
}