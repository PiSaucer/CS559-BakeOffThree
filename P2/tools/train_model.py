#!/usr/bin/env python3
# train_model.py

import argparse
import copy
import random
import time
from pathlib import Path

import numpy as np
import torch
import torch.nn as nn
import torch.nn.functional as F
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[1]
MODEL_KEYS = ("c1.weight", "c1.bias", "c2.weight", "c2.bias", "fc.weight", "fc.bias")

def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Train and export a font-based letter recognition CNN for MLTest.",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    data = parser.add_argument_group("training data")
    data.add_argument("--fonts-dir", type=Path,
                      default=ROOT / "tools" / "training-fonts", metavar="DIR",
                      help="Recursively search this folder for .ttf and .otf font files, "
                           "including fonts in subfolders such as Alan/ and lato/.")
    data.add_argument("--font-limit", type=int, default=0, metavar="N",
                      help="Maximum number of font files to use (0 uses all files).")
    data.add_argument("--samples-per-case", type=int, default=8, metavar="N",
                      help="Augmented samples for each upper/lowercase letter per font.")
    data.add_argument("--validation-fraction", type=float, default=0.2, metavar="F",
                      help="Fraction of font files reserved for validation.")

    train = parser.add_argument_group("training")
    train.add_argument("--epochs", type=int, default=12, help="Number of training epochs.")
    train.add_argument("--batch-size", type=int, default=256, help="Batch size for training.")
    train.add_argument("--learning-rate", type=float, default=0.003, help="Initial learning rate.")
    train.add_argument("--weight-decay", type=float, default=0.0001, help="L2 regularization strength.")
    train.add_argument("--patience", type=int, default=0,
                       help="Early-stop after this many epochs without improvement (0 disables).")
    train.add_argument("--seed", type=int, default=42,
                       help="Random seed for reproducible results.")
    train.add_argument("--threads", type=int, default=4,
                       help="Number of CPU threads used by PyTorch.")
    train.add_argument("--device", choices=("auto", "cpu", "cuda", "mps"),
                       default="auto", help="Training device; auto prefers CUDA/MPS when available.")

    output = parser.add_argument_group("output")
    output.add_argument("--output", type=Path,
                        default=ROOT / "data" / "letter_model.txt",
                        help="Destination text file read with Processing loadStrings().")
    args = parser.parse_args()

    for name in ("epochs", "batch_size", "samples_per_case", "threads"):
        if getattr(args, name) < 1:
            parser.error(f"--{name.replace('_', '-')} must be at least 1")
    if args.font_limit < 0 or args.patience < 0:
        parser.error("--font-limit and --patience cannot be negative")
    if not 0 < args.validation_fraction < 1:
        parser.error("--validation-fraction must be between 0 and 1 (exclusive)")
    if args.learning_rate <= 0 or args.weight_decay < 0:
        parser.error("--learning-rate must be positive and --weight-decay nonnegative")
    return args

def find_fonts(fonts_dir: Path, limit: int, rng: random.Random) -> list[Path]:
    """Load font files exclusively from the local training-fonts directory.

    Subfolders such as Alan/, arimo/, and lato/ are scanned recursively.
    README files and OFL.txt files are ignored. No system font discovery or
    downloads take place.
    """
    fonts_dir = fonts_dir.expanduser().resolve()
    if not fonts_dir.is_dir():
        raise ValueError("Fonts directory not found: {fonts_dir}\nPlace your .ttf files in tools/training-fonts/ or specify --fonts-dir.")

    paths = sorted(
        (p for p in fonts_dir.rglob("*")
         if p.is_file() and p.suffix.lower() in (".ttf", ".otf")),
        key=lambda p: str(p).lower(),
    )
    if not paths:
        raise ValueError(f"No .ttf or .otf files found under {fonts_dir}")

    # Remove unreadable fonts while keeping every usable font, including Alan.
    usable = []
    for path in paths:
        try:
            font = ImageFont.truetype(str(path), 64)
            if font.getbbox("Agz") is not None:
                usable.append(path)
            else:
                print(f"Skipping font with no Latin glyphs: {path.name}", flush=True)
        except (OSError, ValueError) as exc:
            print(f"Skipping unreadable font {path}: {exc}", flush=True)

    if limit:
        rng.shuffle(usable)
        usable = usable[:limit]
    if len(usable) < 2:
        raise ValueError(f"At least two valid font files are needed; found {len(usable)}")
    return usable

