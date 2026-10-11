#!/usr/bin/env python3
"""B's frame gate + gutter sweep.
Gate:  sandbox banner present (brown band at y=160, cap.sh's own test) -> the frame is the app.
Size:  header hairline y  (A3XL 553 px; default/3XL 417 px) - read off the paint, not simctl.
Ink:   RGB distance from the frame's own modal background, below y=440 px.
Edge:  377 pt content edge = x 1131 px; right gutter x in [1131,1178].
"""
import sys, os
import numpy as np
from PIL import Image

EDGE = 1131

def banner(a):
    px = a[160, 100:1080:40].astype(float)
    r, g, b = px[:,0].mean(), px[:,1].mean(), px[:,2].mean()
    return (90 < r < 190 and 30 < g < 110 and b < 60), (round(r), round(g), round(b))

def modal(a):
    q = (a // 8).astype(np.uint16)
    k = q[:,:,0]*1024 + q[:,:,1]*32 + q[:,:,2]
    v, c = np.unique(k, return_counts=True); m = int(v[int(np.argmax(c))])
    return np.array([(m//1024)*8+4, ((m//32)%32)*8+4, (m%32)*8+4], dtype=np.float32)

for p in sys.argv[1:]:
    a = np.asarray(Image.open(p).convert('RGB'), dtype=np.uint8)
    H, W, _ = a.shape
    ok, rgb = banner(a)
    bg = modal(a[440:, :, :])
    d = np.sqrt(((a[440:,:,:].astype(np.float32) - bg) ** 2).sum(axis=2))
    # hairline: first full-width row below y=300
    dd = np.sqrt(((a.astype(np.float32) - bg) ** 2).sum(axis=2))
    fw = [y for y in np.where((dd > 25).sum(axis=1) >= 1170)[0] if y > 300]
    hair = fw[0] if fw else None
    out = []
    for T in (45, 90):
        ink = d > T
        gut = int(ink[:, EDGE:].sum())
        cols = np.where(ink.any(axis=0))[0]
        mx = round(int(cols.max())/3.0, 1) if cols.size else None
        out.append(f"T{T}: gut={gut:>6} maxx={mx}")
    tag = 'A3XL' if hair == 553 else ('dflt/3XL' if hair == 417 else f'hair={hair}')
    print(f"{os.path.basename(p):<52} {W}x{H} banner={'OK ' if ok else 'NO!'} {tag:<9} bg={tuple(int(x) for x in bg)}  " + "  ".join(out))
