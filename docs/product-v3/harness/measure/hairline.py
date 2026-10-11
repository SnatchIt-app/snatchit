import sys
import numpy as np
from PIL import Image
# Characterise the 144 px gutter signal: is it a full-bleed rule or clipped content?
for p in sys.argv[1:]:
    a = np.asarray(Image.open(p).convert('RGB'), dtype=np.float32)
    band = a[440:, :, :]
    q = (a[440:, :, :] // 8).astype(np.uint16)
    key = q[:,:,0]*1024 + q[:,:,1]*32 + q[:,:,2]
    v,c = np.unique(key, return_counts=True); k = int(v[int(np.argmax(c))])
    bg = np.array([(k//1024)*8+4, ((k//32)%32)*8+4, (k%32)*8+4], dtype=np.float32)
    d = np.sqrt(((band-bg)**2).sum(axis=2))
    ink = d > 45
    ys = np.where(ink[:, 1131:].any(axis=1))[0]
    print(f"\n{p.split('/')[-1]}  bg={tuple(int(x) for x in bg)}")
    if ys.size == 0:
        print("   no gutter ink at T=45"); continue
    for y in range(ys.min(), ys.max()+1):
        row = ink[y]
        if not row[1131:].any():
            continue
        xs = np.where(row)[0]
        # is the row continuous across the whole width?
        span = f"x {xs.min()}..{xs.max()}"
        cov = row.sum()/1179
        print(f"   y={y+440}px ({(y+440)/3:.1f} pt)  ink cols={int(row.sum())}/1179 ({cov:.0%})  {span}  "
              f"gutter={int(row[1131:].sum())}/48  contiguous={'YES' if int(row.sum())==xs.max()-xs.min()+1 else 'no'}")
