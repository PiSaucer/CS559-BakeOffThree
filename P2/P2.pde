// import java.util.Arrays;
// import java.util.Collections;
// import java.util.Random;
/* @pjs preload="data/watchhand3smaller.png"; */
/* @pjs font="Arial"; */

String[] phrases; //contains all of the phrases
int totalTrialNum = 2; //the total number of phrases to be tested - set this low for testing. Might be ~10 for the real bakeoff!
int currTrialNum = 0; // the current trial number (indexes into trials array above)
float startTime = 0; // time starts when the first letter is entered
float finishTime = 0; // records the time of when the final trial ends
float lastTime = 0; //the timestamp of when the last trial was completed
float lettersEnteredTotal = 0; //a running total of the number of letters the user has entered (need this for final WPM computation)
float lettersExpectedTotal = 0; //a running total of the number of letters expected (correct phrases)
float errorsTotal = 0; //a running total of the number of errors (when hitting next)
String currentPhrase = ""; //the current target phrase
String currentTyped = ""; //what the user has typed so far
final int DPIofYourDeviceScreen = 128; //you will need to look up the DPI or PPI of your device to make sure you get the right scale. Or play around with this value.
final float sizeOfInputArea = DPIofYourDeviceScreen * 1.0f; //aka, 1.0 inches square!
PImage watch;
PImage finger;

// Handwriting input (replaces the original alphabet picker).
// All text-entry controls remain inside the 1" square.
String[] rankedLetters = {"", "", ""};
int[] rankedScores = {0, 0, 0};
boolean candidatesReady = false;
boolean drawingLetter = false;
boolean hasInk = false;
int lastStrokeTime = 0; // detect a pause after multi-stroke letters in either runtime
int pointCount = 0;
float[] pointXs = new float[2048];
float[] pointYs = new float[2048];
String modelStatus = "";

// Small CNN classifier, trained on augmented computer fonts (26 A-Z classes).
// These are plain float weights so identical inference runs in Java and Processing.js.
final int MODEL_WEIGHT_COUNT = 21658;
float[] modelWeights = new float[MODEL_WEIGHT_COUNT];
boolean modelReady = false;


// Keep the pad's top/bottom buttons and central handwriting area distinct.
float inputX() { return width/2-sizeOfInputArea/2; }
float inputY() { return height/2-sizeOfInputArea/2; }
float buttonH() { return sizeOfInputArea*0.21f; }

// Added for JavaScript compatibility, since Collections.shuffle() is not available in JS mode
void shufflePhrases() {
  for (int i = phrases.length - 1; i > 0; i--) {
    int j = (int)random(i + 1);

    String temp = phrases[i];
    phrases[i] = phrases[j];
    phrases[j] = temp;
  }
}

//You can modify anything in here. This is just a basic implementation.
void setup()
{
  //noCursor();
  size(800, 800); //Sets the size of the app. You should modify this to your device's native size. Many phones today are 1080 wide by 1920 tall.
  watch = loadImage("data/watchhand3smaller.png");
  //finger = loadImage("pngeggSmaller.png"); //not using this
  phrases = loadStrings("data/phrases2.txt"); //load the phrase set into memory
  // Comment out because of JavaScript compatibility issues with Collections.shuffle()
  // Collections.shuffle(Arrays.asList(phrases), new Random()); //randomize the order of the phrases with no seed
  shufflePhrases();
  loadLetterModel(); // shared neural network in Processing (Java + browser)
  //Collections.shuffle(Arrays.asList(phrases), new Random(100)); //randomize the order of the phrases with seed 100; same order every time, useful for testing
 
  // orientation(LANDSCAPE); // Android only //can also be PORTRAIT - sets orientation on android device
  // Comment out because of JavaScript compatibility issues with createFont()
  // textFont(createFont("Arial", 20)); //set the font to arial 24. Creating fonts is expensive, so make difference sizes once in setup, not draw
  textFont(createFont("Arial", 20));
  textSize(20);
  noStroke(); //my code doesn't use any strokes
}

