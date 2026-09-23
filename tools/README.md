# tools

Measurement and analysis code for the notes. Nothing here is a library — each script
exists because a specific investigation needed an instrument that didn't exist yet.

## `bt-dropout-test.sh`

2×2 A/B harness for [note 001](../notes/001-bluetooth-audio-wifi-powersave.md).
Pins the Wi-Fi band by BSSID, toggles power saving, samples PipeWire xruns and signal
strength per arm, writes a CSV, and restores every setting on exit — including on
`Ctrl+C`.

```bash
# fill BSSID_24 / BSSID_50 near the top first:
nmcli -f SSID,FREQ,BSSID device wifi list

./bt-dropout-test.sh 900     # 15 min per arm (default)
./bt-dropout-test.sh 60      # quick sanity run
```

Requires: `iw`, `nmcli`, `pw-top`, `bc`, and **music already playing over Bluetooth** —
the script aborts otherwise, because an idle sink reports nothing.

## `analiz.py` · `analiz3.py`

Retrospective analysis of the systemd journal. Both read two plain text files of
hour-stamps, generated like this:

```bash
journalctl --no-pager -o short-iso --since "2026-05-04" \
  | grep -F "spa.bluez5" | awk '{print substr($1,1,13)}' > bt-active-hours.txt

journalctl --no-pager -o short-iso --since "2026-05-04" \
  | grep -F "Missing completion reports" | awk '{print substr($1,1,13)}' > bt-errors-hours.txt

# analiz3.py additionally needs usage events and an SSID timeline:
journalctl --no-pager -o short-iso --since "2026-05-04" \
  | grep -E "Player registered|bluez_output.*-> running|btd_device_connect" \
  | awk '{print substr($1,1,13)}' > bt-usage-hours.txt

journalctl --no-pager -o short-iso --since "2026-05-04" \
  | grep -E "NetworkManager.*(activating connection|Activation:.*successful)" \
  | grep -oE "^[0-9T:+-]+.*'[^']+'" \
  | sed -E "s/^([0-9-]{10})T([0-9]{2}).*'([^']+)'.*/\1 \2 \3/" > ssid-timeline.txt
```

**`analiz.py` is wrong.** It normalises failures by "hours in which BlueZ logged
something" — but BlueZ logs almost nothing when it is working, so the denominator is
driven by the same failures as the numerator. It is kept here deliberately: the
mistake took longer to find than the fault did, and deleting it would hide the part
of the investigation that actually taught me something.

**`analiz3.py` is the one that held.** Per-day, per-network, with usage detected from
events that fire independently of errors — so "zero failures" can finally be
distinguished from "not used."
