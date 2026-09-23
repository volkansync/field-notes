# field-notes

Diagnosis writeups from real failures on real machines — mine, mostly.

Each note follows the same shape, because the shape is the point:

```
symptom  →  what it wasn't  →  hypothesis  →  a test that could disprove it  →  evidence  →  fix
```

Not tutorials. Not "10 ways to fix X". These are records of working out what was
actually wrong, including the wrong turns, because the wrong turns are where the
method shows.

**Why this repo exists:** most of what I know about Linux and networking came from
breaking my own machine and having to fix it. Writing the fixes down turns an
afternoon of frustration into something reusable — and forces me to actually prove
the cause instead of stopping at "it works now".

---

## Notes

| # | Note | Domain | Root cause | Evidence |
|---|---|---|---|---|
| 001 | [Bluetooth audio dropouts were a Wi-Fi problem](notes/001-bluetooth-audio-wifi-powersave.md) | Wireless / power management | NetworkManager Wi-Fi power saving | 4 months of journal data · 152.5 → 18.3 failures/day |
| 002 | _TLS errors that were DNS blocking_ | DNS / TLS | ISP-level resolution blocking | — |
| 003 | _Anti-cheat 60099: a locale and a missing font_ | Wine / locale | `tr_TR` + absent Windows font | — |
| 004 | _Desktop shell dying after every upgrade_ | Qt / ABI | `qt6-base` ABI break | — |
| 005 | _Migrating a whole desktop environment, reversibly_ | Config management | — | — |

<sub>italics = written up next</sub>

## Tools

Measurement and analysis code lives in [`tools/`](tools/). It is part of the notes,
not an appendix — in 001 the hard part was not finding the fault but building a
measurement that didn't lie about it.

| | |
|---|---|
| [`bt-dropout-test.sh`](tools/bt-dropout-test.sh) | 2×2 A/B harness — pins Wi-Fi band by BSSID, toggles power saving, samples PipeWire xruns and signal strength per arm, restores state on any exit |
| [`analiz.py`](tools/analiz.py) | a normalisation that turned out to be circular · kept on purpose |
| [`analiz3.py`](tools/analiz3.py) | the one that held — per-day, per-network, usage detected independently of errors |

---

## Rules I hold myself to here

1. **State what it wasn't.** The discarded hypotheses are half the value.
2. **Every cause needs a test that could have proved it wrong.** "I changed it and
   the problem went away" is a coincidence, not a diagnosis.
3. **No fix without a reproduction.** If I can't make it break again, I don't
   understand it yet.
4. **Say what the fix costs.** Most fixes trade something away. Name the trade.

---

**Volkan Çevik** · Eskişehir, TR · [github.com/volkansync](https://github.com/volkansync)