//You can modify anything in here. This is just a basic implementation.
void draw()
{
  background(255); //clear background
  // A short pause means several pen strokes (i, t, etc.) form one letter.
  // No JavaScript callbacks are required for recognition.
  if (hasInk && !drawingLetter && !candidatesReady &&
      millis()-lastStrokeTime > 500 && modelReady) {
    classifyHandwriting();
  }
  
   //check to see if the user finished. You can't change the score computation.
  if (finishTime!=0)
  {
    fill(0);
    textAlign(CENTER);
    text("Trials complete!",400,200); //output
    text("Total time taken: " + (finishTime - startTime),400,220); //output
    text("Total letters entered: " + lettersEnteredTotal,400,240); //output
    text("Total letters expected: " + lettersExpectedTotal,400,260); //output
    text("Total errors entered: " + errorsTotal,400,280); //output
    float wpm = (lettersEnteredTotal/5.0f)/((finishTime - startTime)/60000f); //FYI - 60K is number of milliseconds in minute
    text("Raw WPM: " + wpm,400,300); //output
    float freebieErrors = lettersExpectedTotal*.05f; //no penalty if errors are under 5% of chars
    text("Freebie errors: " + nf(freebieErrors,1,3),400,320); //output
    float penalty = max(errorsTotal-freebieErrors, 0) * .5f;
    text("Penalty: " + penalty,400,340);
    text("WPM w/ penalty: " + (wpm-penalty),400,360); //yes, minus, because higher WPM is better
    return;
  }
  
  drawWatch(); //draw watch background
  fill(0);
  rect(width/2-sizeOfInputArea/2, height/2-sizeOfInputArea/2, sizeOfInputArea, sizeOfInputArea); //input area should be 1" by 1"
  

  if (startTime==0 & !mousePressed)
  {
    fill(128);
    textAlign(CENTER);
    text("Click to start time!", 280, 150); //display this messsage until the user clicks!
  }

  if (startTime==0 & mousePressed)
  {
    nextTrial(); //start the trials!
  }

  if (startTime!=0)
  {
    //feel free to change the size and position of the target/entered phrases and next button 
    textAlign(LEFT); //align the text left
    fill(128);
    text("Phrase " + (currTrialNum+1) + " of " + totalTrialNum, 70, 50); //draw the trial count
    fill(128);
    text("Target:   " + currentPhrase, 70, 100); //draw the target string
    text("Entered:  " + currentTyped +"|", 70, 140); //draw what the user has entered thus far 

    //draw very basic next button
    fill(255, 0, 0);
    rect(600, 600, 200, 200); //draw next button
    fill(255);
    text("NEXT > ", 650, 650); //draw next label

    // Handwriting area replaces the original arrow/letter selector.
    // DELETE and SPACE still use the original top and bottom of the 1" square.
    float x = inputX();
    float y = inputY();
    fill(0);
    rect(x, y, sizeOfInputArea, sizeOfInputArea); //keep the 1" input area black
    fill(255);
    textAlign(CENTER, CENTER);
    textSize(12);
    text("DELETE", x+sizeOfInputArea/2, y+buttonH()/2);
    text("SPACE", x+sizeOfInputArea/2, y+sizeOfInputArea-buttonH()/2);
    stroke(105);
    strokeWeight(1);
    line(x, y+buttonH(), x+sizeOfInputArea, y+buttonH());
    line(x, y+sizeOfInputArea-buttonH(), x+sizeOfInputArea, y+sizeOfInputArea-buttonH());
    noStroke();

    if (candidatesReady) {
      // Three ranked, tappable neural-network predictions inside the legal input area.
      for (int i = 0; i < 3; i++) {
        float cx = x + (i + 0.5f) * sizeOfInputArea/3;
        fill(i == 0 ? color(120, 235, 150) : color(255));
        textSize(22);
        text(rankedLetters[i], cx, y+sizeOfInputArea/2-5);
        fill(180);
        textSize(10);
        text("#"+(i+1)+" " + rankedScores[i]+"%", cx, y+sizeOfInputArea/2+19);
      }
    } else if (hasInk) {
      // The white strokes stay visible until the ML model returns candidates.
      stroke(255);
      strokeWeight(5);
      strokeCap(ROUND);
      for (int i = 0; i < pointCount; i++) {
        if (pointXs[i] < 0) continue; // -1 marks a new stroke
        if (i > 0 && pointXs[i-1] >= 0)
          line(pointXs[i-1], pointYs[i-1], pointXs[i], pointYs[i]);
        else
          point(pointXs[i], pointYs[i]);
      }
      noStroke();
    } else {
      fill(175);
      textSize(12);
      text("DRAW", x+sizeOfInputArea/2, y+sizeOfInputArea/2);
    }
    textSize(20); //restore the original font size
    textAlign(LEFT);
    fill(95);
    if (candidatesReady)
      text("Letter predictions: tap #1, #2, or #3 in the square", 70, 190);
    else if (hasInk)
      text(modelStatus.length()>0 ? modelStatus : "Recognizing handwriting...", 70, 190);
    else
      text("Draw one letter at a time in the black square", 70, 190);
  }
 
 
  //drawFinger(); //no longer needed as we'll be deploying to an actual touschreen device
}

