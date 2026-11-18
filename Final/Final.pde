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

// 3 pages with a 3x3 grid 
String alphabet = "abcdefghijklmnopqrstuvwxyz ";
int currentPage = 0; 
final int lettersPerPage = 9;
final int totalPages = 3;
final int gridCols = 3;
final int gridRows = 3;

// Drag and swipe for page switching
float pressStartX = 0;
float pressStartY = 0;
boolean isDragging = false;
final float SWIPE_THRESHOLD = sizeOfInputArea * 0.15f; // minimum drag distance to count as a page swipe

// Added for JavaScript compatibility, since Collections.shuffle() is not available in JS mode
void shufflePhrases() {
  for (int i = phrases.length - 1; i > 0; i--) {
    int j = (int)random(i + 1);

    String temp = phrases[i];
    phrases[i] = phrases[j];
    phrases[j] = temp;
  }
}

void setup()
{
  //noCursor();
  watch = loadImage("data/watchhand3smaller.png");
  phrases = loadStrings("data/phrases2.txt");
  shufflePhrases();

  size(800, 800);
  textFont(createFont("Arial", 20));
  textSize(20);
  noStroke();
}

void draw()
{
  background(255); //clear background
  
  //check to see if the user finished. You can't change the score computation.
  if (finishTime!=0)
  {
    fill(0);
    textAlign(CENTER);
    text("Trials complete!",400,200);
    text("Total time taken: " + (finishTime - startTime),400,220);
    text("Total letters entered: " + lettersEnteredTotal,400,240);
    text("Total letters expected: " + lettersExpectedTotal,400,260);
    text("Total errors entered: " + errorsTotal,400,280);
    float wpm = (lettersEnteredTotal/5.0f)/((finishTime - startTime)/60000f);
    text("Raw WPM: " + wpm,400,300);
    float freebieErrors = lettersExpectedTotal*.05;
    text("Freebie errors: " + nf(freebieErrors,1,3),400,320);
    float penalty = max(errorsTotal-freebieErrors, 0) * .5f;
    text("Penalty: " + penalty,400,340);
    text("WPM w/ penalty: " + (wpm-penalty),400,360);
    return;
  }
  
  drawWatch(); //draw watch background
  fill(0);
  rect(width/2-sizeOfInputArea/2, height/2-sizeOfInputArea/2, sizeOfInputArea, sizeOfInputArea);
  
  if (startTime==0 & !mousePressed)
  {
    fill(128);
    textAlign(CENTER);
    text("Click to start time!", 280, 150);
  }

  if (startTime==0 & mousePressed)
  {
    nextTrial();
  }

  if (startTime!=0)
  {
    textAlign(LEFT);
    fill(128);
    text("Phrase " + (currTrialNum+1) + " of " + totalTrialNum, 70, 50);
    fill(128);
    text("Target:   " + currentPhrase, 70, 100);
    text("Entered:  " + currentTyped +"|", 70, 140);

    //draw very basic next button
    fill(255, 0, 0);
    rect(600, 600, 200, 200);
    fill(255);
    text("NEXT > ", 650, 650);

    // 3x3 grid setup for javascript
    float boxX = width/2 - sizeOfInputArea/2;
    float boxY = height/2 - sizeOfInputArea/2;
    float gridH = sizeOfInputArea * 0.78f;       
    float bottomBarH = sizeOfInputArea * 0.22f;  // Bottom 22& of screen to be space and delete
    float cellW = sizeOfInputArea / 3.0f;
    float cellH = gridH / 3.0f;

    // Keep the 1" input area black
    fill(0);
    rect(boxX, boxY, sizeOfInputArea, sizeOfInputArea);

    // Draw DELETE (bottom-left) and SPACE (bottom-right) backgrounds
    float bottomY = boxY + gridH;
    float halfW = sizeOfInputArea / 2.0f;
    fill(40);
    rect(boxX, bottomY, sizeOfInputArea, bottomBarH);

    // Draw clean, continuous grid lines for the 3x3 grid and bottom buttons
    stroke(120);
    strokeWeight(1);
    noFill();
    rect(boxX, boxY, sizeOfInputArea, sizeOfInputArea); // Outer border
    // 2 Vertical divider lines for the 3x3 grid
    line(boxX + cellW, boxY, boxX + cellW, boxY + gridH);
    line(boxX + cellW * 2.0f, boxY, boxX + cellW * 2.0f, boxY + gridH);
    // 2 Horizontal divider lines for the 3x3 grid + 1 bottom bar divider
    line(boxX, boxY + cellH, boxX + sizeOfInputArea, boxY + cellH);
    line(boxX, boxY + cellH * 2.0f, boxX + sizeOfInputArea, boxY + cellH * 2.0f);
    line(boxX, bottomY, boxX + sizeOfInputArea, bottomY);
    // Center divider between DELETE and SPACE
    line(boxX + halfW, bottomY, boxX + halfW, bottomY + bottomBarH);
    noStroke();

    // Draw the 9 letters centered in each cell
    int startIdx = currentPage * lettersPerPage;
    textAlign(CENTER, CENTER);
    textSize(18);
    fill(255);

    for (int i = 0; i < lettersPerPage; i++) {
      int col = i % gridCols;
      int row = int(i / gridCols); // MUST use int(...) in Processing.js so it doesn't do float division!

      float cx = boxX + col * cellW + cellW / 2.0f;
      float cy = boxY + row * cellH + cellH / 2.0f;

      int charIdx = startIdx + i;
      if (charIdx < alphabet.length()) {
        String label = alphabet.substring(charIdx, charIdx + 1);
        if (label.equals(" ")) label = "_"; // Show underscore for the bonus space cell on page 3
        text(label, cx, cy - 1);
      }
    }

    // Draw delete and space labels
    fill(255);
    textSize(11);
    text("DELETE", boxX + halfW / 2.0f, bottomY + bottomBarH / 2.0f);
    text("SPACE", boxX + halfW + halfW / 2.0f, bottomY + bottomBarH / 2.0f);

    textSize(20); // restore default text size
  }
}

