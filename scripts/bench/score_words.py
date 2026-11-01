import json, sys
gold = json.load(open(sys.argv[1]))
rows = json.load(open(sys.argv[2]))
def ok(text, word):
    t = text.strip("。、 ")
    if t == word:          # 照搬原词（丈夫 → 丈夫）不算对，除非原词本身就在答案里
        return word in gold[word]
    return any(g in t for g in gold[word])
n = len(rows)
base_ok = new_ok = misled_base = misled_new = warned = false_alarm = 0
lines = []
for r in rows:
    w = r["word"]
    b = ok(r["mt"], w)
    ff = bool(r.get("falseFriend"))
    eq = r.get("equivalents", [])
    primary = eq[0] if ff and eq else r["mt"]
    p = ok(primary, w)
    base_ok += b; new_ok += p
    misled_base += not b
    misled_new += (not p) and not ff      # 错了还没有任何提醒
    warned += ff
    false_alarm += ff and b               # 译文是对的却报了同形异义
    if not b or ff:
        lines.append(f'{"✓" if p else "✗"}{"⚠" if ff else " "} {w}: MT={r["mt"]} → {primary}   同形={r.get("falseFriend","")[:30]}  对应词={eq}')
print(f"首选答案正确: 改前 {base_ok}/{n} ({base_ok/n:.1%}) → 改后 {new_ok}/{n} ({new_ok/n:.1%})")
print(f"答错且无提醒(误导): 改前 {misled_base}/{n} ({misled_base/n:.1%}) → 改后 {misled_new}/{n} ({misled_new/n:.1%})")
dict1 = sum(1 for r in rows if r.get("equivalents") and ok(r["equivalents"][0], r["word"]))
visible = sum(1 for r in rows if ok(r["mt"], r["word"]) or any(ok(e, r["word"]) for e in r.get("equivalents", [])[:3]))
print(f"词典对应词第一个正确 {dict1}/{n} ({dict1/n:.1%})   译文或前3个对应词里有正确答案 {visible}/{n} ({visible/n:.1%})")
print(f"报警 {warned} 次，其中误报（译文其实是对的）{false_alarm} 次")
print("\n".join(lines))
