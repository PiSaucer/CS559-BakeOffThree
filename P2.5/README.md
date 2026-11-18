# Prototype 2.5: Handwriting + CNN

The **same** `P2.5.pde` runs in the Processing IDE's **Java Mode** and in the browser through Processing.js. The COSC 559 bakeoff trial logic, edit-distance scoring, WPM, penalty calculations, original comments, the one-inch input region, and the HTML touch-to-mouse scaffold are retained.

The only substantial replacement is the original scrolling alphabet picker. It is now a one-letter handwriting pad with three ranked CNN suggestions. The **DELETE** and **SPACE** hit targets remain inside the 1-inch square. SPACE inserts a space without changing the entered words.

## Files

```text
P2.5/                       <-- Sketch folder must be named P2.5
├── P2.5.pde                # All drawing, Java + web inference and scoring
├── index.html                # Original web scaffold, with touch-drag forwarding
├── processing.min.js         # Processing.js runtime
├── data/
│   ├── letter_model.txt      # Trained CNN weights (required)
│   ├── phrases2.txt          # Phrase set for trials
│   └── watchhand3smaller.png # Watch background image
└── tools/
    ├── train_model.py        # Train CNN using EMNIST Letters and local fonts
    ├── download_emnist.py    # Download and verify EMNIST Letters
    ├── emnist/               # Downloaded EMNIST dataset (created automatically)
    └── training-fonts/       # Local TTF/OTF fonts, organized into subfolders
        ├── Alan/
        ├── arimo/
        ├── caladea/
        ├── carlito/
        ├── comicneue/
        └── ...
```

**Important:** Keep `processing.min.js`, `phrases2.txt`, and `watchhand3smaller.png` in their existing locations. The trained `letter_model.txt` file must be present in `data/` for handwriting recognition to work.

## Run in Java Mode (desktop)

1. Open the folder's **`P2.5.pde`** with the [Processing IDE](https://processing.org/download/).
2. Choose **Java Mode** (the standard Processing mode).
3. Click **Run**. No internet, TensorFlow.js, Python, libraries, or JavaScript bridge is required for this mode.

## Run in a browser (Processing.js)

1. Keep the provided `index.html` and `processing.min.js` in the same folder.
2. Serve the `P2.5` directory, e.g. `python3 -m http.server 8000`.
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

* A **real 26-class convolutional neural network** is trained *offline* using [EMNIST Letters](https://www.nist.gov/itl/products-and-services/emnist-dataset) handwritten characters and randomly transformed glyphs from local computer fonts.
* The resulting `data/letter_model.txt` contains its actual trained weights, not a handcrafted alphabet lookup.
* Both Processing modes load those weights and run the **same** two 3×3 convolution/2×2 max-pool stages and 26-way fully connected/softmax output in the PDE.
* Input strokes are normalized and rasterized to 28×28 grayscale in plain Processing. The three most probable letters are ranked on the screen.
* There is no word-level correction or prediction: the selected letters are preserved as entered.

**Accuracy limitation:** Although EMNIST Letters provides real handwritten samples, performance on the dataset does not guarantee accuracy with actual users drawing on the one-inch input area. The softmax percentages are model scores, not calibrated real-world confidence. Test with actual users to evaluate recognition accuracy.

**Note:** Existing `letter_model.txt` weights remain font-only until the model is retrained using EMNIST.

## Training the model (optional)

Model training uses Python with `torch`, `Pillow`, and `numpy`. These dependencies are **not** needed to run the delivered PDE.

First, download EMNIST Letters:

```bash
python3 tools/download_emnist.py
```

This downloads and verifies the dataset in `tools/emnist/`. The download only needs to be completed once.

Then train using **both EMNIST Letters and the fonts in `tools/training-fonts/`**:

```bash
python3 tools/train_model.py \
    --dataset both \
    --epochs 30 \
    --batch-size 128 \
    --learning-rate 0.001 \
    --font-fraction 0.25 \
    --patience 6 \
    --device mps
```

The `--font-fraction 0.25` option allocates approximately 25% of training samples per epoch to synthetic fonts and 75% to EMNIST handwriting. Training runs locally without downloading additional data.

The trained model is exported to `data/letter_model.txt`, replacing the previous weights.

To train with only one dataset, use `--dataset fonts` or `--dataset emnist`.

## Validation and limitations

* Java syntax/type checking against stub Processing API methods: **passed**.
* Compiled and executed the **actual Java CNN inference** and handwriting methods in a minimal Java test harness: **passed** (the model returned ranked predictions for a hand-coded V-shaped stroke).
* EMNIST loading, label conversion, dataset splitting, and combined training/export passed offline tests using synthetic fixtures.
* The original course scoring equations and evaluation flow remain unchanged; two decimal constants were suffixed with `f` for strict Java float compilation.
* **Full EMNIST training on the actual dataset and end-to-end testing in both Processing runtimes still require verification.**

## Upstream data attribution

[EMNIST](https://www.nist.gov/itl/products-and-services/emnist-dataset) is an extension of MNIST containing handwritten character images derived from the NIST Special Database 19.

Cohen, G., Afshar, S., Tapson, J., & van Schaik, A. (2017). *EMNIST: An Extension of MNIST to Handwritten Letters*.

The training pipeline combines EMNIST Letters with locally stored font-generated samples. The exported model remains compatible with both Processing Java Mode and Processing.js.
