#!/usr/bin/env python3
# train_model.py
# Train the Processing-compatible ML CNN on downloaded EMNIST Letters and local fonts.
import argparse
import gzip
import random
import struct
import time
from pathlib import Path

import numpy as np
import torch
from torch import nn
from torch.nn import functional as F
from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
KEYS = ('c1.weight', 'c1.bias', 'c2.weight', 'c2.bias', 'fc.weight', 'fc.bias')

def arguments():
    p = argparse.ArgumentParser(description='Train ML CNN on local EMNIST Letters and fonts; export ML-CNN-1 weights.',
                                formatter_class=argparse.ArgumentDefaultsHelpFormatter)
    p.add_argument('--dataset', choices=('both', 'emnist', 'fonts'), default='both')
    p.add_argument('--fonts-dir', type=Path, default=ROOT/'tools'/'training-fonts')
    p.add_argument('--font-limit', type=int, default=0, help='0 means all fonts')
    p.add_argument('--samples-per-case', type=int, default=8)
    p.add_argument('--validation-fraction', type=float, default=.2, help='Held-out fonts')
    p.add_argument('--emnist-dir', type=Path, default=ROOT/'tools'/'emnist')
    p.add_argument('--emnist-validation-fraction', type=float, default=.1)
    p.add_argument('--emnist-limit', type=int, default=0, help='0 uses all handwriting samples; for quick smoke tests')
    p.add_argument('--font-fraction', type=float, default=.25, help='Fraction of training batch indices from fonts')
    p.add_argument('--epochs', type=int, default=12)
    p.add_argument('--batch-size', type=int, default=256)
    p.add_argument('--learning-rate', type=float, default=.003)
    p.add_argument('--weight-decay', type=float, default=.0001)
    p.add_argument('--patience', type=int, default=0)
    p.add_argument('--seed', type=int, default=42)
    p.add_argument('--threads', type=int, default=4)
    p.add_argument('--device', choices=('auto', 'cpu', 'cuda', 'mps'), default='auto')
    p.add_argument('--output', type=Path, default=ROOT/'data'/'letter_model.txt')
    a = p.parse_args()
    for k in ('epochs', 'batch_size', 'samples_per_case', 'threads'):
        if getattr(a, k) < 1: p.error(f'--{k.replace("_", "-")} must be positive')
    if a.font_limit < 0 or a.patience < 0 or (a.emnist_limit and a.emnist_limit < 26):
        p.error('limits/patience must be nonnegative and --emnist-limit must be 0 or >=26')
    if not all(0 < v < 1 for v in (a.validation_fraction, a.emnist_validation_fraction, a.font_fraction)):
        p.error('validation and font fractions must be strictly between 0 and 1')
    if a.learning_rate <= 0 or a.weight_decay < 0: p.error('invalid optimizer settings')
    return a

def require_local_emnist(directory: Path) -> Path:
    """Never download data while training; use download_emnist.py first."""
    directory = directory.expanduser().resolve()
    names = [f'emnist-letters-{split}-{kind}-idx{3 if kind == "images" else 1}-ubyte.gz'
             for split in ('train', 'test') for kind in ('images', 'labels')]
    missing = [name for name in names if not (directory/name).is_file()]
    if missing:
        raise ValueError(
            f'EMNIST files missing from {directory}: {", ".join(missing)}\n'
            'Run python tools/download_emnist.py first. Training does not download datasets.'
        )
    return directory

