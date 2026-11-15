"""Builds BetterBoard's next-word (bigrams.txt) and emoji (emoji.txt) resources.

Usage: python -I build_data.py <data_dir> <out_dir>
"""
import bz2
import collections
import json
import os
import re
import sys

data_dir, out_dir = sys.argv[1], sys.argv[2]
sys.stdout.reconfigure(encoding="utf-8")

# Hand-picked emoji for common texting words (Gboard-like), checked first.
OVERRIDES = {
    "love": "❤️ 😍 🥰", "heart": "❤️ 💕", "happy": "😊 😄", "sad": "😢 😞", "lol": "😂 🤣",
    "haha": "😂 🤣", "hahaha": "😂", "laugh": "😂", "laughing": "😂", "cry": "😭 😢",
    "crying": "😭", "angry": "😠 😡", "mad": "😡", "kiss": "😘 💋", "kisses": "😘",
    "hug": "🤗", "hugs": "🤗", "thanks": "🙏 😊", "thank": "🙏", "please": "🙏",
    "yes": "👍", "ok": "👌 👍", "okay": "👌 👍", "no": "🙅", "cool": "😎", "party": "🎉 🥳",
    "birthday": "🎂 🎉", "congrats": "🎉 🥳", "congratulations": "🎉 🥳", "fire": "🔥",
    "hot": "🔥 🥵", "cold": "🥶", "sleep": "😴", "sleepy": "😴", "tired": "😴 🥱",
    "sick": "🤒 🤢", "money": "💰 💵", "beer": "🍺 🍻", "wine": "🍷", "coffee": "☕",
    "food": "🍔 🍕", "hungry": "😋", "yum": "😋", "yummy": "😋", "pizza": "🍕", "cake": "🎂",
    "dog": "🐶 🐕", "cat": "🐱 🐈", "sun": "☀️", "sunny": "☀️", "rain": "🌧️", "snow": "❄️",
    "music": "🎵 🎶", "car": "🚗", "home": "🏠", "house": "🏠", "work": "💼", "phone": "📱",
    "game": "🎮", "win": "🏆", "good": "👍", "great": "👍 🙌", "nice": "👌 👍", "wow": "😮 🤩",
    "omg": "😱", "scared": "😱", "think": "🤔", "thinking": "🤔", "hmm": "🤔", "idea": "💡",
    "smile": "😊", "wink": "😉", "cute": "🥰", "beautiful": "😍", "sorry": "😔 🙏",
    "bye": "👋", "hello": "👋", "hi": "👋", "hey": "👋", "strong": "💪", "eyes": "👀",
    "clap": "👏", "pray": "🙏", "star": "⭐", "christmas": "🎄 🎅", "halloween": "🎃",
    "ghost": "👻", "dead": "💀", "skull": "💀", "gift": "🎁", "present": "🎁",
    "flower": "🌸 💐", "flowers": "💐", "rose": "🌹", "tree": "🌳", "beach": "🏖️",
    "plane": "✈️", "travel": "✈️", "book": "📚", "school": "🏫", "kangaroo": "🦘",
    "koala": "🐨", "australia": "🇦🇺", "aussie": "🇦🇺", "footy": "🏉", "football": "🏈 ⚽",
    "soccer": "⚽", "basketball": "🏀", "gym": "🏋️ 💪", "run": "🏃", "running": "🏃",
    "time": "⏰", "late": "⏰", "perfect": "💯", "crazy": "🤪", "boom": "💥", "rocket": "🚀",
    "chicken": "🐔 🍗", "burger": "🍔", "fries": "🍟", "taco": "🌮", "sushi": "🍣",
    "apple": "🍎", "banana": "🍌", "egg": "🥚", "bread": "🍞", "cheese": "🧀",
    "drink": "🥤 🍹", "drinks": "🍻", "cheers": "🍻 🥂", "celebrate": "🎉 🥳",
    "dance": "💃", "dancing": "💃", "sing": "🎤", "ring": "💍", "married": "💍",
    "baby": "👶", "family": "👪", "friends": "👯", "secret": "🤫", "rich": "🤑",
    "nerd": "🤓", "brain": "🧠", "broken": "💔", "heartbroken": "💔", "cow": "🐄 🐮",
    "money": "💰 💵", "shocked": "😱", "lmao": "🤣", "nope": "🙅", "fine": "👍",
    "excited": "🤩", "awesome": "🙌 🔥", "amazing": "🤩", "sweet": "🍭", "kill": "🔪",
}

# ---------------------------------------------------------------- next words
# Tatoeba's famous example-sentence names would otherwise dominate predictions.
NAMES = set("""tom mary john alice ken jack bob mike jane jim ziri sami layla skura rima
yanni mennad baya muiriel taninna nuja mohamed tatoeba dan linda fadil dania""".split())
BLOCKED = set("""fuck fucking fucked fucker fuckin fucks motherfucker shit shitty bullshit
bitch bitches cunt dick dicks pussy cock asshole bastard slut whore fag faggot nigger
nigga retard twat wanker dickhead prick""".split())

