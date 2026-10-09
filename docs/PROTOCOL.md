# Huawei FreeBuds control protocol

What this app speaks to the earbuds. Everything marked **verified** was exercised on a real
**HUAWEI FreeBuds Pro 5** (firmware 5.4.12, macOS 27). The protocol was first mapped by the
[OpenFreebuds](https://github.com/melianmiko/OpenFreebuds) project (GPL-3.0); this document and the
Swift implementation were written independently from observed traffic.

## Transport

Bluetooth Classic **RFCOMM** (serial port). On the Pro 5 the SDP records list "Serial Port" and
"Private COM" on **channel 1**; that is the control channel. Open it with `IOBluetoothDevice`
after the earbuds are connected to the Mac (A2DP/HFP). The earbuds can hold the channel for one
client at a time, so quit other tools (e.g. OpenFreebuds) first.

On macOS the process that owns the Bluetooth permission prompt must declare
`NSBluetoothAlwaysUsageDescription`, so this only works from an `.app` bundle.

## Frame

```
5A | length (2 bytes, big-endian) | 00 | command (2) | parameters… | CRC16 (2, big-endian)
```

* `length` = number of bytes in `command + parameters` + 1.
* A parameter is `type (1) | size (1) | value (size bytes)`.
* CRC is CRC-16/XMODEM (poly `0x1021`, init `0`) over everything before it.
* A *read* request lists the wanted parameter types with empty values.
* A response normally reuses the request's command id. The earbuds also push frames on their own
  when something changes (touch gestures, case lid, etc.).

Example (battery read): `5a 0009 00 0108 01 00 02 00 03 00 fbb9`

## Commands

Verified on a **HUAWEI FreeBuds Pro 5**, partly by driving the Huawei phone app (AI Life) on Android
while recording the Bluetooth HCI log, so the frames below are exactly what the official app sends.
The tests in `Tests/FreeBudsKitTests` compare this project's frames with those captures byte for byte.

### Readings

| Command | Meaning | Layout |
|---|---|---|
| `0108` | Battery | p1 overall %, p2 `[left, right, case]` %, p3 charging flags. `0127` pushes the same layout |
| `0107` | Device info | strings: p3 hardware, p7 firmware, p9 serial, p10 submodel, p15 model |
| `2b2a` | Noise control state | p1 `[level, mode]`, p2 = adaptive-awareness intensity (`0…10`, default `5`) |
| `2b4a` | Equalizer state | p2 current preset id, p3 list of preset ids the earbuds offer. Read with `2b4a` and an empty p2 |
| `2b4b` | Volume event (pushed) | sent on every swipe: direction, previous and new volume on a `0…127` scale |

### Noise control

`2b04` writes it; **the earbuds do not acknowledge**, they push `2b2a` instead.

| Setting | p1 |
|---|---|
| Off | `[00 00]` |
| Noise cancelling | `[01 ff]` (mode), then `[01 level]`: `01` cozy, `00` general, `02` ultra, `03` dual engine (automatic) |
| Awareness | `[02 ff]` (mode), then `[02 level]`: `02` standard, `01` voice, `04` adaptive |
| Adaptive intensity | `[02 04]` + p3 `[01]` + p4 `[0…10]`; `0` is "more noise", `10` "less noise" |

### Generic settings (`2bb4`)

Parameter 1 is the feature id, parameter 2 the value. A read sends an empty p2 and the earbuds answer
with the same command.

| Feature id | Setting | Value |
|---|---|---|
| `18` | Spatial audio | `0` off, `2` fixed, `1` head tracking |
| `0b` | Head control (nod to answer) | `0/1` |
| `05` | Noise cancelling with one earbud | `0/1` |
| `02` | Adaptive volume | `0/1` |
| `1b` | Conversation awareness | `0/1` |
| `10` | Case options | p2 is a 12-byte block, e.g. `01 00 0f 00…`; its **second byte is the "case opening tone"** flag. Write the whole block back with that byte changed. Only shown when the charging-case tone is on |

### Equalizer

`2b49` with p1 = preset id selects it; the earbuds answer with `2b4a`.

| Preset | id |
|---|---|
| Adaptive EQ | `11` (17) |
| Balanced | `05` |
| Voice | `09` |
| Bass | `02` |
| Movie | `0d` |
| Games | `0e` |
| Podcast | `0f` |
| Impact | `10` |
| Classic | `c9` (201), sent as a curve: p2 `0a` (bands), p5 `01`, p3 ten signed gains `fb 14 1e 0a 00 00 e7 f6 0a 00`, p4 the text `201` |

The earbuds also list ids `12` and `13` as available; they are not named in the phone app's list.

### Gestures

The Pro 5 has five kinds of gesture, each with its own command pair (write / read):

| Gesture | Commands | Layout | Action codes |
|---|---|---|---|
| Pinch (squeeze) | `2b92` / `2b93` | p1 kind (`0` once, `1` twice, `2` three times, `3` hold), p2 scenario (`2` normal, `1` in a call, `0` hold), p3 left, p4 right; read also returns p5 supported codes | `ff` none, `00` answer/end call, `01` reject, `02` play/pause, `03` previous, `04` next; hold: `05` assistant, `06` noise control |
| Tap (touch) double | `011f` / `0120` | p1 left, p2 right, p4 in a call | `01` play/pause, `00` answer (in call), `ff` none |
| Tap (touch) triple | `0125` / `0126` | p1 left, p2 right | `02` next, `07` previous, `ff` none |
| Press and hold | `2b16` / `2b17` | p1 left, p2 right | `00` assistant, `0a` noise control, `ff` none |
| Swipe | `2b1e` / `2b1f` | p1 and p2 | `00` volume, `ff` none |
| Noise-control cycle | `2b18` / `2b19` | p1 (one value for both sides; writing p1 or p2 sets both) | `01` off/cancelling, `02` off/cancelling/awareness, `03` cancelling/awareness, `04` off/awareness |

Writes are acknowledged with the same command id. The earbuds refuse nothing, but the phone app lets the
voice assistant live on only one gesture, and warns before moving it.

### Other

| Command | Meaning |
|---|---|
| `2b11` / `2b10` | Pause when removed (wear detection), `0/1` |
| `2b6c` | Low latency, write p1 `0/1`, read p2 |
| `2ba3` / `2ba2` | Sound preference: `0` connection stability, `1` sound quality |
| `2b2f` / `2b2e` | Multi-connection on/off: write `2b2e` p1 `0/1` (turning it off disconnects all but one device), read `2b2f` p1 |
| `2bb1` | Charging-case tone: write p1 `0/1`; the answer has p2 (tone on) and p3 (`01` when it can be changed, i.e. both earbuds in an open case) |
| `2b25` | Wear state, **pushed on every change** (read with p1…p4): p1 left in ear, p2 right in ear, p3 left in case, p4 right in case. The earbuds do **not** send an AVRCP pause to the Mac when removed, so the app pauses the music itself |
| `2b03` | State notification, p8/p9 in-ear flag (from OpenFreebuds, not observed) |

### Multi-connection devices

The earbuds can stay connected to several devices. Addresses are six bytes in **reverse order** (the address
`AA:BB:CC:DD:EE:FF` is `ff ee dd cc bb aa`).

| Command | Meaning |
|---|---|
| `2b31` read (p1 empty) | One `2b31` answer per device: p4 address, p5 connection state (`00` not connected, `01` connected, `07` connected and streaming audio: any non-zero value means connected), p6 kind (`04` computer, `01` phone), **p7 voice priority** `0/1`, p9 name, **p13 audio priority** `0/1` |
| `2b31` read with p4 = address | Same, for one device |
| `2b33` with the address as parameter *N* | Action *N*: **connect** is `4`, `6`, `1` sent in that order, **disconnect** is `5`, `7`, `2`; **`8` priority-all-audio on**, **`9` off**. Each is acknowledged with `2b33` p30 = *N*, p31 = `00` |
| `2b32` p1 = address | Voice-message priority for that device; six zero bytes clear it. The phone app also sends zeros here when it turns audio priority on or off |
| `2b36` (pushed) | Events: p5 = address + state (`01` connected, `00` disconnected, others during streaming), p7 = voice-priority address, p9 = address + audio-priority flag |

Audio priority and voice priority exclude each other (turning audio on clears voice).

### Custom equalizer

`2b49` with p1 = a profile id from `100` up; p2 `0a` (ten bands); p3 ten signed gains in tenths of a dB
(`−60…+60`, the phone app uses 1 dB steps at 60, 125, 250, 500, 1k, 2k, 4k, 8k, 12k, 16k Hz); p4 the name
(UTF-8, up to 24 bytes); **p5 `00` preview (plays it, not stored), `01` save, `02` delete**. The earbuds
answer with `2b4a`: p2 current id, p6/p7 the active curve and name, **p8 every stored profile** as
36-byte records (id, band count, ten gains, name padded to 24 bytes). Selecting a stored profile is
`2b49` with only p1 = its id.

### Quirks

* **One session at a time.** If an app leaves the control channel without closing it (a crash, a force quit),
  the earbuds keep that old session: the next client's channel *opens* but is **never answered**, until the
  earbuds' Bluetooth link is reset (closing the case does it). Reproduced by killing the app with SIGKILL and
  reopening it. The app therefore closes its channel when it quits, and if a new channel gets no answer within
  8 s it drops and re-opens the earbuds' Bluetooth connection (the music stops for a few seconds), then keeps
  asking macOS to reconnect for a minute.
* A channel that worked and then goes quiet is simply re-opened.

## Not decoded yet

* Equalizer ids `12` and `13`, and how many custom profiles the earbuds hold (the app stops at 5).
* Features `2bb4` ids `03`, `23`, `30` that the phone app reads on connect.
* Tip fit test and eartip tests (they play audio), find my earbuds (it makes the earbuds beep), firmware update.

To help: enable *Bluetooth HCI snoop log* on an Android phone, change one setting in Huawei AI Life,
and open an issue with the capture.
