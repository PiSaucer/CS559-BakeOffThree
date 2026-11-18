# MLTest — one Processing sketch for Java Mode and Processing.js

The **same** `MLTest.pde` runs in the Processing IDE's **Java Mode** and in the browser through Processing.js. The COSC 559 bakeoff trial logic, edit-distance scoring, WPM, penalty calculations, original comments, the one-inch input region, and the HTML touch-to-mouse scaffold are retained.

The only substantial replacement is the original scrolling alphabet picker. It is now a one-letter handwriting pad with three ranked CNN suggestions. The **DELETE** and **SPACE** hit targets remain inside the 1-inch square. SPACE inserts a space without changing the entered words.

## Files

```text
MLTest/                      <-- Sketch folder must be named MLTest
├── MLTest.pde               # All drawing, Java + web inference and scoring
├── index.html               # Original web scaffold, with touch-drag forwarding
├── processing.min.js        # COPY from your original web project (not bundled)
├── data/
│   ├── letter_model.txt     # Bundled, locally trained CNN weights (required)
│   ├── phrases2.txt         # DEMO phrases; replace with instructor's actual data
│   └── watchhand3smaller.png # TRANSPARENT PLACEHOLDER; replace with original image
└── tools/
    ├── train_model.py       # Optional: rebuild the model (requires Python/PyTorch)
    ├── check_java_syntax.py # API-stub Java syntax check, not Processing IDE
    └── smoke_test.py        # API-stub Java inference/handwriting test
```

**Important:** The original `processing.min.js`, watch image, and phrase file were not supplied. The included phrase file is **only a test sample**, and the transparent watch image is **only a placeholder** so the browser's `@pjs preload` can resolve. **Replace both with your instructor's files for the real bakeoff.** Also copy `processing.min.js` from your existing website into the sketch folder.

## Run in Java Mode (desktop)

1. Open the folder's **`MLTest.pde`** with the [Processing IDE](https://processing.org/download/).
2. Choose **Java Mode** (the standard Processing mode).
3. Click **Run**. No internet, TensorFlow.js, Python, libraries, or JavaScript bridge is required for this mode.

## Run in a browser (Processing.js)

1. Keep the provided `index.html` and add your existing `processing.min.js` to the same folder.
2. Serve the `MLTest` directory, e.g. `python3 -m http.server 8000`.
3. Open **`http://localhost:8000/`**.

Do not load directly via `file://`: browsers can block the resource fetches used by Processing.js. No TensorFlow.js or `letter-ml.js` is required; the network is unnecessary once `processing.min.js` is local.

## Interaction

1. Click/tap to start the first trial, just as in the original sketch.
2. In the one-inch black square, draw **one** printed letter (upper- or lowercase); for multi-stroke glyphs such as `t`, lift and draw again within about **500 ms**.
3. After a half-second pause, select the #1, #2, or #3 ranked prediction by touching the middle of the square.
4. **DELETE** cancels the pending letter first; otherwise it deletes the last committed character.
5. **SPACE** accepts the top pending letter (if necessary), then appends a space without changing the word.
6. **NEXT** advances the experiment, leaving the original phrase-by-phrase measurements and scoring in place.

## How the ML works

- A **real 26-class convolutional neural network** is trained *offline* on randomly transformed glyphs from locally installed computer fonts.
- The resulting ~247 KB `data/letter_model.txt` contains its actual trained weights, not a handcrafted alphabet lookup.
- Both Processing modes load those weights and run the **same** two 3×3 convolution/2×2 max-pool stages and 26-way fully connected/softmax output in the PDE.
- Input strokes are normalized and rasterized to 28×28 grayscale in plain Processing. The three most probable letters are ranked on the screen.
- There is no word-level correction or prediction: the selected letters are preserved as entered.

**Accuracy limitation:** Training used synthetic *font* glyphs, **not handwritten EMNIST samples**. A holdout of similar generated glyphs achieved ~89% accuracy, which does **not** predict accuracy with real handwritten letters. The softmax percentages are model scores, not calibrated real-world confidence. Test with actual users, and retrain on [EMNIST Letters](https://www.nist.gov/itl/products-and-services/emnist-dataset) if higher handwriting accuracy is needed. The architecture allows retraining without changing either runtime's inference logic.

`tools/train_model.py` is optional: it reproduces a synthetically-trained model from locally installed Latin fonts, using `torch`, `Pillow`, and `numpy`. These dependencies are *not* needed to run the delivered PDE.

## Validation and limitations

- Java syntax/type checking against stub Processing API methods: **passed**.
- Compiled and executed the **actual Java CNN inference** and handwriting methods in a minimal Java test harness: **passed** (the model returned ranked predictions for a hand-coded V-shaped stroke).
- The original course scoring equations and evaluation flow remain unchanged; two decimal constants were suffixed with `f` for strict Java float compilation.
- **Not yet verified with the actual Processing IDE or Processing.js in a browser** because the Processing runtime files were not among the provided assets. Verify both locally before the actual class bakeoff.

## Upstream data attribution

The ML weights were trained for this example on computer-font glyphs and should not be represented as an EMNIST-trained model. EMNIST is a useful possible future training source: Cohen et al., *EMNIST: An Extension of MNIST to Handwritten Letters* (2017).