//my terrible implementation you can entirely replace
boolean didMouseClick(float x, float y, float w, float h) //simple function to do hit testing
{
  return (mouseX > x && mouseX<x+w && mouseY>y && mouseY<y+h); //check to see if it is in button bounds
}

//my terrible implementation you can entirely replace
void mousePressed()
{
  if (startTime==0 || finishTime!=0) //do not type before trials start or after they finish
    return;

  float x = inputX();
  float y = inputY();
  float h = buttonH();

  //You are allowed to have a next button outside the 1" area
  if (didMouseClick(600, 600, 200, 200)) //check if click is in next button
  {
    nextTrial(); //if so, advance to next trial
    return;
  }

  if (didMouseClick(x, y, sizeOfInputArea, h)) //DELETE removes last entered character
  {
    if (hasInk || candidatesReady)
      clearHandwriting(); //first cancel a pending letter, if present
    else if (currentTyped.length()>0)
      currentTyped = currentTyped.substring(0, currentTyped.length()-1);
  }
  else if (didMouseClick(x, y+sizeOfInputArea-h, sizeOfInputArea, h)) //SPACE inserts a space
  {
    if (hasInk && !candidatesReady) {
      // SPACE may accept a handwritten letter immediately instead of dropping ink.
      if (!modelReady) return;
      classifyHandwriting();
    }
    if (candidatesReady) acceptCandidate(0); //best candidate, if not selected yet
    if (currentTyped.length() > 0 && !currentTyped.substring(currentTyped.length()-1).equals(" ")) {
      // No automatic word correction: keep the letters exactly as entered.
      currentTyped += " ";
    }
  }
  else if (didMouseClick(x, y+h, sizeOfInputArea, sizeOfInputArea-2*h))
  {
    if (candidatesReady) {
      int index = (int)((mouseX-x)/(sizeOfInputArea/3));
      acceptCandidate(max(0, min(index, 2))); //tap one of the ranked alternatives
    } else {
      drawingLetter = true;
      if (pointCount > 0) addPoint(-1, -1); //separate multi-stroke letters
      addDrawingPoint(mouseX, mouseY);
    }
  }
}

// Read mouse movements from the existing Processing.js canvas.
// No additional drawing controls or click targets are needed.
void mouseDragged()
{
  if (drawingLetter)
    addDrawingPoint(mouseX, mouseY);
}

void mouseReleased()
{
  if (drawingLetter) {
    addDrawingPoint(mouseX, mouseY);
    lastStrokeTime = millis();
  }
  drawingLetter = false;
}

void addPoint(float x, float y)
{
  if (pointCount >= pointXs.length) return;
  pointXs[pointCount] = x;
  pointYs[pointCount] = y;
  pointCount++;
}

