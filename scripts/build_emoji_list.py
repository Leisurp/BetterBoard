"""Builds Keyboard/Resources/emoji_list.txt for the emoji panel.

Usage: python -I build_emoji_list.py <data_dir> <out_dir>
  data_dir needs emoji-test.txt and annotations.json (CLDR, English) from Unicode.

Format:
  # Group name
  <emoji>\t<search words>\t<5 skin-tone versions, space separated (optional)>
"""
import json
import os
import re
import sys

data_dir, out_dir = sys.argv[1], sys.argv[2]
MAX_VERSION = (15, 1)
TONES = ["light skin tone", "medium-light skin tone", "medium skin tone",
         "medium-dark skin tone", "dark skin tone"]

ann = json.load(open(os.path.join(data_dir, "annotations.json"), encoding="utf-8"))
ann = ann["annotations"]["annotations"]
ann_by_key = {k.replace("️", ""): v for k, v in ann.items()}

groups = []        # [(group, [base emoji])]
names = {}         # emoji -> name
toned = {}         # base name -> {tone: emoji}
group = None
for line in open(os.path.join(data_dir, "emoji-test.txt"), encoding="utf-8"):
    if line.startswith("# group:"):
        group = line.split(":", 1)[1].strip()
        if group != "Component":
            groups.append((group, []))
        continue
    if "; fully-qualified" not in line or group == "Component":
        continue
    m = re.search(r"#\s*(\S+)\s+E(\d+)\.(\d+)\s+(.*)$", line)
    if not m:
        continue
    emoji, version, name = m.group(1), (int(m.group(2)), int(m.group(3))), m.group(4).strip()
    if version > MAX_VERSION:
        continue
    if "skin tone" in name:
        base, _, tone = name.partition(": ")
        if tone in TONES:  # exactly one tone (not mixed couples)
            toned.setdefault(base, {})[tone] = emoji
        continue
    names[emoji] = name
    groups[-1][1].append(emoji)

out = []
count = 0
for group_name, emojis in groups:
    if not emojis:
        continue
    out.append("# " + group_name)
    for emoji in emojis:
        name = names[emoji]
        a = ann_by_key.get(emoji.replace("️", ""), {})
        words = set(re.findall(r"[a-z0-9]+", name.lower().replace("flag: ", "")))
        for keyword in a.get("default", []):
            words.update(re.findall(r"[a-z0-9]+", keyword.lower()))
        words.discard("")
        line = emoji + "\t" + " ".join(sorted(words))
        tones = toned.get(name, {})
        if len(tones) == 5:
            line += "\t" + " ".join(tones[t] for t in TONES)
        out.append(line)
        count += 1

os.makedirs(out_dir, exist_ok=True)
with open(os.path.join(out_dir, "emoji_list.txt"), "w", encoding="utf-8", newline="\n") as f:
    f.write("\n".join(out) + "\n")
sys.stdout.reconfigure(encoding="utf-8")
print(count, "emoji in", len([g for g in groups if g[1]]), "groups;",
      sum(1 for e in names if len(toned.get(names[e], {})) == 5), "with skin tones")