boolean didMouseClick(float x, float y, float w, float h)
{
  return (mouseX > x && mouseX < x + w && mouseY > y && mouseY < y + h);
}

void mousePressed()
{
  if (startTime == 0 || finishTime != 0)
    return;

  pressStartX = mouseX;
  pressStartY = mouseY;
  isDragging = false;
}

void mouseDragged()
{
  if (startTime == 0 || finishTime != 0)
    return;

  if (abs(mouseX - pressStartX) > SWIPE_THRESHOLD) {
    isDragging = true;
  }
}

void mouseReleased()
{
  if (startTime == 0 || finishTime != 0)
    return;

  float boxX = width/2 - sizeOfInputArea/2;
  float boxY = height/2 - sizeOfInputArea/2;
  float gridH = sizeOfInputArea * 0.78f;
  float bottomBarH = sizeOfInputArea * 0.22f;
  float cellW = sizeOfInputArea / 3.0f;
  float cellH = gridH / 3.0f;

  boolean startedInInput = (pressStartX >= boxX && pressStartX <= boxX + sizeOfInputArea &&
                            pressStartY >= boxY && pressStartY <= boxY + sizeOfInputArea);

  // Drag and swipe between page
  if (isDragging && startedInInput)
  {
    float dx = mouseX - pressStartX;
    if (dx < -SWIPE_THRESHOLD) {
      currentPage = (currentPage + 1) % totalPages; // Drag left -> next page
    } else if (dx > SWIPE_THRESHOLD) {
      currentPage = (currentPage + totalPages - 1) % totalPages; // Drag right -> previous page
    }
    isDragging = false;
    return;
  }

  // Clicking buttons of the 3x3 grid in the page
  if (didMouseClick(boxX, boxY, sizeOfInputArea, gridH))
  {
    for (int i = 0; i < lettersPerPage; i++) {
      int col = i % gridCols;
      int row = int(i / gridCols); // MUST use int(...) in Processing.js!

      if (didMouseClick(boxX + col * cellW, boxY + row * cellH, cellW, cellH)) {
        int charIdx = currentPage * lettersPerPage + i;
        if (charIdx < alphabet.length()) {
          currentTyped += alphabet.substring(charIdx, charIdx + 1);
        }
        return;
      }
    }
  }
  else if (didMouseClick(boxX, boxY + gridH, sizeOfInputArea / 2.0f, bottomBarH)) // Bottom-left: DELETE
  {
    if (currentTyped.length() > 0)
      currentTyped = currentTyped.substring(0, currentTyped.length() - 1);
  }
  else if (didMouseClick(boxX + sizeOfInputArea / 2.0f, boxY + gridH, sizeOfInputArea / 2.0f, bottomBarH)) // Bottom-right: SPACE
  {
    currentTyped += " ";
  }

  // Check if click is in the red NEXT button outside the 1" area
  if (didMouseClick(600, 600, 200, 200))
  {
    nextTrial();
  }
}

void nextTrial()
{
  if (currTrialNum >= totalTrialNum)
    return;

  if (startTime!=0 && finishTime==0)
  {
    println("==================");
    println("Phrase " + (currTrialNum+1) + " of " + totalTrialNum);
    println("Target phrase: " + currentPhrase);
    println("Phrase length: " + currentPhrase.length());
    println("User typed: " + currentTyped);
    println("User typed length: " + currentTyped.length());
    println("Number of errors: " + computeLevenshteinDistance(currentTyped.trim(), currentPhrase.trim()));
    println("Time taken on this trial: " + (millis()-lastTime));
    println("Time taken since beginning: " + (millis()-startTime));
    println("==================");
    lettersExpectedTotal+=currentPhrase.trim().length();
    lettersEnteredTotal+=currentTyped.trim().length();
    errorsTotal+=computeLevenshteinDistance(currentTyped.trim(), currentPhrase.trim());
  }

  if (currTrialNum == totalTrialNum-1)
  {
    finishTime = millis();
    println("==================");
    println("Trials complete!");
    println("Total time taken: " + (finishTime - startTime));
    println("Total letters entered: " + lettersEnteredTotal);
    println("Total letters expected: " + lettersExpectedTotal);
    println("Total errors entered: " + errorsTotal);

    float wpm = (lettersEnteredTotal/5.0f)/((finishTime - startTime)/60000f);
    float freebieErrors = lettersExpectedTotal*.05;
    float penalty = max(errorsTotal-freebieErrors, 0) * .5f;
    
    println("Raw WPM: " + wpm);
    println("Freebie errors: " + freebieErrors);
    println("Penalty: " + penalty);
    println("WPM w/ penalty: " + (wpm-penalty));
    println("==================");

    currTrialNum++;
    return;
  }

  if (startTime==0)
  {
    println("Trials beginning! Starting timer...");
    startTime = millis();
  } 
  else
    currTrialNum++;

  lastTime = millis();
  currentTyped = "";
  currentPhrase = phrases[currTrialNum];
  currentPage = 0; // reset back to page 0 on a new trial
}

void drawWatch()
{
  float watchscale = DPIofYourDeviceScreen/138.0;
  pushMatrix();
  translate(width/2, height/2);
  scale(watchscale);
  imageMode(CENTER);
  image(watch, 0, 0);
  popMatrix();
}

void drawFinger()
{
  float fingerscale = DPIofYourDeviceScreen/150f;
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

int computeLevenshteinDistance(String phrase1, String phrase2)
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