def render_glyph(letter: str, font_path: Path, rng: random.Random) -> np.ndarray:
    """Create a 28x28 single-channel glyph with mild geometric augmentation."""
    font = ImageFont.truetype(str(font_path), rng.randint(56, 85))
    img = Image.new("L", (160, 160), 0)
    draw = ImageDraw.Draw(img)
    bbox = draw.textbbox((0, 0), letter, font=font)
    # Offset by the measured bbox so descenders and font bearings aren't clipped.
    draw.text((12 - bbox[0], 12 - bbox[1]), letter, font=font, fill=255)
    box = img.getbbox()
    if box is None:
        raise ValueError(f"Font {font_path.name} rendered a blank glyph: {letter!r}")
    img = img.crop(box)

    w, h = img.size
    s = max(w, h)
    new_w = max(2, round(w / s * rng.randint(17, 23) * rng.uniform(0.85, 1.12)))
    new_h = max(2, round(h / s * rng.randint(17, 23) * rng.uniform(0.90, 1.13)))
    img = img.resize((min(25, new_w), min(25, new_h)), Image.Resampling.BILINEAR)

    if rng.random() < 0.20:
        img = img.filter(ImageFilter.MaxFilter(3))
    if rng.random() < 0.10 and min(img.size) >= 3:
        # MinFilter erodes white strokes against a black background. Narrow
        # letters such as i, l, I, and j can disappear entirely at 28 px.
        # Keep the original instead of introducing a blank, mislabeled sample.
        eroded = img.filter(ImageFilter.MinFilter(3))
        ink_before = np.count_nonzero(np.asarray(img) > 16)
        ink_after = np.count_nonzero(np.asarray(eroded) > 16)
        if ink_after >= max(4, round(ink_before * 0.20)):
            img = eroded

    padded = Image.new("L", (44, 44), 0)
    padded.paste(img, ((44 - img.width) // 2, (44 - img.height) // 2))
    # Keep an unrotated fallback: PIL may erase a very thin stroke when
    # resampling a rotated glyph, especially with lightweight fonts.
    rotated = padded.rotate(rng.uniform(-14, 14), resample=Image.Resampling.BILINEAR)
    if rotated.getbbox() is not None:
        padded = rotated
    box = padded.getbbox()
    if box is None:
        # A truly missing glyph is a font-data problem, not a reason to
        # silently train on a blank image with a letter label.
        raise ValueError(f"Font {font_path.name} produced a blank {letter!r} after resizing")
    padded = padded.crop(box)
    max_dim = max(padded.size)
    if max_dim > 24:
        scale = 24 / max_dim
        padded = padded.resize(
            (max(1, round(padded.width * scale)),
             max(1, round(padded.height * scale))),
            Image.Resampling.BILINEAR,
        )

    out = Image.new("L", (28, 28), 0)
    out.paste(padded, (
        (28 - padded.width) // 2 + rng.randint(-2, 2),
        (28 - padded.height) // 2 + rng.randint(-2, 2),
    ))
    return np.asarray(out, dtype=np.float32) / 255.0

def make_dataset(font_paths: list[Path], samples_per_case: int, seed: int) -> tuple[torch.Tensor, torch.Tensor]:
    rng = random.Random(seed)
    images: list[np.ndarray] = []
    labels: list[int] = []
    for cls in range(26):
        for path in font_paths:
            for char in (chr(65 + cls), chr(97 + cls)):
                for _ in range(samples_per_case):
                    images.append(render_glyph(char, path, rng))
                    labels.append(cls)
    images_array = np.stack(images)[:, None, :, :]
    return torch.from_numpy(images_array), torch.tensor(labels, dtype=torch.long)

class Net(nn.Module):
    """Architecture deliberately kept identical to the Processing PDE loader."""

    def __init__(self) -> None:
        super().__init__()
        self.c1 = nn.Conv2d(1, 8, 3, padding=1)
        self.c2 = nn.Conv2d(8, 16, 3, padding=1)
        self.fc = nn.Linear(16 * 7 * 7, 26)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        x = F.max_pool2d(F.relu(self.c1(x)), 2)
        x = F.max_pool2d(F.relu(self.c2(x)), 2)
        return self.fc(x.reshape(x.size(0), -1))

def choose_device(requested: str) -> torch.device:
    if requested == "auto":
        requested = ("cuda" if torch.cuda.is_available() else "mps" if hasattr(torch.backends, "mps")
                     and torch.backends.mps.is_available() else "cpu")
    if requested == "cuda" and not torch.cuda.is_available():
        raise ValueError("CUDA requested but not available")
    if requested == "mps" and not (hasattr(torch.backends, "mps")
                                  and torch.backends.mps.is_available()):
        raise ValueError("MPS requested but not available")
    return torch.device(requested)

@torch.inference_mode()
def evaluate(model: Net, x: torch.Tensor, y: torch.Tensor, batch_size: int, device: torch.device) -> tuple[float, float]:
    model.eval()
    total_loss, total_correct = 0.0, 0
    for i in range(0, len(y), batch_size):
        xb = x[i:i + batch_size].to(device)
        yb = y[i:i + batch_size].to(device)
        logits = model(xb)
        total_loss += F.cross_entropy(logits, yb, reduction="sum").item()
        total_correct += (logits.argmax(dim=1) == yb).sum().item()
    return total_loss / len(y), total_correct / len(y)

def export_model(model: Net, path: Path) -> None:
    path = path.expanduser().resolve()
    path.parent.mkdir(parents=True, exist_ok=True)
    # No metadata or extra lines: MLTest.pde expects this exact header/order.
    with path.open("w", encoding="utf-8", newline="\n") as handle:
        handle.write("MLTEST-CNN-1\n")
        state = model.cpu().state_dict()
        for key in MODEL_KEYS:
            flat = state[key].detach().numpy().ravel()  # PyTorch native order
            for start in range(0, len(flat), 64):
                handle.write(" ".join(f"{float(v):.9g}" for v in flat[start:start + 64]) + "\n")
    print(f"Saved {path} ({path.stat().st_size:,} bytes)")

def main() -> None:
    args = parse_args()
    random.seed(args.seed)
    np.random.seed(args.seed)
    torch.manual_seed(args.seed)
    torch.set_num_threads(args.threads)
    if torch.cuda.is_available():
        torch.cuda.manual_seed_all(args.seed)

    device = choose_device(args.device)
    split_rng = random.Random(args.seed)
    fonts = find_fonts(args.fonts_dir, args.font_limit, split_rng)
    # Shuffle even when --font-limit=0 so validation is not biased toward
    # alphabetically first directories (Alan, Arimo, Caladea, etc.).
    split_rng.shuffle(fonts)
    print(f"Fonts directory: {args.fonts_dir.expanduser().resolve()}", flush=True)
    validation_count = max(1, min(len(fonts) - 1, round(len(fonts) * args.validation_fraction)))
    valid_fonts, train_fonts = fonts[:validation_count], fonts[validation_count:]

    print(f"Device: {device}; seed: {args.seed}", flush=True)
    print(f"Fonts: {len(train_fonts)} train / {len(valid_fonts)} validation (different font files)", flush=True)
    print("Validation fonts: " + ", ".join(p.name for p in valid_fonts), flush=True)
    x_train, y_train = make_dataset(train_fonts, args.samples_per_case, args.seed + 1)
    x_valid, y_valid = make_dataset(valid_fonts, args.samples_per_case, args.seed + 2)
    print(f"Examples: {len(y_train):,} train / {len(y_valid):,} validation", flush=True)

    model = Net().to(device)
    optimizer = torch.optim.AdamW(model.parameters(), lr=args.learning_rate, weight_decay=args.weight_decay)

    best_accuracy = -1.0
    best_loss = float("inf")
    best_epoch = 0
    best_state = None
    no_improvement = 0

    for epoch in range(1, args.epochs + 1):
        started = time.perf_counter()
        model.train()
        permutation = torch.randperm(len(y_train))
        total_loss, correct = 0.0, 0
        for ids in permutation.split(args.batch_size):
            xb, yb = x_train[ids].to(device), y_train[ids].to(device)
            optimizer.zero_grad(set_to_none=True)
            logits = model(xb)
            loss = F.cross_entropy(logits, yb)
            loss.backward()
            optimizer.step()
            total_loss += loss.item() * len(ids)
            correct += (logits.argmax(dim=1) == yb).sum().item()

        val_loss, val_accuracy = evaluate(model, x_valid, y_valid, args.batch_size, device)
        train_accuracy = correct / len(y_train)
        improved = (val_accuracy > best_accuracy + 1e-8 or (abs(val_accuracy - best_accuracy) <= 1e-8 and val_loss < best_loss))
        if improved:
            best_accuracy, best_loss, best_epoch = val_accuracy, val_loss, epoch
            best_state = copy.deepcopy({k: v.cpu() for k, v in model.state_dict().items()})
            no_improvement = 0
        else:
            no_improvement += 1

        print(f"Epoch {epoch:2}/{args.epochs}: "
              f"train loss={total_loss / len(y_train):.4f} acc={train_accuracy:.1%} | "
              f"valid loss={val_loss:.4f} acc={val_accuracy:.1%} | "
              f"{time.perf_counter() - started:.1f}s"
              + (" *best" if improved else ""), flush=True)
        if args.patience and no_improvement >= args.patience:
            print(f"Early stopping after {args.patience} unimproved epochs")
            break

    if best_state is None:
        raise RuntimeError("Training did not produce a checkpoint")
    model.load_state_dict(best_state)
    print(f"Best held-out-font accuracy: {best_accuracy:.1%} (epoch {best_epoch})")
    export_model(model, args.output)

if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError) as exc:
        raise SystemExit(f"Error: {exc}") from exc