def emnist_partition(directory, split):
    base = directory / f'emnist-letters-{split}-'
    image_path = Path(str(base)+'images-idx3-ubyte.gz')
    label_path = Path(str(base)+'labels-idx1-ubyte.gz')
    with gzip.open(image_path, 'rb') as f:
        head = f.read(16)
        if len(head)!=16: raise ValueError('Invalid image IDX header')
        magic,n,h,w = struct.unpack('>IIII', head)
        if magic != 2051 or (h,w)!=(28,28): raise ValueError('Unexpected IDX image shape')
        buf = f.read()
    if len(buf)!=n*784: raise ValueError('Invalid image IDX byte count')
    with gzip.open(label_path, 'rb') as f:
        head = f.read(8)
        if len(head)!=8: raise ValueError('Invalid label IDX header')
        lm, count=struct.unpack('>II',head)
        labels = np.frombuffer(f.read(),dtype=np.uint8)
    if lm!=2049 or count!=n or len(labels)!=n or not np.all((labels>=1)&(labels<=26)):
        raise ValueError('Invalid EMNIST Letters labels (expected 1-26)')
    # NIST pixels are stored transposed. Processing writes upright images.
    images = np.frombuffer(buf,dtype=np.uint8).reshape(n,28,28).transpose(0,2,1).copy()
    return torch.from_numpy(images[:,None]), torch.from_numpy((labels.astype(np.int64)-1).copy())

def split_emnist(x, y, val_fraction, seed, limit=0):
    rng=np.random.default_rng(seed); labels=y.numpy(); train=[]; valid=[]
    for cls in range(26):
        ids=np.flatnonzero(labels==cls)
        if len(ids)<2: raise ValueError(f'Not enough examples of class {cls}')
        rng.shuffle(ids)
        n=max(1,min(len(ids)-1,round(len(ids)*val_fraction)))
        valid.extend(ids[:n]); train.extend(ids[n:])
    if limit and limit<len(train):
        pool=np.asarray(train); selected=[]; each,extra=divmod(limit,26)
        for cls in range(26): selected.extend(pool[labels[pool]==cls][:each+(cls<extra)])
        train=selected
    rng.shuffle(train);rng.shuffle(valid)
    return x[train],y[train],x[valid],y[valid]

def available_fonts(directory, limit, rng):
    directory=directory.expanduser().resolve()
    if not directory.is_dir(): raise ValueError(f'Fonts folder not found: {directory}. Use --dataset emnist instead.')
    paths=sorted((f for f in directory.rglob('*') if f.is_file() and f.suffix.lower() in ('.ttf','.otf')),
                 key=lambda f:str(f).lower())
    fonts=[]
    for f in paths:
        try:
            if ImageFont.truetype(str(f),64).getbbox('Agz') is not None: fonts.append(f)
        except (ValueError,OSError) as exc: print(f'Skipping {f}: {exc}')
    rng.shuffle(fonts)
    if limit: fonts=fonts[:limit]
    if len(fonts)<2: raise ValueError('Need at least two readable font files for held-out font validation')
    return fonts

