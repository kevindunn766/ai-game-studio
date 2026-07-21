import os, sys, json, math, hashlib, urllib.request, re
import numpy as np
from PIL import Image
from urllib.parse import urljoin

BASE = 'https://www.castlevaniacrypt.com/sotn-sprites/'
OUT_ORIG = r'C:\Users\kevin\game-studio\assets\characters\sotn_reference\originals'
OUT_SPRITES = r'C:\Users\kevin\game-studio\assets\characters\sotn_reference\sprites'
REPORT = r'C:\Users\kevin\game-studio\assets\characters\sotn_reference\report.md'

os.makedirs(OUT_ORIG, exist_ok=True)
os.makedirs(OUT_SPRITES, exist_ok=True)

# Fetch index
with urllib.request.urlopen(BASE, timeout=30) as r:
    html = r.read().decode('utf-8', errors='ignore')

# Extract image URLs from img tags or links
imgs = re.findall(r'https://www\.castlevaniacrypt\.com/wp-content/img/sotn/sprites/[^"\'\s<>]+\.(?:png|gif)', html)
# Also from anchor hrefs as seen in browser
imgs += re.findall(r'href="(https://www\.castlevaniacrypt\.com/wp-content/img/sotn/sprites/[^"]+\.(?:png|gif))"', html)
imgs = sorted(set(imgs))
print(f'Found {len(imgs)} sprite sheet URLs')

# Download
downloaded = []
for url in imgs:
    name = os.path.basename(url)
    path = os.path.join(OUT_ORIG, name)
    if os.path.exists(path):
        downloaded.append((url, name, path))
        continue
    try:
        with urllib.request.urlopen(url, timeout=60) as r:
            data = r.read()
        with open(path, 'wb') as f:
            f.write(data)
        downloaded.append((url, name, path))
        print(f'Downloaded {name} ({len(data)} bytes)')
    except Exception as e:
        print(f'ERROR downloading {url}: {e}')

print(f'Total downloaded: {len(downloaded)}')

# Processing
MAGIC = (255, 0, 255)
TOTAL_SPRITES = 0
TOTAL_ORIG_BYTES = 0
TOTAL_SPRITE_BYTES = 0
ALL_PALETTES = []
ERRORS = []
SPRITE_FILES = []

for url, name, path in downloaded:
    sheet_path = path
    try:
        im = Image.open(sheet_path)
        # Convert to RGBA for cropping and alpha handling
        if im.mode != 'RGBA':
            im = im.convert('RGBA')
    except Exception as e:
        ERRORS.append(f'Cannot open {name}: {e}')
        continue

    orig_bytes = os.path.getsize(sheet_path)
    TOTAL_ORIG_BYTES += orig_bytes

    # Identify non-transparent pixels to find grid if possible
    data = np.array(im)
    alpha = data[:,:,3]
    # Pixels with >0 alpha are content
    ys, xs = np.where(alpha > 0)
    if len(xs) == 0:
        continue
    minx, maxx = int(xs.min()), int(xs.max())
    miny, maxy = int(ys.min()), int(ys.max())
    # Tight bbox of entire sheet content
    content = im.crop((minx, miny, maxx+1, maxy+1))
    # Save cropped original too? We keep originals unchanged; we just use content for slicing

    # Heuristic: this is a single-row/grid sprite sheet. We need to split.
    # Strategy: scan vertical columns for non-transparent pixels. Group contiguous x ranges.
    col_has = (alpha > 0).any(axis=0)
    groups = []
    in_g = False
    for x in range(col_has.shape[0]):
        if col_has[x] and not in_g:
            in_g = True
            gx0 = x
        elif not col_has[x] and in_g:
            in_g = False
            groups.append((gx0, x-1))
    if in_g:
        groups.append((gx0, col_has.shape[0]-1))

    # For each column group, compute tight bounding box over all non-transparent pixels within that x-range
    sheet_sprites = []
    for gx0, gx1 in groups:
        mask = alpha[:, gx0:gx1+1] > 0
        if not mask.any():
            continue
        ys, xs_rel = np.where(mask)
        if len(xs_rel) == 0:
            continue
        local_miny = int(ys.min())
        local_maxy = int(ys.max())
        local_minx = int(xs_rel.min())
        local_maxx = int(xs_rel.max())
        bbox = (gx0 + local_minx, local_miny, gx0 + local_maxx + 1, local_maxy + 1)
        sheet_sprites.append(bbox)

    stem = os.path.splitext(name)[0]
    for idx, (x0, y0, x1, y1) in enumerate(sheet_sprites):
        spr = im.crop((x0, y0, x1, y1))
        w, h = spr.size
        # Replace alpha with #FF00FF
        dst = Image.new('RGB', (w, h), MAGIC)
        dst.paste(spr, mask=spr.split()[3])
        # Ensure no alpha
        dst = dst.convert('RGB')
        # Collect unique colors excluding magic
        px = np.array(dst)
        # reshape and find unique
        ucolors = np.unique(px.reshape(-1, 3), axis=0)
        pal = []
        for col in ucolors:
            col = tuple(int(c) for c in col)
            if col != MAGIC:
                pal.append(f'#{col[0]:02X}{col[1]:02X}{col[2]:02X}')
        # Output filename
        out_name = f'{stem}_{idx:03d}.png'
        out_path = os.path.join(OUT_SPRITES, out_name)
        dst.save(out_path)
        meta = {
            'filename': out_name,
            'source_page': BASE,
            'source_sheet': url,
            'width': w,
            'height': h,
            'bbox': {'x': int(x0), 'y': int(y0), 'w': int(w), 'h': int(h)},
            'palette_hex_list': pal
        }
        meta_name = out_name.replace('.png', '.json')
        with open(os.path.join(OUT_SPRITES, meta_name), 'w') as f:
            json.dump(meta, f, indent=2)
        TOTAL_SPRITES += 1
        TOTAL_SPRITE_BYTES += os.path.getsize(out_path)
        SPRITE_FILES.append(out_path)
        ALL_PALETTES.extend(pal)

print(f'Total sprites generated: {TOTAL_SPRITES}')
print(f'Errors: {len(ERRORS)}')
for e in ERRORS:
    print(e)
print(f'Total sprite bytes: {TOTAL_SPRITE_BYTES}')
print(f'Total original bytes: {TOTAL_ORIG_BYTES}')
pal_unique = sorted(set(ALL_PALETTES))
print(f'Unique palette colors across all sprites: {len(pal_unique)}')

# Report
md = f'# Castlevania: SOTN Sprite Reference Report\n\n'
md += f'Generated: {__import__("datetime").datetime.now().isoformat()}\n\n'
md += f'## Summary\n\n'
md += f'- Source page: {BASE}\n'
md += f'- Sheets downloaded: {len(downloaded)}\n'
md += f'- Total sprites: {TOTAL_SPRITES}\n'
md += f'- Total originals size: {TOTAL_ORIG_BYTES} bytes\n'
md += f'- Total sprites size: {TOTAL_SPRITE_BYTES} bytes\n'
md += f'- Unique palette colors (excl #FF00FF): {len(pal_unique)}\n\n'
md += f'## Errors\n\n'
if ERRORS:
    md += '\n'.join([f'- {e}' for e in ERRORS]) + '\n'
else:
    md += 'No errors.\n'
md += f'\n## Sheets\n\n'
md += '\n'.join([f'- {name} ({url})' for url, name, p in downloaded]) + '\n'

with open(REPORT, 'w') as f:
    f.write(md)
print('Report written to', REPORT)