void addDrawingPoint(float x, float y)
{
  // Clamp to the middle of the 1" square so strokes never cover the buttons.
  x = constrain(x, inputX()+3, inputX()+sizeOfInputArea-3);
  y = constrain(y, inputY()+buttonH()+3, inputY()+sizeOfInputArea-buttonH()-3);
  if (pointCount > 0 && pointXs[pointCount-1] >= 0) {
    if (dist(x, y, pointXs[pointCount-1], pointYs[pointCount-1]) < 1) return;
  }
  addPoint(x, y);
  hasInk = true;
  lastStrokeTime = millis();
  modelStatus = "";
}

void clearHandwriting()
{
  pointCount = 0;
  hasInk = false;
  drawingLetter = false;
  candidatesReady = false;
  modelStatus = "";
}


void acceptCandidate(int which)
{
  if (!candidatesReady) return;
  currentTyped += rankedLetters[which].toLowerCase();
  clearHandwriting();
}

// === Cross-platform ML: trained CNN, implemented in plain Processing ===
// The saved weights were learned from augmented font samples, NOT EMNIST handwriting.
// Every operation below is regular Java/Processing; Processing.js translates it too.
void loadLetterModel()
{
  String[] lines = loadStrings("data/letter_model.txt");
  if (lines == null || lines.length < 2 || !lines[0].equals("ML-CNN-1")) {
    modelStatus = "Missing data/letter_model.txt";
    return;
  }
  int index = 0;
  for (int i = 1; i < lines.length; i++) {
    String[] values = splitTokens(lines[i], " \t");
    for (int j = 0; j < values.length; j++) {
      if (index >= MODEL_WEIGHT_COUNT) {
        modelStatus = "Invalid model size";
        return;
      }
      modelWeights[index++] = parseFloat(values[j]);
    }
  }
  modelReady = index == MODEL_WEIGHT_COUNT;
  modelStatus = modelReady ? "" : "Incomplete model weights";
  println(modelReady ? "Handwriting ML model loaded" : modelStatus);
}

// Generate the same 28x28 input format on desktop and web from saved stroke points.
// Normalize the handwritten glyph into a centered ~21-pixel square.
float[] rasterizeHandwriting()
{
  float minX=99999, minY=99999, maxX=-99999, maxY=-99999;
  for (int i=0; i<pointCount; i++) {
    if (pointXs[i] < 0) continue;
    minX=min(minX,pointXs[i]);
    minY=min(minY,pointYs[i]);
    maxX=max(maxX,pointXs[i]);
    maxY=max(maxY,pointYs[i]);
  }
  float[] ink = new float[784];
  if (minX>maxX) return ink;
  float w=max(2,maxX-minX);
  float h=max(2,maxY-minY);
  float scale=21.0f/max(w,h);
  float xPad=(28-w*scale)*0.5f;
  float yPad=(28-h*scale)*0.5f;
  for (int i=0; i<pointCount; i++) {
    if (pointXs[i] < 0) continue;
    float sx=xPad+(pointXs[i]-minX)*scale;
    float sy=yPad+(pointYs[i]-minY)*scale;
    if (i>0 && pointXs[i-1]>=0) {
      float ex=xPad+(pointXs[i-1]-minX)*scale;
      float ey=yPad+(pointYs[i-1]-minY)*scale;
      int steps=max(1,(int)(dist(sx,sy,ex,ey)*2.0f));
      for (int k=0; k<=steps; k++) {
        float t=(float)k/steps;
        putInk(ink,lerp(ex,sx,t),lerp(ey,sy,t));
      }
    } else putInk(ink,sx,sy);
  }
  return ink;
}

// Anti-aliased circular pen: black background is zero, white ink near one.
void putInk(float[] inkBuffer, float x, float y)
{
  int x0=max(0,(int)floor(x)-2), x1=min(27,(int)ceil(x)+2);
  int y0=max(0,(int)floor(y)-2), y1=min(27,(int)ceil(y)+2);
  for (int yy=y0; yy<=y1; yy++) {
    for (int xx=x0; xx<=x1; xx++) {
      float d=dist(xx+0.5f, yy+0.5f, x, y);
      float a=constrain(1.6f-d,0,1);
      int n=yy*28+xx;
      inkBuffer[n]=max(inkBuffer[n],a);
    }
  }
}

