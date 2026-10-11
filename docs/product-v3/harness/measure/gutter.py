#!/usr/bin/env python3
"""B's independent gutter / content-edge measurement.

Geometry: iPhone 16, 393x852 pt logical, @3x -> 1179x2556 px. 3.0 px per pt exactly.
Content edge 377 pt -> x = 1131 px. Right gutter = x in [1131, 1178] (48 px = 16 pt).

"Ink" = a pixel whose RGB Euclidean distance from the frame's own modal background
exceeds T. The modal background is computed per frame from the measured band, so the
instrument never assumes which appearance it is looking at. Reported at several T so
the answer can be seen to be threshold-robust rather than threshold-chosen.
"""
import sys, os
import numpy as np
from PIL import Image

PX_PER_PT = 3.0
EDGE_PT = 377.0
EDGE_PX = int(round(EDGE_PT * PX_PER_PT))   # 1131
HEADER_PX = 440                              # below the fixed header, as C used
THRESHOLDS = (30, 45, 60, 90)

def modal_bg(a):
    q = (a // 8).astype(np.uint16)
    key = q[:, :, 0] * 1024 + q[:, :, 1] * 32 + q[:, :, 2]
    vals, counts = np.unique(key, return_counts=True)
    k = int(vals[int(np.argmax(counts))])
    return np.array([(k // 1024) * 8 + 4, ((k // 32) % 32) * 8 + 4, (k % 32) * 8 + 4], dtype=np.float32)

def measure(path, y0=HEADER_PX, y1=None):
    im = Image.open(path).convert('RGB')
    a = np.asarray(im, dtype=np.uint8)
    H, W, _ = a.shape
    if y1 is None:
        y1 = H
    band = a[y0:y1, :, :].astype(np.float32)
    bg = modal_bg(a[y0:y1, :, :])
    d = np.sqrt(((band - bg) ** 2).sum(axis=2))
    out = {'file': os.path.basename(path), 'wh': (W, H), 'bg': tuple(int(v) for v in bg),
           'band': (y0, y1), 'rows': {}}
    for T in THRESHOLDS:
        ink = d > T
        gut = int(ink[:, EDGE_PX:].sum())
        cols = np.where(ink.any(axis=0))[0]
        if cols.size:
            mx = int(cols.max())
            maxpt = round(mx / PX_PER_PT, 1)
        else:
            mx, maxpt = -1, None
        out['rows'][T] = {'gutter_px': gut, 'max_ink_x_px': mx, 'max_ink_x_pt': maxpt,
                          'total_ink_px': int(ink.sum())}
        if gut:
            ys = np.where(ink[:, EDGE_PX:].any(axis=1))[0]
            out['rows'][T]['gutter_y_pt'] = (round((ys.min() + y0) / PX_PER_PT, 1),
                                             round((ys.max() + y0) / PX_PER_PT, 1))
    return out

if __name__ == '__main__':
    for p in sys.argv[1:]:
        r = measure(p)
        print(f"\n{r['file']}  {r['wh'][0]}x{r['wh'][1]}  bg={r['bg']}  band y={r['band'][0]}-{r['band'][1]}px")
        for T in THRESHOLDS:
            x = r['rows'][T]
            extra = f"  gutter_y={x['gutter_y_pt']}" if 'gutter_y_pt' in x else ""
            print(f"   T={T:<3} gutter={x['gutter_px']:>7} px   max_ink_x={x['max_ink_x_pt']} pt ({x['max_ink_x_px']} px)   total_ink={x['total_ink_px']}{extra}")
