import sys
from PIL import Image
# ink2.py <png> <x0> <x1> <y0> <y1> [dark]
path = sys.argv[1]; x0,x1,y0,y1 = (int(v) for v in sys.argv[2:6])
dark = len(sys.argv) > 6
im = Image.open(path).convert('L'); px = im.load()
hit = (lambda v: v > 140) if dark else (lambda v: v < 110)
rows = [any(hit(px[x, y]) for x in range(x0, x1, 2)) for y in range(y0, y1)]
bands, start = [], None
for i, d in enumerate(rows):
    if d and start is None: start = i
    elif not d and start is not None:
        bands.append((y0+start, y0+i-1)); start = None
if start is not None: bands.append((y0+start, y1-1))
print(f'{path}  ({"light ink on dark" if dark else "dark ink on light"})')
for a, b in bands:
    if b - a + 1 >= 6: print(f'  {a:5d}..{b:5d} px   {(b-a+1)/3:6.1f} pt')