void classifyHandwriting()
{
  if (!modelReady || !hasInk || drawingLetter || candidatesReady) return;
  float[] input = rasterizeHandwriting();
  // Layer 1: 3x3 padded convolution, ReLU, 2x2 max-pooling.
  float[] p1 = new float[8*14*14];
  for (int oc=0; oc<8; oc++) {
    for (int py=0; py<14; py++) for (int px=0; px<14; px++) {
      float maxPool=0;
      for (int dy=0; dy<2; dy++) for (int dx=0; dx<2; dx++) {
        int y=py*2+dy, x=px*2+dx;
        float acc=modelWeights[72+oc];
        for (int ky=0; ky<3; ky++) for (int kx=0; kx<3; kx++) {
          int iy=y+ky-1, ix=x+kx-1;
          if (iy>=0 && ix>=0 && iy<28 && ix<28)
            acc+=modelWeights[oc*9+ky*3+kx]*input[iy*28+ix];
        }
        maxPool=max(maxPool,acc);
      }
      p1[oc*196+py*14+px]=maxPool;
    }
  }
  // Layer 2: another 3x3 padded convolution, ReLU, 2x2 max-pooling.
  float[] p2 = new float[16*7*7];
  for (int oc=0; oc<16; oc++) {
    for (int py=0; py<7; py++) for (int px=0; px<7; px++) {
      float maxPool=0;
      for (int dy=0; dy<2; dy++) for (int dx=0; dx<2; dx++) {
        int y=py*2+dy, x=px*2+dx;
        float acc=modelWeights[1232+oc]; // 72+8+1152 + oc
        for (int ic=0; ic<8; ic++) {
          int base=80+(oc*8+ic)*9;
          for (int ky=0; ky<3; ky++) for (int kx=0; kx<3; kx++) {
            int iy=y+ky-1, ix=x+kx-1;
            if (iy>=0 && ix>=0 && iy<14 && ix<14)
              acc+=modelWeights[base+ky*3+kx]*p1[ic*196+iy*14+ix];
          }
        }
        maxPool=max(maxPool,acc);
      }
      p2[oc*49+py*7+px]=maxPool;
    }
  }
  // Layer 3: 26-way fully connected output (A-Z), followed by softmax.
  float[] logits = new float[26];
  float peak=-999999;
  for (int c=0; c<26; c++) {
    float acc=modelWeights[21632+c];
    int base=1248+c*784;
    for (int j=0; j<784; j++) acc+=modelWeights[base+j]*p2[j];
    logits[c]=acc;
    peak=max(peak,acc);
  }
  float total=0;
  for (int c=0; c<26; c++) {
    logits[c]=exp(logits[c]-peak);
    total+=logits[c];
  }
  // Sorted top three model predictions, with softmax scores.
  for (int rank=0; rank<3; rank++) {
    int best=-1;
    float bestScore=-1;
    for (int c=0; c<26; c++) {
      if (logits[c]>bestScore) { best=c; bestScore=logits[c]; }
    }
    rankedLetters[rank]="ABCDEFGHIJKLMNOPQRSTUVWXYZ".substring(best,best+1);
    rankedScores[rank]=(int)round(100*bestScore/total);
    logits[best]=-1;
  }
  candidatesReady=true;
  modelStatus="";
}

