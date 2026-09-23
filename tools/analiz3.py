#!/usr/bin/env python3
"""Day-by-day: which network, was Bluetooth actually used, and did it fail?
Usage is detected from events that fire regardless of errors (player/device
connect), so 'no errors' can no longer be confused with 'not used'."""
from collections import Counter, defaultdict

FIX = "2026-08-21"

assoc = {}
for line in open("ssid-timeline.txt"):
    p = line.split(None, 2)
    if len(p) == 3:
        assoc[f"{p[0]}T{p[1]}"] = p[2].strip()
known = sorted(assoc)

def ssid_at(hour):
    lo, hi, best = 0, len(known) - 1, None
    while lo <= hi:
        m = (lo + hi) // 2
        if known[m] <= hour: best, lo = known[m], m + 1
        else: hi = m - 1
    return assoc.get(best, "?") if best else "?"

use = Counter(l.strip() for l in open("bt-usage-hours.txt") if l.strip())
err = Counter(l.strip() for l in open("bt-errors-hours.txt") if l.strip())

days = defaultdict(lambda: {"use": 0, "err": 0, "nets": Counter()})
for h, n in use.items():
    d = days[h[:10]]; d["use"] += n; d["nets"][ssid_at(h)] += 1
for h, n in err.items():
    days[h[:10]]["err"] += n; days[h[:10]]["nets"][ssid_at(h)] += 1

print(f"{'gün':12} {'ağ':14} {'kullanım':>9} {'HATA':>7}")
print("-" * 48)
tot = defaultdict(lambda: [0, 0, 0])      # (net, period) -> [days, use, err]
for d in sorted(days):
    v = days[d]
    net = v["nets"].most_common(1)[0][0] if v["nets"] else "?"
    short = {"Zyxel_3DC1": "EV", "Zyxel_3DC1 1": "EV", "GSBWIFI": "YURT"}.get(net, net[:12])
    period = "ÖNCE" if d <= FIX else "SONRA"
    flag = "  ← düzeltme" if d == FIX else ""
    if v["use"] or v["err"]:
        print(f"{d:12} {short:14} {v['use']:>9} {v['err']:>7}{flag}")
    if short in ("EV", "YURT"):
        t = tot[(short, period)]; t[0] += 1; t[1] += v["use"]; t[2] += v["err"]

print("\n" + "=" * 48)
print(f"{'ağ':6} {'dönem':7} {'gün':>5} {'kullanım':>9} {'HATA':>8}")
print("-" * 48)
for k in [("EV", "ÖNCE"), ("EV", "SONRA"), ("YURT", "ÖNCE"), ("YURT", "SONRA")]:
    if k in tot:
        d, u, e = tot[k]
        print(f"{k[0]:6} {k[1]:7} {d:>5} {u:>9} {e:>8}")
    else:
        print(f"{k[0]:6} {k[1]:7} {'—':>5} {'—':>9} {'—':>8}")
print("=" * 48)
