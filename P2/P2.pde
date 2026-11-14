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

// Variables for 4 letter grouping
String alphabet = "abcdefghijklmnopqrstuvwxyz";
int currentPage = 0; // index of the 4-letter group (0 to 6)
final int lettersPerPage = 4;
final int totalPages = 7; // 26 letters grouped by 4 gives 7 pages

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
  watch = loadImage("data/watchhand3smaller.png");
  //finger = loadImage("pngeggSmaller.png"); //not using this
  phrases = loadStrings("data/phrases2.txt"); //load the phrase set into memory
  // Comment out because of JavaScript compatibility issues with Collections.shuffle()
  // Collections.shuffle(Arrays.asList(phrases), new Random()); //randomize the order of the phrases with no seed
  shufflePhrases();
  //Collections.shuffle(Arrays.asList(phrases), new Random(100)); //randomize the order of the phrases with seed 100; same order every time, useful for testing
 
  // orientation(LANDSCAPE); // Android only //can also be PORTRAIT - sets orientation on android device
  size(800, 800); //Sets the size of the app. You should modify this to your device's native size. Many phones today are 1080 wide by 1920 tall.
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
    float freebieErrors = lettersExpectedTotal*.05; //no penalty if errors are under 5% of chars
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

    // Determine next expected character and guidance state ---
    String nextExpectedChar = "";
    int targetPage = -1;
    boolean highlightLeft = false;
    boolean highlightRight = false;
    boolean highlightSpace = false;

    if (currentTyped.length() < currentPhrase.length()) {
      nextExpectedChar = currentPhrase.substring(currentTyped.length(), currentTyped.length() + 1).toLowerCase();
      if (nextExpectedChar.equals(" ")) {
        highlightSpace = true;
      } else {
        int targetCharIdx = alphabet.indexOf(nextExpectedChar);
        if (targetCharIdx != -1) {
          targetPage = targetCharIdx / lettersPerPage;
          if (targetPage != currentPage) {
            // Calculate shortest wrap-around direction across pages
            int forwardDist = (targetPage - currentPage + totalPages) % totalPages;
            int backwardDist = (currentPage - targetPage + totalPages) % totalPages;
            if (backwardDist <= forwardDist) {
              highlightLeft = true;
            } else {
              highlightRight = true;
            }
          }
        }
      }
    }

    //example design draw code - arrows, letters, delete and space in the 1" area
    float x = width/2;
    float y = height/2;
    fill(0);
    rect(x-sizeOfInputArea/2, y-sizeOfInputArea/2, sizeOfInputArea, sizeOfInputArea); //keep the 1" input area black
    textAlign(CENTER, CENTER);
    textSize(12);
    fill(255);
    text("DELETE", x, y-sizeOfInputArea*0.40); //delete previous character

    // Highlight SPACE in green if the next expected character is a space
    if (highlightSpace) fill(0, 255, 0);
    else fill(255);
    text("SPACE", x, y+sizeOfInputArea*0.40); //enter a space

    // Arrows with directional highlighting
    strokeWeight(3); // smaller stroke weight (was 5)
    strokeCap(ROUND);
    strokeJoin(ROUND);
    float arrowY = y;
    float leftX = x - sizeOfInputArea * 0.36f;
    float rightX = x + sizeOfInputArea * 0.36f;

    // Draw Left Arrow
    if (highlightLeft) stroke(0, 255, 0);
    else stroke(255);
    line(leftX + 7, arrowY, leftX - 7, arrowY);       // smaller left arrow shaft
    line(leftX - 7, arrowY, leftX - 1, arrowY - 6);   // smaller left arrow upper head
    line(leftX - 7, arrowY, leftX - 1, arrowY + 6);   // smaller left arrow lower head

    // Draw Right Arrow
    if (highlightRight) stroke(0, 255, 0);
    else stroke(255);
    line(rightX - 7, arrowY, rightX + 7, arrowY);     // smaller right arrow shaft
    line(rightX + 7, arrowY, rightX + 1, arrowY - 6); // smaller right arrow upper head
    line(rightX + 7, arrowY, rightX + 1, arrowY + 6); // smaller right arrow lower head
    noStroke(); //restore original drawing style

    // Draw 2 by 2 grid for 4 letters
    float gridX = x - sizeOfInputArea / 6.0f;
    float gridY = y - (sizeOfInputArea * 3.0f / 10.0f);
    float gridW = sizeOfInputArea / 3.0f;
    float gridH = (sizeOfInputArea * 3.0f) / 5.0f;
    float cellW = gridW / 2.0f;
    float cellH = gridH / 2.0f;

    // Subtle divider lines for the 2 by 2 letter grid
    stroke(80);
    strokeWeight(1);
    line(gridX + cellW, gridY, gridX + cellW, gridY + gridH);
    line(gridX, gridY + cellH, gridX + gridW, gridY + cellH);
    noStroke();

    textSize(22);
    int startIdx = currentPage * lettersPerPage;
    for (int i = 0; i < lettersPerPage; i++) {
      int charIdx = startIdx + i;
      if (charIdx < alphabet.length()) {
        int col = i % 2;
        int row = i / 2;
        float cx = gridX + col * cellW + cellW / 2.0f;
        float cy = gridY + row * cellH + cellH / 2.0f;
        String letter = alphabet.substring(charIdx, charIdx + 1);

        // --- NEW CODE: Highlight target letter in green when on its page ---
        if (letter.equals(nextExpectedChar)) {
          fill(0, 255, 0);
        } else {
          fill(255);
        }
        text(letter, cx, cy - 2);
      }
    }
    textSize(20); //restore the original font size
  }
 
  //drawFinger(); //no longer needed as we'll be deploying to an actual touchscreen device
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

  float x = width/2-sizeOfInputArea/2;
  float y = height/2-sizeOfInputArea/2;
  float fifth = sizeOfInputArea/5;

  if (didMouseClick(x, y+fifth, sizeOfInputArea/3, fifth*3)) //check if click in left arrow
  {
    currentPage = (currentPage + totalPages - 1) % totalPages; // wrap backward one page
  }
  else if (didMouseClick(x+sizeOfInputArea*2/3, y+fifth, sizeOfInputArea/3, fifth*3)) //check if click in right arrow
  {
    currentPage = (currentPage + 1) % totalPages; // wrap forward one page
  }
  else if (didMouseClick(x+sizeOfInputArea/3, y+fifth, sizeOfInputArea/3, fifth*3)) //check if click occurred in 2x2 letter area
  {
    // Check which of the 4 cells was clicked
    float gridX = x + sizeOfInputArea / 3.0f;
    float gridY = y + fifth;
    float cellW = (sizeOfInputArea / 3.0f) / 2.0f;
    float cellH = (fifth * 3.0f) / 2.0f;

    for (int i = 0; i < lettersPerPage; i++) {
      int col = i % 2;
      int row = i / 2;
      if (didMouseClick(gridX + col * cellW, gridY + row * cellH, cellW, cellH)) {
        int charIdx = currentPage * lettersPerPage + i;
        if (charIdx < alphabet.length()) {
          currentTyped += alphabet.substring(charIdx, charIdx + 1); // insert tapped letter
        }
      }
    }
  }
  else if (didMouseClick(x, y, sizeOfInputArea, fifth)) //DELETE removes the last entered character
  {
    if (currentTyped.length()>0)
      currentTyped = currentTyped.substring(0, currentTyped.length()-1);
  }
  else if (didMouseClick(x, y+fifth*4, sizeOfInputArea, fifth)) //SPACE inserts a space
  {
    currentTyped += " ";
  }

  //You are allowed to have a next button outside the 1" area
  if (didMouseClick(600, 600, 200, 200)) //check if click is in next button
  {
    nextTrial(); //if so, advance to next trial
  }
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
    float freebieErrors = lettersExpectedTotal*.05; //no penalty if errors are under 5% of chars
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
  currentPhrase = phrases[currTrialNum]; // load the next phrase!
  currentPage = 0; // reset back to the first page ('a'-'d') on a new trial
  //currentPhrase = "abc"; // uncomment this to override the test phrase (useful for debugging)
}

//probably shouldn't touch this - should be same for all teams.
void drawWatch()
{
  float watchscale = DPIofYourDeviceScreen/138.0; //normalizes the image size
  pushMatrix();
  translate(width/2, height/2);
  scale(watchscale);
  imageMode(CENTER);
  image(watch, 0, 0);
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
