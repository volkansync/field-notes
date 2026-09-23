# 001 — Bluetooth audio dropouts were a Wi-Fi problem

| | |
|---|---|
| **Domain** | wireless · radio coexistence |
| **Primary cause** | 2.4 GHz band contention between Wi-Fi and Bluetooth |
| **Amplifier** | Wi-Fi power saving — makes it far worse, but is not the cause |
| **Fix** | move Wi-Fi off 2.4 GHz *and* renegotiate the Bluetooth link |
| **Result** | 152.5 → 18.3 failures/day on the same network · 10 days at exactly zero |
| **Cost** | negligible idle power draw · 5 GHz was *not* sacrificed |

> **Note on revisions.** This started as *"power saving causes Bluetooth dropouts."*
> Measuring it properly moved the cause to the band itself, demoted power saving to
> an amplifier, and added a second required step nobody writes down. The earlier
> version is still visible in the git history; it was wrong in a useful way.

---

## Symptom

Bluetooth audio cut out at irregular intervals. It always started on one channel —
sometimes the right earpiece, sometimes the left — then alternated, and eventually
both would drop together. Audio returned on its own within a second or two.

It happened on **two different pairs of headphones**, which was the first useful
signal: if a single headset were faulty, the failure would not have moved between
devices, and it would not have alternated channels.

## What it wasn't

Each of these was tested and discarded before the real cause was found:

- **A codec problem.** Switching codecs changed audio *quality*, not the dropout
  behaviour. A codec fault degrades consistently; this was intermittent.
- **The Bluetooth adapter's own power management.** Disabling it independently made
  no difference.
- **A faulty headset.** Ruled out by the symptom appearing on a second pair.
- **A PipeWire/BlueZ configuration issue.** Nothing corresponding in the logs, and
  the dropouts survived a clean restart of the audio stack.

The advice you find everywhere is *"move your Wi-Fi to 5 GHz."* It works — and that
it works was the actual clue, because it points at the band, not at Bluetooth.

## Hypothesis

2.4 GHz Wi-Fi and Bluetooth occupy the same band, and on a combo chip they contend
for the same radio time. Wi-Fi power saving puts the radio to sleep between beacons
and wakes it to transmit. Each wake cycle consumes airtime — and at low signal
margin, failed transmissions get retried, consuming much more of it.

So the mechanism isn't Bluetooth at all:

```
power saving  →  radio sleeps, wakes, transmits
                        ↓
        weak signal  →  transmit fails  →  retry  →  retry
                        ↓
              radio occupies the band far longer
                        ↓
            Bluetooth's slice shrinks  →  audio drops
```

Prediction: disabling Wi-Fi power saving should remove the dropouts **without**
giving up the 2.4 GHz band.

## Fix

Two steps. The second one is missing from every guide I found, and without it the
first appears not to work.

**1 — stop the radio from duty-cycling.** Set globally, so it applies to every
connection rather than one saved network:

```ini
# /etc/NetworkManager/conf.d/wifi-powersave.conf
[connection]
wifi.powersave = 2
```

```bash
sudo systemctl restart NetworkManager
```

**2 — re-establish the Bluetooth link.** Power the headset off and on again. Not a
Wi-Fi reconnect — the *Bluetooth* connection has to be torn down and renegotiated.

Applied **2026-08-21 21:01**. The dropouts stopped and did not return.

### Why step 2 is not optional

Measured directly, later: with the fault actively occurring, changing the Wi-Fi band
in software produced **no improvement at all**. The failure counter kept climbing.
Only after putting the headphones back in their case — letting the link drop — and
reconnecting did it fall to zero.

The likely reason is **AFH (adaptive frequency hopping)**. When a Bluetooth link is
established it negotiates a channel map, marking which parts of the 2.4 GHz band are
too noisy to use. That map is agreed at connection time. A link established while the
band is congested carries a degraded map for its whole lifetime — so moving Wi-Fi out
of the way afterwards changes nothing, because Bluetooth is still operating on a
decision it made earlier. Tearing the link down forces a fresh negotiation.

This also reframes the original fix: `systemctl restart NetworkManager` disturbed the
stack enough that the link came back up. **Part of what worked in August may have been
the reconnection, not only the setting.** Both steps belong in the fix; I can't
currently separate their contributions.

---

## Evidence

"It stopped happening" is not evidence, so I went looking for a measurement. The
system journal turned out to have been recording the fault the whole time:

```
wireplumber: spa.bluez5.sink.media:
    Missing completion reports for packet — Bluetooth adapter firmware bug?
```

That message fires when the controller fails to confirm packet transmission — which
is exactly what airtime starvation looks like from the host's side. The journal is
persistent here and goes back to May, covering three and a half months before the
fix.

### Three metrics, two of them wrong

This is the part worth writing down.

