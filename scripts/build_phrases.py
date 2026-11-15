"""Builds Keyboard/Resources/phrases.txt: common multi-word continuations
("thank" -> "you so much"), for phrase suggestions.

Usage: python -I build_phrases.py <data_dir> <out_dir> [min_share] [min_count]
  data_dir needs eng_sentences.tsv.bz2 (Tatoeba, CC BY 2.0 FR).

Format: <previous word>\t<phrase>   ("<s>" = start of a sentence)
"""
import bz2
import collections
import os
import re
import sys

data_dir, out_dir = sys.argv[1], sys.argv[2]
MIN_SHARE = float(sys.argv[3]) if len(sys.argv) > 3 else 0.12
MIN_COUNT = int(sys.argv[4]) if len(sys.argv) > 4 else 20

token_re = re.compile(r"[a-z]+(?:'[a-z]+)?")
follow2 = collections.defaultdict(collections.Counter)
follow3 = collections.defaultdict(collections.Counter)
seen = collections.Counter()

with bz2.open(os.path.join(data_dir, "eng_sentences.tsv.bz2"), "rt", encoding="utf-8") as f:
    for line in f:
        parts = line.rstrip("\n").split("\t")
        if len(parts) < 3:
            continue
        text = parts[2].lower().replace("’", "'")
        # Only phrases within a clause: split on punctuation.
        for clause_index, clause in enumerate(re.split(r"[.,!?;:\"()]+", text)):
            tokens = token_re.findall(clause)
            if not tokens:
                continue
            words = (["<s>"] if clause_index == 0 else []) + tokens
            for i, w in enumerate(words):
                if i + 2 < len(words) + 0 and i + 2 <= len(words) - 1:
                    seen[w] += 1
                    follow2[w][" ".join(words[i + 1:i + 3])] += 1
                    if i + 3 <= len(words) - 1:
                        follow3[w][" ".join(words[i + 1:i + 4])] += 1

# Names from the corpus's stories make poor suggestions.
NAMES = {"tom", "mary", "john", "alice", "ken", "jim", "bob", "jack", "tony", "mike"}

out = []
for w, total in seen.items():
    if total < MIN_COUNT * 2:
        continue
    best = None
    for counter in (follow3[w], follow2[w]):
        if not counter:
            continue
        phrase, count = counter.most_common(1)[0]
        share = count / total
        # A 3-word phrase is worth more, so it needs a little less certainty.
        need = MIN_SHARE * (0.75 if counter is follow3[w] else 1.0)
        if count >= MIN_COUNT and share >= need and not (set(phrase.split()) & NAMES):
            best = phrase
            break
    if best:
        out.append(f"{w}\t{best}")

out.sort()
os.makedirs(out_dir, exist_ok=True)
with open(os.path.join(out_dir, "phrases.txt"), "w", encoding="utf-8", newline="\n") as f:
    f.write("\n".join(out) + "\n")
print(len(out), "phrases")
lookup = dict(line.split("\t") for line in out)
for w in "<s> thank see how what i going let as want look nice good happy talk would could have will do are you we in at".split():
    print(f"  {w} -> {lookup.get(w, '')}")
