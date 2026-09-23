#!/usr/bin/env python3
"""Before/after analysis of Bluetooth packet-completion failures,
normalised by how many hours the Bluetooth sink was actually in use."""
from collections import Counter
import statistics as st

FIX = "2026-08-21"          # wifi.powersave = 2 written at 21:01

act = Counter(l.strip() for l in open("bt-active-hours.txt") if l.strip())
err = Counter(l.strip() for l in open("bt-errors-hours.txt") if l.strip())

# an "active hour" = any bluez sink log line in that hour
hours = sorted(act)
def split(d):
    b = {h: v for h, v in d.items() if h[:10] <= FIX}
    a = {h: v for h, v in d.items() if h[:10] >  FIX}
    return b, a

act_b, act_a = split(act)
err_b, err_a = split(err)

def block(name, active, errors):
    ah = len(active)                       # hours the sink was in use
    ev = sum(errors.values())              # total failure log lines
    eh = len(errors)                       # hours containing >=1 failure
    days = len({h[:10] for h in active})
    print(f"\n  {name}")
    print(f"    gün sayısı (BT kullanılan)      : {days}")
    print(f"    aktif saat (BT sink açık)       : {ah}")
    print(f"    toplam hata satırı              : {ev}")
    print(f"    hata içeren saat                : {eh}  ({eh/ah*100:.1f}% of active hours)")
    print(f"    >>> AKTİF SAAT BAŞINA HATA      : {ev/ah:.1f}")
    per_h = [errors.get(h, 0) for h in active]
    print(f"    saatlik medyan                  : {st.median(per_h):.0f}")
    return ev/ah, eh/ah*100

print("=" * 64)
print(f"  Bluetooth paket tamamlama hatası — {FIX} düzeltmesi öncesi/sonrası")
print(f"  Normalize edilen: Bluetooth'un gerçekten kullanıldığı saat sayısı")
print("=" * 64)

r_b, p_b = block("ÖNCE  (2026-05-04 → 2026-08-21)", act_b, err_b)
r_a, p_a = block("SONRA (2026-08-22 → bugün)",      act_a, err_a)

print("\n" + "=" * 64)
print(f"  Aktif saat başına hata      : {r_b:.1f}  →  {r_a:.1f}   ({r_b/r_a:.1f}x azalma)")
print(f"  Hatalı saat oranı           : {p_b:.1f}% →  {p_a:.1f}%")
print("=" * 64)

# monthly trend, to check the drop lines up with the fix and not with a move
print("\n  Aylık seyir (aktif saat başına hata):")
mon_a, mon_e = Counter(), Counter()
for h, v in act.items(): mon_a[h[:7]] += 1
for h, v in err.items(): mon_e[h[:7]] += v
for m in sorted(mon_a):
    r = mon_e[m] / mon_a[m]
    bar = "#" * min(int(r), 55)
    mark = "  ← düzeltme" if m == FIX[:7] else ""
    print(f"    {m}  {r:6.1f}  {bar}{mark}")