**Attempt 1 — live PipeWire xrun counters.** I wrote a script that pins the Wi-Fi
band, toggles power saving, and measures buffer underruns per arm. It returned zero
for every configuration, including the one that should have failed. The instrument
wasn't broken; the environment was wrong — see *Limits* below.

**Attempt 2 — failures per "Bluetooth-active hour."** To rule out "you just used
Bluetooth less after the fix," I normalised by hours in which the BlueZ sink logged
anything. This produced a modest 3.3× improvement and an apparently *unchanged*
pattern, so I nearly concluded the fix was unproven.

It was the metric that was wrong. **BlueZ logs almost nothing when it is working
correctly** — verified by using Bluetooth for over an hour and generating two log
lines. So the denominator was driven by the same failures as the numerator. Fewer
problems shrank the denominator and hid the improvement. A circular measure.

**Attempt 3 — the one that held.** Count failures per day, attribute every hour to
the Wi-Fi network that was actually associated at the time, and detect usage with
events that fire *independently of errors* (player/device connect). Now "no errors"
can no longer be confused with "not used."

### Result

| network | power saving | days | failures | per day |
|---|---|---|---|---|
| **home** | **on** | 64 | **9,763** | **152.5** |
| **home** | **off** | 22 | **402** | **18.3** |
| dorm | on | 6 | 308 | 51.3 |
| dorm | off | 2 | 8 | 4.0 |

Same network, same router, same flat — only the setting changed. **A factor of 8.**

And on the days where usage is independently confirmed, the home-after-fix rows read:

```
2026-09-05   2 usage events   0 failures
2026-09-06   3                0
2026-09-07   4                0
2026-09-08   2                0
2026-09-09   7                0
2026-09-10  13                0
2026-09-15  13                0
2026-09-17   2                0
2026-09-18   9                0
2026-09-19   5                0
```

Ten days of ordinary use, zero failures.

---

## Limits

**The fault could not be reproduced on demand.** A controlled 2×2 (band × power
saving, 15 minutes per cell) run on a different network produced zero failures in
every cell — including 2.4 GHz with power saving enabled, the cell that should have
failed.

I first attributed this to signal strength — a −30 dBm reading. That was wrong: it was
an instantaneous sample, and the per-arm averages were −46 to −52 dBm, ordinary
values, not far off home conditions. **Signal margin does not explain it.**

What the run did not control for was the access point and the state of the band.
Enterprise APs handle DTIM and Bluetooth coexistence differently from consumer
routers, and dorm 2.4 GHz congestion varies sharply by hour. Which of those mattered
is **unknown**, and I would rather record that than invent a cause.

The same evening, after the run finished, the fault appeared on its own — 24 failures
in ten minutes, on 2.4 GHz, with power saving already **off**. That is the observation
that redirected the whole diagnosis: power saving is not the primary cause. The band
is. Power saving makes it worse.

**Open questions, not smoothed over:**

- **2026-09-04** shows 141 failures on the home network *after* the fix, while the
  days around it are at zero. Unexplained.
- **2026-08-22 → 09-02** has failure counts but no independent usage signal — those
  events only began appearing in the journal on 09-03, probably after a package
  update changed log verbosity. That window is ambiguous and is excluded from the
  usage-confirmed rows above.

**Still to do:** run the 2×2 on the home network, where the fault actually lives, and
record signal strength alongside. That closes it.

---

## Why this fix and not the obvious one

The common advice — force 5 GHz — treats the symptom and costs you the 2.4 GHz band
entirely, which matters for range and for older devices. Disabling Wi-Fi power saving
treats the mechanism and keeps both bands, trading only a small amount of idle power
on a machine that is mains-powered most of the time.

Name the trade, then decide it's acceptable. Don't pretend there isn't one.

## Reproduction

Re-enable power saving (`wifi.powersave = 3`), restart NetworkManager, and use
Bluetooth audio **on a 2.4 GHz link with moderate-to-weak signal**. On a strong link
it will not reproduce, and that is the finding, not a failure of the test.

## Tooling

| | |
|---|---|
| [`bt-dropout-test.sh`](../tools/bt-dropout-test.sh) | 2×2 harness: pins band via BSSID, toggles power saving, samples xruns and signal per arm, restores state on any exit |
| [`analiz.py`](../tools/analiz.py) | first (flawed) normalisation — kept deliberately, because the mistake is the lesson |
| [`analiz3.py`](../tools/analiz3.py) | final analysis: per-day, per-network, with error-independent usage detection |

## Notes for next time

- A symptom in one subsystem often originates in another that shares a physical
  resource. *"What hardware does this actually sit on?"* is a cheap question to ask early.
- **Check what your denominator is made of.** A normalisation driven by the same
  signal as the numerator will hide exactly the effect you are looking for.
- Absence of log lines is not absence of usage. Find a signal that fires when things
  go *right*, or you cannot tell silence from success.
- Fixing the measurement took longer than finding the fault.

---

<sub>← back to <a href="../README.md">field-notes</a></sub>