token_re = re.compile(r"[a-z]+(?:'[a-z]+)*|[.!?]")
pairs = collections.Counter()
lines = 0
with bz2.open(os.path.join(data_dir, "eng_sentences.tsv.bz2"), "rt", encoding="utf-8") as f:
    for line in f:
        parts = line.rstrip("\n").split("\t")
        if len(parts) < 3:
            continue
        text = parts[2].lower().replace("’", "'")
        prev = "<s>"
        for m in token_re.finditer(text):
            tok = m.group(0)
            if tok in ".!?":
                prev = "<s>"
                continue
            pairs[(prev, tok)] += 1
            prev = tok
        lines += 1

by_prev = collections.defaultdict(list)
for (prev, nxt), count in pairs.items():
    if count < 3 or nxt in NAMES or nxt in BLOCKED or len(nxt) > 20:
        continue
    by_prev[prev].append((count, nxt))

out_lines = []
for prev in sorted(by_prev):
    best = sorted(by_prev[prev], key=lambda t: (-t[0], t[1]))[:6]
    out_lines.append(prev + "\t" + " ".join(f"{w}:{c}" for c, w in best))

with open(os.path.join(out_dir, "bigrams.txt"), "w", encoding="utf-8", newline="\n") as f:
    f.write("\n".join(out_lines) + "\n")
print(f"sentences={lines} prev-words={len(out_lines)}")
print("after <s>:", next(l for l in out_lines if l.startswith("<s>\t")))
print("after i:", next(l for l in out_lines if l.startswith("i\t")))
print("after how:", next(l for l in out_lines if l.startswith("how\t")))

# --------------------------------------------------------------------- emoji
fully = []  # (emoji, name) in Unicode order
for line in open(os.path.join(data_dir, "emoji-test.txt"), encoding="utf-8"):
    if "; fully-qualified" not in line:
        continue
    m = re.search(r"#\s*(\S+)\s+E(\d+)\.(\d+)\s+(.*)$", line)
    if not m:
        continue
    emoji, major, minor, name = m.group(1), int(m.group(2)), int(m.group(3)), m.group(4).strip()
    if (major, minor) > (15, 1) or "skin tone" in name:
        continue
    fully.append((emoji, name.lower()))

ann = json.load(open(os.path.join(data_dir, "annotations.json"), encoding="utf-8"))
ann = ann["annotations"]["annotations"]
ann_by_key = {k.replace("️", ""): v for k, v in ann.items()}

word_re = re.compile(r"^[a-z]{2,}$")
candidates = collections.defaultdict(list)  # word -> [(rank, order, emoji)]
keyword_count = collections.Counter()
entries = []
for order, (emoji, name) in enumerate(fully):
    a = ann_by_key.get(emoji.replace("️", ""), {})
    tts = (a.get("tts") or [name])[0].lower()
    tts = tts.replace("flag: ", "")
    keywords = [k.lower() for k in a.get("default", [])]
    entries.append((order, emoji, tts, keywords))
    for k in set(keywords):
        if word_re.match(k):
            keyword_count[k] += 1

for order, emoji, tts, keywords in entries:
    tts_words = re.findall(r"[a-z]+", tts)
    if len(tts_words) == 1:
        candidates[tts_words[0]].append((0, order, emoji))
    elif tts_words:
        for w in {tts_words[0], tts_words[-1]}:
            candidates[w].append((1, order, emoji))
    for k in set(keywords):
        if word_re.match(k) and keyword_count[k] <= 6:
            candidates[k].append((2, order, emoji))

GENERIC = set("""face with and the of man woman person people symbol sign button mark
hand light dark medium skin tone flag box new free old one two three four five six
seven eight nine ten ten top up down left right on off in out""".split())
emoji_lines = []
for word in sorted(set(candidates) | set(OVERRIDES)):
    if word in BLOCKED or not word_re.match(word):
        continue
    if word in GENERIC and word not in OVERRIDES:
        continue
    items = sorted(set(candidates.get(word, [])))
    # Loose keyword matches only when nothing names the word directly.
    if any(i[0] <= 1 for i in items):
        items = [i for i in items if i[0] <= 1]
    if len(items) > 12:
        items = [i for i in items if i[0] == 0]
    seen, picked = set(), []
    for emoji in OVERRIDES.get(word, "").split():
        if emoji not in seen:
            seen.add(emoji)
            picked.append(emoji)
    for rank, order, emoji in items:
        if len(picked) >= 3:
            break
        if emoji not in seen:
            seen.add(emoji)
            picked.append(emoji)
        if len(picked) == 3:
            break
    if picked:
        emoji_lines.append(word + "\t" + " ".join(picked))

with open(os.path.join(out_dir, "emoji.txt"), "w", encoding="utf-8", newline="\n") as f:
    f.write("\n".join(emoji_lines) + "\n")
print(f"emoji words={len(emoji_lines)}")
for w in ["cow", "pizza", "love", "happy", "dog", "beer", "sad", "heart", "lol", "car", "the", "man"]:
    print(w, next((l for l in emoji_lines if l.startswith(w + "\t")), "-"))
