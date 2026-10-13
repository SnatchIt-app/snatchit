import sys
from PIL import Image

def bands(path, x0, x1, y0, y1, thresh=110):
    im = Image.open(path).convert('L')
    px = im.load()
    rows = []
    for y in range(y0, y1):
        dark = sum(1 for x in range(x0, x1, 2) if px[x, y] < thresh)
        rows.append(dark > 0)
    out, start = [], None
    for i, d in enumerate(rows):
        if d and start is None: start = i
        elif not d and start is not None:
            out.append((y0 + start, y0 + i - 1)); start = None
    if start is not None: out.append((y0 + start, y1 - 1))
    return [(a, b, round((b - a + 1) / 3.0, 1)) for a, b in out if (b - a + 1) >= 6]

if __name__ == '__main__':
    path = sys.argv[1]
    x0, x1, y0, y1 = (int(v) for v in sys.argv[2:6])
    print(f'{path}  band(y_top..y_bottom px)  ink height pt')
    for a, b, h in bands(path, x0, x1, y0, y1):
        print(f'  {a:5d}..{b:5d}   {h:6.1f} pt')
