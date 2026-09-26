# 002 — A "dead" flash drive was write-protecting itself

| | |
|---|---|
| **Domain** | USB storage · controller firmware |
| **Primary cause** | The controller latched itself into a permanent read-only state |
| **Red herring** | The drive *was* strangely partitioned — real, but not why writes failed |
| **Test** | Three independent write-refusal probes + a full-surface read |
| **Result** | Not dead. Read-only at the silicon — and a flawless bootable installer because of it |
| **Cost** | Writes are gone for good; vendor-tool recovery is ~50/50 and can brick it |

> A friend handed me a USB stick he'd written off as dead — "it's broken, don't
> bother." I couldn't write to it either. We were both wrong, in two different
> directions, and the real cause was a third thing neither of us had looked at.

---

## Symptom

The drive mounted, but nothing could be written to it. On Windows it had reportedly
shown a tiny partition and a *"you need to format this disk"* prompt — the classic
"it's broken" signature. On Linux every write was refused outright.

A **Kingston DataTraveler 100 G3** (`0951:1666`), 57.7 GiB. It enumerated cleanly,
threw no I/O errors, and never reset during normal use. Whatever was wrong, it wasn't
the drive falling off the bus.

## What it wasn't

- **Not physically dead.** It attached cleanly every time, reported full capacity,
  and read without a single error (see below). A failing drive does not behave this
  politely.
- **Not "just needs reformatting."** It carried a real, deliberate layout — an NTFS
  partition plus a 1 MB `UEFI_NTFS` partition. That 1 MB partition is a **Rufus**
  fingerprint: UEFI can only boot from FAT, so Rufus adds a tiny FAT stub to boot an
  NTFS install. Someone had made it a Windows 11 install stick. That explained why
  Windows displayed it oddly and cried *"format me"* — Windows historically shows only
  the first partition on removable media. It did **not** explain the write failures.
- **Not a host-side read-only flag.** Clearing the OS's own read-only bit changed
  nothing (the test below).
- **Not NAND wear.** The most likely "it's dying" story — and the full-surface read
  killed it.
- **"Windows would have fixed it."** No. The protection lives in the drive's
  controller, not the OS. `diskpart`'s `readonly` attribute is stored in *Windows'
  own registry* — Linux never sees it, and it isn't the lock you're hitting here.

Two confident misdiagnoses — his ("broken") and my first one ("it's the
partitioning") — both wrong. The cause was underneath both.

## Hypothesis

The controller had latched itself into a **permanent read-only mode**. Cheap
controllers do this as a last-ditch protection state: keep the data readable, refuse
all writes. If that's true, the "no" is coming from the *device*, not from Linux — and
no amount of host-side coaxing will move it.

The controller identifies itself through its INQUIRY revision string: **`PMAP`** — a
Phison signature (the PS2251 family). That matters for recovery: Phison's
mass-production tool is the only thing that speaks to it at that level.

## Tests that could have disproved it

Three probes, each of which would have pointed elsewhere if the lock were soft:

**1 · Clear the host-side read-only flag.**
```bash
sudo blockdev --setrw /dev/sdX
lsblk -o NAME,RO /dev/sdX      # RO still 1
```
The flag won't clear. → The block layer isn't holding it read-only; something below
is. *(If this had cleared it, the lock was host-side and the story ends here.)*

**2 · Ask the device what it thinks it is.**
```bash
sudo sg_modes /dev/sdX        # MODE SENSE(10)
# mode header: 45 00 80 00  →  the 0x80 bit is WP=1
```
The device's **own** mode header declares write-protect. This is the drive saying "I
am read-only," not the kernel guessing. *(WP=0 here would have meant the block layer
was lying and the device was fine.)*

**3 · Try to force a low-level format.**
```bash
sudo sg_format --format /dev/sdX
# → Host_status=0x07  DID_ERROR
```
The bridge won't even *execute* FORMAT UNIT. *(A soft lock would have let the format
proceed.)* — Note: this reset the device twice, but it recovered cleanly; the attempt
did no damage.

Three independent layers, one answer: the refusal is in the controller.

## Evidence the NAND is fine

The recoverable-vs-scrap question hinges on whether the flash itself is worn out.
Full-surface read:

```bash
sudo dd if=/dev/sdX of=/dev/null bs=4M status=progress
# 61,904,781,312 bytes · 0 errors · steady 98.2 MB/s throughout
```

**Zero read errors, and a flat 98.2 MB/s across the entire 58 GiB.** Worn flash shows
the opposite: ECC-correction slowdowns and scattered I/O errors as blocks go bad. This
showed neither. The NAND is healthy — the failure is a *logic* lock in the controller,
not dead cells. That's the recoverable kind.

## Conclusion

The drive isn't broken. It **write-protected itself at the controller**, kept every
byte readable, and refused writes. There is no host-side fix: undoing it needs Phison's
mass-production tool (`MPALL`) run against the exact chip, in an offline Windows
environment — and that path is roughly fifty-fifty and can permanently brick the drive
if the firmware write is interrupted.

But "read-only forever" isn't useless. It's already a Windows 11 install stick, and a
stick that **cannot** be written is a bootable installer that can never be accidentally
corrupted or overwritten. The failure mode is the feature.

## What it turned into

One detail from the recovery research outlived the drive. The vendor tool that would
*un-brick* this controller reaches it through a firmware-reflash command channel — and
that is the **same primitive BadUSB abuses** to turn a storage stick into a phantom
keyboard. The door you'd use to rescue it is the door an attacker uses to weaponise it.

I didn't want to leave that as a stray thought, so it became a separate hands-on lab —
a virtual-keyboard attacker versus a device-layer detector, benign and on my own
machine: **[badusb-offense-defense](https://github.com/volkansync/badusb-offense-defense)**.
The one-line thesis it starts from is the same thing this drive taught me:

> A USB device's identity is a claim the device makes about itself — not a fact the
> host verifies.

---

**Volkan Çevik** · Eskişehir, TR · [github.com/volkansync](https://github.com/volkansync)
