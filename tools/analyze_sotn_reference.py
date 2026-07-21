import json, collections, pathlib
meta_dir = pathlib.Path(r'C:\Users\kevin\game-studio\assets\characters\sotn_reference\metadata')
color_global = collections.Counter()
color_examples = collections.Counter()
for p in meta_dir.glob('*.json'):
    data = json.loads(p.read_text(encoding='utf-8'))
    for c in data.get('palette_hex_list', []):
        color_global[c] += 1
        if len(color_examples) < 90:
            color_examples[c] += 1
print('Top global colors:')
for c, n in color_global.most_common(50):
    print(f'{c}: {n}')
