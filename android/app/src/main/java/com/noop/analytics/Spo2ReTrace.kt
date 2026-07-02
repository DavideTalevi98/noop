package com.noop.analytics

/*
 * Spo2ReTrace.kt — a diagnostic dump for reverse-engineering WHOOP SpO2 (Blood O2).
 *
 * NOOP decodes the raw red/IR PPG channels (spo2_red@68 / spo2_ir@70 on the WHOOP 4.0 v24 layout) but
 * never surfaces a calibrated % — computing SpO2 from raw ADC ourselves needs the dense dual-wavelength
 * waveform + WHOOP's proprietary calibration, and guessing it would manufacture a plausible-but-wrong
 * health number (the same trap that withdrew the #194 PPG->HR attempt). The ONLY honest path to a
 * reliable value is to find whether the strap already BANKS a computed SpO2 in some record field.
 *
 * This dumps a few full historical records + their mapped SpO2 channels so an offline pass can correlate
 * a byte (or the red/IR pair) against the SpO2 % the WHOOP app shows for the same nights. Full record, no
 * prefix cap (a WHOOP 4 v24 record is ~84 B, so the whole frame fits one line). Diagnostic-only: emitted
 * only while the Connection test mode is on, bounded per session, and it never changes stored data.
 *
 * Byte-for-byte twin of the Swift Spo2ReTrace.
 */
object Spo2ReTrace {

    /** Max records to dump per offload session — a handful is enough to correlate and keeps the strap log
     *  bounded. Records are dumped whether or not they carry SpO2, so "no SpO2 banked" is provable too. */
    const val MAX_SAMPLES = 8

    /** One record's RE line: the FULL frame hex + the mapped SpO2 channels + unix + layout version. [decoded]
     *  is the map from `decodeHistorical` for the SAME frame. No prefix cap (full record) per the diagnostic-
     *  dump convention. */
    fun recordLine(frame: ByteArray, decoded: Map<String, Any?>): String {
        val hex = frame.joinToString("") { String.format("%02x", it.toInt() and 0xFF) }
        return "spo2re v=${decoded["hist_version"]} unix=${decoded["unix"]} " +
            "red=${decoded["spo2_red"]} ir=${decoded["spo2_ir"]} skinRaw=${decoded["skin_temp_raw"]} " +
            "len=${frame.size} raw=$hex"
    }
}
