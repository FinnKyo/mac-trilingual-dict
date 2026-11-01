#!/usr/bin/env python3
"""语料级 chrF（与 sacrebleu 默认设置一致：字符 1~6 元，beta=2，忽略空白）。

用法：python3 scripts/chrf.py <参考译文.txt> <系统译文.txt> [<系统译文2.txt> ...]
两个文件逐行对应；只统计参考译文的前 N 行（N 为系统译文的行数）。
"""
import sys
from collections import Counter

ORDER = 6
BETA = 2


def ngrams(s, n):
    s = "".join(s.split())
    return Counter(s[i:i + n] for i in range(len(s) - n + 1))


def chrf(refs, hyps):
    match = [0] * ORDER
    hyp_total = [0] * ORDER
    ref_total = [0] * ORDER
    for r, h in zip(refs, hyps):
        for n in range(1, ORDER + 1):
            rg, hg = ngrams(r, n), ngrams(h, n)
            match[n - 1] += sum((rg & hg).values())
            hyp_total[n - 1] += sum(hg.values())
            ref_total[n - 1] += sum(rg.values())
    precisions = [m / t for m, t in zip(match, hyp_total) if t > 0]
    recalls = [m / t for m, t in zip(match, ref_total) if t > 0]
    p = sum(precisions) / len(precisions) if precisions else 0
    r = sum(recalls) / len(recalls) if recalls else 0
    if p + r == 0:
        return 0.0
    return 100 * (1 + BETA ** 2) * p * r / (BETA ** 2 * p + r)


def read(path):
    with open(path, encoding="utf-8") as f:
        return [line.rstrip("\n") for line in f]


if __name__ == "__main__":
    refs = read(sys.argv[1])
    for path in sys.argv[2:]:
        hyps = read(path)
        print(f"{chrf(refs[:len(hyps)], hyps):6.2f}  {path}")
