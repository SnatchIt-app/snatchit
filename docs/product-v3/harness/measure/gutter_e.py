# E's gutter instrument, after B's stated method: ink = RGB distance from the frame's modal background > T,
# below y=440px; right gutter x in [1131,1178]; full-bleed hairlines (rows inked across >=95% of width) excluded by shape.
import sys, numpy as np
from PIL import Image
def measure(p, T):
    a = np.asarray(Image.open(p).convert('RGB')).astype(int)[440:]
    flat = a.reshape(-1,3); vals, counts = np.unique(flat, axis=0, return_counts=True); bg = vals[counts.argmax()]
    ink = np.sqrt(((a-bg)**2).sum(2)) > T
    full = ink.mean(1) >= 0.95; ink[full] = False
    g = int(ink[:,1131:1179].sum()); cols = np.where(ink.any(0))[0]
    return g, (cols.max()+1)/3 if len(cols) else 0
for p in sys.argv[1:]:
    r = [measure(p,T) for T in (30,45,60,90)]
    print(f"{p.split('/')[-2]}/{p.split('/')[-1]}: gutter px T30/45/60/90 = {'/'.join(str(x[0]) for x in r)}  max ink x = {r[1][1]:.1f} pt")
