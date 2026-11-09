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
final int DPIofYourDeviceScreen = 120; //you will need to look up the DPI or PPI of your device to make sure you get the right scale. Or play around with this value.
final float sizeOfInputArea = DPIofYourDeviceScreen*1; //aka, 1.0 inches square!
PImage watch;
PImage finger;

//Variables for my silly implementation. You can delete this:
String alphabet = "abcdefghijklmnopqrstuvwxyz";
int currentLetterIndex = 0; // index into the alphabet, avoiding char/ASCII conversion in Processing.js

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

    //example design draw code - arrows, letter, delete and space in the 1" area
    float x = width/2;
    float y = height/2;
    fill(0);
    rect(x-sizeOfInputArea/2, y-sizeOfInputArea/2, sizeOfInputArea, sizeOfInputArea); //keep the 1" input area black
    fill(255);
    textAlign(CENTER, CENTER);
    textSize(12);
    text("DELETE", x, y-sizeOfInputArea*0.40); //delete previous character
    text("SPACE", x, y+sizeOfInputArea*0.40); //enter a space

    //draw bold arrows using lines rather than font glyphs for consistent appearance
    stroke(255);
    strokeWeight(5);
    strokeCap(ROUND);
    strokeJoin(ROUND);
    float arrowY = y;
    float leftX = x-sizeOfInputArea*0.34;
    float rightX = x+sizeOfInputArea*0.34;
    line(leftX+12, arrowY, leftX-12, arrowY); //left arrow shaft
    line(leftX-12, arrowY, leftX-3, arrowY-10); //left arrow upper head
    line(leftX-12, arrowY, leftX-3, arrowY+10); //left arrow lower head
    line(rightX-12, arrowY, rightX+12, arrowY); //right arrow shaft
    line(rightX+12, arrowY, rightX+3, arrowY-10); //right arrow upper head
    line(rightX+12, arrowY, rightX+3, arrowY+10); //right arrow lower head
    noStroke(); //restore original drawing style

    fill(255);
    textSize(42);
    text(alphabet.substring(currentLetterIndex, currentLetterIndex+1), x, y-3); //single tap enters the selected letter
    textSize(20); //restore the original font size
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

  float x = width/2-sizeOfInputArea/2;
  float y = height/2-sizeOfInputArea/2;
  float fifth = sizeOfInputArea/5;

  if (didMouseClick(x, y+fifth, sizeOfInputArea/3, fifth*3)) //check if click in left arrow
  {
    currentLetterIndex = (currentLetterIndex + 25) % 26; // wrap backward from a to z
  }
  else if (didMouseClick(x+sizeOfInputArea*2/3, y+fifth, sizeOfInputArea/3, fifth*3)) //check if click in right arrow
  {
    currentLetterIndex = (currentLetterIndex + 1) % 26; // wrap forward from z to a
  }
  else if (didMouseClick(x+sizeOfInputArea/3, y+fifth, sizeOfInputArea/3, fifth*3)) //check if click occurred in letter area
  {
    currentTyped += alphabet.substring(currentLetterIndex, currentLetterIndex+1); // insert selected letter
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
