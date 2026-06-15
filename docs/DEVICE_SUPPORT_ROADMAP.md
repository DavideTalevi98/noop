# Device support — roadmap & protocol notes

NOOP's north star is **WHOOP**, fully supported. Everything else is an opportunistic, easy-first
expansion that must never regress the WHOOP experience. This file records where each additional
source stands and the protocol facts we've verified, so the next build can pick up cleanly.

| Source | Status | How |
|--------|--------|-----|
| **WHOOP 4 / 5 / MG** | ✅ Shipped, primary | Local BLE decode |
| **Generic BLE heart-rate straps** (Polar / Wahoo / Coospo / Garmin HRM / Amazfit Helio HR-broadcast) | ✅ Shipped (v3.8.0), live HR + RR | Standard HR service `0x180D` / `0x2A37` |
| **Fitness Age / Vitality / Body Age** | ✅ Shipped (v4.0.0) | On-device, from the data above |
| **Polar deep streams** (ECG / PPG / ACC / PPI) | 🔬 Protocol verified, decoder not built | PMD service (below) — alpha, hardware-gated |
| **Garmin** (sleep / HRV / Body Battery / SpO₂ / FIT) | 📋 Researched, not built | Local BLE re-derive (Gadgetbridge-informed, **never** GPLv3 copy) |
| **Amazfit / Zepp** (incl. Helio deep) | 📋 Researched, not built | Encrypted Huami BLE — needs a one-time **user-pasted** vendor key (NOOP never logs into the vendor cloud) |
| **Oura** | 📋 Researched, not built | Cloud API v2 — off-by-default OAuth **import** lane only |
| **Fitbit / Google** | 📋 Researched, not built | Build against **Google Health** API (Fitbit Web API sunsets Sept 2026) — off-by-default import |

## Polar Measurement Data (PMD) — verified protocol

Source: official `polarofficial/polar-ble-sdk` (cross-verified). Lets us read ECG/PPG/ACC/PPI from a
Polar H10 / Verity Sense / OH1 the user owns, account-free, on top of the standard HR service.

- **Service UUID:** `FB005C80-02E7-F387-1CAD-8ACD2D8DF0C8`
  - **Control Point char:** `FB005C81-02E7-F387-1CAD-8ACD2D8DF0C8` (write + indicate)
  - **Data (MTU) char:** `FB005C82-02E7-F387-1CAD-8ACD2D8DF0C8` (notify)
- **Measurement-type codes (u8):** ECG `0`, PPG `1`, ACC `2`, PPI `3`, GYRO `5`, MAGNETOMETER `6` (mask `0x3F`).
- **Control-Point opcodes:** GET_MEASUREMENT_SETTINGS `1`, REQUEST_MEASUREMENT_START `2`, STOP_MEASUREMENT `3`.
  Start request byte = `(recordingType << 7) | measurementType`; settings are `[SettingType, len, data…]`
  blocks where SampleRate `0x00`, Resolution `0x01`, Range `0x02`.
- **Data frame:** `data[0]` = measurement type; `data[1..8]` = 64-bit little-endian timestamp (ns since
  2000-01-01 UTC); `data[9]` = frame type (`& 0x7F` = type, `& 0x80` = delta-compressed); payload from `data[10]`.
  - **ECG** type-0: 24-bit signed µV samples.
  - **ACC** type-0/1/2: 8/16/24-bit signed X/Y/Z (milli-g).
  - **PPI** type-0: `byte0` HR, `bytes1-2` peak-to-peak interval (ms), `bytes3-4` error estimate (ms),
    `byte5` flags (bit0 invalid, bit1 poor/no skin contact, bit2 contact unsupported).
  - **PPG** type-0: three 24-bit channels + ambient.
- **Per-model streams:** **H10** = ECG (130 Hz) + ACC + HR + RR (no PPG); **Verity Sense / OH1** =
  PPG + PPI + ACC + GYRO + HR (no ECG).

**Open item — #421** ("Polar H10 paired, no live data", Android): the generic-HR plumbing is correct
(CCCD write + both notification callbacks); the leading theory is the WHOOP auto-reconnect reclaiming
the radio while the strap is active. Needs the reporter's detail + an H10 in hand to verify a fix.

## Notes on the deep-band lanes (Garmin / Amazfit / cloud)

These "earn their place" — pursue only while tractable, defer/drop if they threaten WHOOP stability or
become a time-sink. Garmin/Amazfit decode is genuinely L-effort and best done with a device to capture
against; the cloud lanes need registered OAuth apps + real accounts to verify. None will ship "blind."
