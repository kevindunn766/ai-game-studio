import pathlib, json, os
from PIL import Image

src = pathlib.Path(r'C:\Users\kevin\game-studio\assets\characters\sotn_reference\sprites')
out = pathlib.Path(r'C:\Users\kevin\game-studio\assets\characters\sotn_reference\metadata')
out.mkdir(parents=True, exist_ok=True)
errors = []
count = 0
for p in src.glob('*.png'):
    try:
        with Image.open(p) as img:
            img = img.convert('RGBA')
            w, h = img.size
            # find tight bbox ignoring alpha=0 or pixels close to magenta
            pixels = img.load()
            min_x, min_y = w, h
            max_x, max_y = 0, 0
            for y in range(h):
                for x in range(w):
                    r, g, b, a = pixels[x, y]
                    if a == 0 or (r == 255 and g == 0 and b == 255):
                        continue
                    if x < min_x: min_x = x
                    if y < min_y: min_y = y
                    if x > max_x: max_x = x
                    if y > max_y: max_y = y
            if max_x < min_x or max_y < min_y:
                bbox = {"x": 0, "y": 0, "w": w, "h": h}
                colors = []
            else:
                bbox = {"x": min_x, "y": min_y, "w": max_x-min_x+1, "h": max_y-min_y+1}
                seen = set()
                colors = []
                for y in range(min_y, max_y+1):
                    for x in range(min_x, max_x+1):
                        r, g, b, a = pixels[x, y]
                        if a == 0 or (r == 255 and g == 0 and b == 255):
                            continue
                        hex_color = f'#{r:02X}{g:02X}{b:02X}'
                        if hex_color not in seen:
                            seen.add(hex_color)
                            colors.append(hex_color)
            data = {
                "filename": p.name,
                "source_page": "https://www.castlevaniacrypt.com/sotn-sprites/",
                "width": w,
                "height": h,
                "bbox": bbox,
                "palette_hex_list": colors,
            }
            json_path = out / (p.stem + '.json')
            json_path.write_text(json.dumps(data, indent=2), encoding='utf-8')
            count += 1
    except Exception as e:
        errors.append((p.name, str(e)))

print(f'Generated {count} metadata files')
print(f'Errors: {len(errors)}')
if errors:
    for e in errors[:10]:
        print(e)