void nextTrial()
{
  if (currTrialNum >= totalTrialNum) //check to see if experiment is done
    return; //if so, just return

  if (startTime!=0 && finishTime==0) //in the middle of trials
  {
    println("==================");
    println("Phrase " + (currTrialNum+1) + " of " + totalTrialNum); //output
    println("Target phrase: " + currentPhrase); //output
    println("Phrase length: " + currentPhrase.length()); //output
    println("User typed: " + currentTyped); //output
    println("User typed length: " + currentTyped.length()); //output
    println("Number of errors: " + computeLevenshteinDistance(currentTyped.trim(), currentPhrase.trim())); //trim whitespace and compute errors
    println("Time taken on this trial: " + (millis()-lastTime)); //output
    println("Time taken since beginning: " + (millis()-startTime)); //output
    println("==================");
    lettersExpectedTotal+=currentPhrase.trim().length();
    lettersEnteredTotal+=currentTyped.trim().length();
    errorsTotal+=computeLevenshteinDistance(currentTyped.trim(), currentPhrase.trim());
  }

  //probably shouldn't need to modify any of this output / penalty code.
  if (currTrialNum == totalTrialNum-1) //check to see if experiment just finished
  {
    finishTime = millis();
    println("==================");
    println("Trials complete!"); //output
    println("Total time taken: " + (finishTime - startTime)); //output
    println("Total letters entered: " + lettersEnteredTotal); //output
    println("Total letters expected: " + lettersExpectedTotal); //output
    println("Total errors entered: " + errorsTotal); //output

    float wpm = (lettersEnteredTotal/5.0f)/((finishTime - startTime)/60000f); //FYI - 60K is number of milliseconds in minute
    float freebieErrors = lettersExpectedTotal*.05f; //no penalty if errors are under 5% of chars
    float penalty = max(errorsTotal-freebieErrors, 0) * .5f;
    
    println("Raw WPM: " + wpm); //output
    println("Freebie errors: " + freebieErrors); //output
    println("Penalty: " + penalty);
    println("WPM w/ penalty: " + (wpm-penalty)); //yes, minus, becuase higher WPM is better
    println("==================");

    currTrialNum++; //increment by one so this mesage only appears once when all trials are done
    return;
  }

  if (startTime==0) //first trial starting now
  {
    println("Trials beginning! Starting timer..."); //output we're done
    startTime = millis(); //start the timer!
  } 
  else
    currTrialNum++; //increment trial number

  lastTime = millis(); //record the time of when this trial ended
  currentTyped = ""; //clear what is currently typed preparing for next trial
  clearHandwriting(); //clear the drawing pad for the next trial
  currentPhrase = phrases[currTrialNum]; // load the next phrase!
  //currentPhrase = "abc"; // uncomment this to override the test phrase (useful for debugging)
}

//probably shouldn't touch this - should be same for all teams.
void drawWatch()
{
  float watchscale = DPIofYourDeviceScreen/138.0f; //normalizes the image size
  pushMatrix();
  translate(width/2, height/2);
  scale(watchscale);
  imageMode(CENTER);
  if (watch != null) image(watch, 0, 0); // permit testing while optional artwork is absent
  popMatrix();
}

//probably shouldn't touch this - should be same for all teams.
void drawFinger()
{
  float fingerscale = DPIofYourDeviceScreen/150f; //normalizes the image size
  pushMatrix();
  translate(mouseX, mouseY);
  scale(fingerscale);
  imageMode(CENTER);
  image(finger,52,341);
  if (mousePressed)
     fill(0);
  else
     fill(255);
  ellipse(0,0,5,5);

  popMatrix();
  }
  

//=========SHOULD NOT NEED TO TOUCH THIS METHOD AT ALL!==============
int computeLevenshteinDistance(String phrase1, String phrase2) //this computers error between two strings
{
  int[][] distance = new int[phrase1.length() + 1][phrase2.length() + 1];

  for (int i = 0; i <= phrase1.length(); i++)
    distance[i][0] = i;
  for (int j = 1; j <= phrase2.length(); j++)
    distance[0][j] = j;

  for (int i = 1; i <= phrase1.length(); i++)
    for (int j = 1; j <= phrase2.length(); j++)
      distance[i][j] = min(min(distance[i - 1][j] + 1, distance[i][j - 1] + 1), distance[i - 1][j - 1] + ((phrase1.charAt(i - 1) == phrase2.charAt(j - 1)) ? 0 : 1));

  return distance[phrase1.length()][phrase2.length()];
}
