# -*- coding: utf-8 -*-
# i18n denetimi: (1) tr()/trp() anahtarlarindan en.json'da olmayanlar
#                (2) tr() disinda kalan hardcoded Turkce literaller
import json, re, os, io
from collections import Counter

EN = json.load(open('api/apps/translations/data/en.json', encoding='utf-8'))
LIB = 'mobile-app/lib'

def strip_comments(src):
    out = []
    for line in src.split('\n'):
        idx = 0
        in_s = None
        cut = len(line)
        while idx < len(line) - 1:
            c = line[idx]
            if in_s:
                if c == '\\':
                    idx += 2
                    continue
                if c == in_s:
                    in_s = None
            else:
                if c in ('"', "'"):
                    in_s = c
                elif c == '/' and line[idx + 1] == '/':
                    cut = idx
                    break
            idx += 1
        out.append(line[:cut])
    return '\n'.join(out)

call_re = re.compile(r"\btrp?\(\s*((?:'(?:[^'\\]|\\.)*'\s*)+)", re.S)
lit_re = re.compile(r"'((?:[^'\\]|\\.)*)'")
TRCH = re.compile(r"[çğıöşüÇĞİÖŞÜ]")

files = []
for root, _, fnames in os.walk(LIB):
    for fn in fnames:
        if fn.endswith('.dart'):
            files.append(os.path.join(root, fn))

keys = {}
spans = {}
for f in files:
    src = strip_comments(open(f, encoding='utf-8').read())
    spans[f] = []
    for m in call_re.finditer(src):
        spans[f].append((m.start(), m.end()))
        parts = lit_re.findall(m.group(1))
        key = ''.join(parts).replace("\\'", "'").replace('\\n', '\n')
        keys.setdefault(key, []).append(os.path.relpath(f, LIB))

missing = {k: sorted(set(v)) for k, v in keys.items() if k not in EN}
print('TOPLAM tr()/trp() anahtar:', len(keys))
print('EN KARSILIGI EKSIK:', len(missing))

hard = []
for f in files:
    src = strip_comments(open(f, encoding='utf-8').read())
    covered = spans.get(f, [])
    for m in lit_re.finditer(src):
        s = m.group(1)
        if not TRCH.search(s):
            continue
        pos = m.start()
        if any(a <= pos < b for a, b in covered):
            continue
        ctx = src[max(0, pos - 40):pos]
        if re.search(r"\btrp?\(\s*$", ctx):
            continue
        hard.append((os.path.relpath(f, LIB), s[:90]))

print('HARDCODED TURKCE LITERAL:', len(hard))
rep = {'missing': missing, 'hard': hard}
io.open('i18n_report.json', 'w', encoding='utf-8').write(
    json.dumps(rep, ensure_ascii=False, indent=1))
print('dosya bazinda hardcoded:')
for f, n in Counter(f for f, _ in hard).most_common(20):
    print(' ', n, f)
