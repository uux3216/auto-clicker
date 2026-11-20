import glob, os, re
cands = glob.glob('android/app/src/main/**/MainActivity.*', recursive=True)
assert cands, 'MainActivity not found'
text = open(cands[0], encoding='utf-8').read()
pkg = re.search(r'^package\s+([\w.]+)', text, re.M).group(1)
tpl = open('tools/MainActivity.kt.tpl', encoding='utf-8').read().replace('__PKG__', pkg)
d = os.path.dirname(cands[0])
for c in cands:
    os.remove(c)
open(os.path.join(d, 'MainActivity.kt'), 'w', encoding='utf-8').write(tpl)
print('native audio module installed in', d, 'package', pkg)