def glyph(letter, font_path, rng):
    font=ImageFont.truetype(str(font_path),rng.randint(56,85))
    img=Image.new('L',(160,160),0)
    draw=ImageDraw.Draw(img)
    box=draw.textbbox((0,0),letter,font=font)
    draw.text((12-box[0],12-box[1]),letter,font=font,fill=255)
    crop=img.getbbox()
    if crop is None: raise ValueError(f'Blank font glyph {font_path}: {letter}')
    img=img.crop(crop); w,h=img.size; scale=max(w,h)
    neww=max(2,round(w/scale*rng.randint(17,23)*rng.uniform(.85,1.12)))
    newh=max(2,round(h/scale*rng.randint(17,23)*rng.uniform(.90,1.13)))
    img=img.resize((min(25,neww),min(25,newh)),Image.Resampling.BILINEAR)
    if rng.random()<.2: img=img.filter(ImageFilter.MaxFilter(3))
    if rng.random()<.1 and min(img.size)>=3:
        eroded=img.filter(ImageFilter.MinFilter(3))
        before=np.count_nonzero(np.asarray(img)>16); after=np.count_nonzero(np.asarray(eroded)>16)
        if after>=max(4,round(before*.2)): img=eroded
    canvas=Image.new('L',(44,44),0)
    canvas.paste(img,((44-img.width)//2,(44-img.height)//2))
    rotated=canvas.rotate(rng.uniform(-14,14),resample=Image.Resampling.BILINEAR)
    if rotated.getbbox(): canvas=rotated
    crop=canvas.getbbox()
    if crop is None: raise ValueError(f'Blank augmented glyph {font_path}: {letter}')
    canvas=canvas.crop(crop)
    if max(canvas.size)>24:
        s=24/max(canvas.size)
        canvas=canvas.resize((max(1,round(canvas.width*s)),max(1,round(canvas.height*s))),Image.Resampling.BILINEAR)
    out=Image.new('L',(28,28),0)
    out.paste(canvas,((28-canvas.width)//2+rng.randint(-2,2),(28-canvas.height)//2+rng.randint(-2,2)))
    if not out.getbbox(): raise ValueError(f'Blank final glyph {font_path}: {letter}')
    return np.asarray(out,dtype=np.uint8)

def font_dataset(fonts, count, seed):
    rng=random.Random(seed); images=[];labels=[]
    for cls in range(26):
        for path in fonts:
            for letter in (chr(65+cls),chr(97+cls)):
                for _ in range(count): images.append(glyph(letter,path,rng));labels.append(cls)
    return torch.from_numpy(np.stack(images)[:,None]),torch.tensor(labels,dtype=torch.long)

class Net(nn.Module):
    '''Must match P2.pde and ML-CNN-1 weight order.'''
    def __init__(self):
        super().__init__()
        self.c1=nn.Conv2d(1,8,3,padding=1)
        self.c2=nn.Conv2d(8,16,3,padding=1)
        self.fc=nn.Linear(16*7*7,26)
    def forward(self,x):
        x=F.max_pool2d(F.relu(self.c1(x)),2)
        x=F.max_pool2d(F.relu(self.c2(x)),2)
        return self.fc(x.reshape(x.size(0),-1))

def device_for(name):
    if name=='auto': name=('cuda' if torch.cuda.is_available() else
                          'mps' if hasattr(torch.backends,'mps') and torch.backends.mps.is_available() else 'cpu')
    if name=='cuda' and not torch.cuda.is_available(): raise ValueError('CUDA unavailable')
    if name=='mps' and not (hasattr(torch.backends,'mps') and torch.backends.mps.is_available()):
        raise ValueError('Apple MPS unavailable')
    return torch.device(name)

@torch.inference_mode()
def evaluate(net,x,y,bs,device):
    net.eval(); loss=0;correct=0
    for start in range(0,len(y),bs):
        xb=x[start:start+bs].to(device=device,dtype=torch.float32)/255
        yb=y[start:start+bs].to(device)
        logits=net(xb)
        loss+=F.cross_entropy(logits,yb,reduction='sum').item()
        correct+=(logits.argmax(1)==yb).sum().item()
    return loss/len(y),correct/len(y)

def export_model(net,path):
    path=path.expanduser().resolve();path.parent.mkdir(parents=True,exist_ok=True)
    with path.open('w',encoding='utf-8',newline='\n') as out:
        out.write('ML-CNN-1\n')
        state=net.cpu().state_dict()
        for key in KEYS:
            values=state[key].detach().numpy().ravel()
            for start in range(0,len(values),64):
                out.write(' '.join(f'{float(v):.9g}' for v in values[start:start+64])+'\n')
    print(f'Saved {path} ({path.stat().st_size:,} bytes)')

def main():
    args=arguments();random.seed(args.seed);np.random.seed(args.seed);torch.manual_seed(args.seed)
    torch.set_num_threads(args.threads)
    if torch.cuda.is_available(): torch.cuda.manual_seed_all(args.seed)
    device=device_for(args.device)
    print(f'Dataset: {args.dataset}; device: {device}; seed: {args.seed}',flush=True)
    em_train=em_valid=em_test=fo_train=fo_valid=None
    if args.dataset in ('both','emnist'):
        directory=require_local_emnist(args.emnist_dir)
        x,y=emnist_partition(directory,'train')
        xet,yet,xev,yev=split_emnist(x,y,args.emnist_validation_fraction,args.seed,args.emnist_limit)
        em_train=(xet,yet);em_valid=(xev,yev); em_test=emnist_partition(directory,'test')
        print(f'EMNIST Letters: {len(yet):,} training, {len(yev):,} validation, '
              f'{len(em_test[1]):,} official test; 0-based labels, upright pixels',flush=True)
        del x,y
    if args.dataset in ('both','fonts'):
        rng=random.Random(args.seed); fonts=available_fonts(args.fonts_dir,args.font_limit,rng)
        n=max(1,min(len(fonts)-1,round(len(fonts)*args.validation_fraction)))
        train_fonts,valid_fonts=fonts[n:],fonts[:n]
        fo_train=font_dataset(train_fonts,args.samples_per_case,args.seed+1)
        fo_valid=font_dataset(valid_fonts,args.samples_per_case,args.seed+2)
        print(f'Fonts: {len(train_fonts)} train / {len(valid_fonts)} held out; '
              f'{len(fo_train[1]):,} train glyphs, {len(fo_valid[1]):,} valid glyphs',flush=True)
    if args.dataset=='both':
        xt=torch.cat((em_train[0],fo_train[0]));yt=torch.cat((em_train[1],fo_train[1]))
        em_len=len(em_train[1]);font_draws=round(em_len*args.font_fraction/(1-args.font_fraction))
        print(f'Each epoch: {em_len:,} EMNIST + {font_draws:,} sampled fonts',flush=True)
    elif args.dataset=='emnist':xt,yt=em_train
    else:xt,yt=fo_train
    net=Net().to(device);opt=torch.optim.AdamW(net.parameters(),lr=args.learning_rate,weight_decay=args.weight_decay)
    best_acc=-1.; best_loss=float('inf'); best_epoch=0;best_state=None;stale=0
    for epoch in range(1,args.epochs+1):
        start=time.perf_counter();net.train()
        if args.dataset=='both':
            ids=torch.cat((torch.randperm(em_len),torch.randint(len(fo_train[1]),(font_draws,))+em_len))
            ids=ids[torch.randperm(len(ids))]
        else:ids=torch.randperm(len(yt))
        correct=0;total_loss=0
        for batch in ids.split(args.batch_size):
            xb=xt[batch].to(device=device,dtype=torch.float32)/255
            yb=yt[batch].to(device)
            opt.zero_grad(set_to_none=True)
            scores=net(xb);loss=F.cross_entropy(scores,yb);loss.backward();opt.step()
            correct+=(scores.argmax(1)==yb).sum().item();total_loss+=loss.item()*len(batch)
        primary=em_valid if em_valid is not None else fo_valid
        vl,va=evaluate(net,*primary,args.batch_size,device)
        note=f'EMNIST validation={va:.1%}' if em_valid is not None else f'font validation={va:.1%}'
        if fo_valid is not None and em_valid is not None:
            _,fa=evaluate(net,*fo_valid,args.batch_size,device)
            note+=f' | font validation={fa:.1%}'
        improved=va>best_acc+1e-8 or (abs(va-best_acc)<=1e-8 and vl<best_loss)
        if improved:
            best_acc,best_loss,best_epoch=va,vl,epoch
            best_state={k:v.detach().cpu().clone() for k,v in net.state_dict().items()}
            stale=0
        else:stale+=1
        print(f'Epoch {epoch}/{args.epochs}: loss={total_loss/len(ids):.4f} '
              f'train acc={correct/len(ids):.1%} | {note} | '
              f'{time.perf_counter()-start:.1f}s'+(' *best' if improved else ''),flush=True)
        if args.patience and stale>=args.patience:
            print(f'Early stopping after {args.patience} unimproved epochs',flush=True);break
    net.load_state_dict(best_state)
    print(f'Best validation accuracy {best_acc:.1%} at epoch {best_epoch}',flush=True)
    if em_test is not None:
        tl,ta=evaluate(net,*em_test,args.batch_size,device)
        print(f'Official EMNIST TEST (evaluated after selection): loss={tl:.4f}, accuracy={ta:.1%}',flush=True)
    export_model(net,args.output)

if __name__=='__main__':
    try:
        main()
    except (ValueError,OSError,EOFError) as exc:
        raise SystemExit(f'Error: {exc}') from exc
