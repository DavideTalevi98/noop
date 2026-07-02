import Foundation

/// Spo2ReTrace — a diagnostic dump for reverse-engineering WHOOP SpO2 (Blood O2).
///
/// NOOP decodes the raw red/IR PPG channels (spo2_red@68 / spo2_ir@70 on the WHOOP 4.0 v24 layout) but
/// never surfaces a calibrated % — computing SpO2 from raw ADC ourselves needs the dense dual-wavelength
/// waveform + WHOOP's proprietary calibration, and guessing it would manufacture a plausible-but-wrong
/// health number (the trap that withdrew the #194 PPG->HR attempt). The only honest path to a reliable
/// value is to find whether the strap already BANKS a computed SpO2 in some record field.
///
/// This dumps a few full historical records + their mapped SpO2 channels so an offline pass can correlate
/// a byte (or the red/IR pair) against the SpO2 % the WHOOP app shows for the same nights. Full record, no
/// prefix cap. Diagnostic-only: emitted only while the Connection test mode is on, bounded per session, and
/// it never changes stored data.
///
/// Byte-identical OUTPUT to the Kotlin `Spo2ReTrace`. The Kotlin twin takes the decoded map directly;
/// here the caller passes the already-extracted ints, so this stays free of a WhoopProtocol dependency
/// (matching `ConnectionTrace`'s primitive signature) — the emitted line format is identical either way.
public enum Spo2ReTrace {

    /// Max records to dump per offload session — a handful is enough to correlate and keeps the strap log
    /// bounded. Records are dumped whether or not they carry SpO2, so "nothing banked" is provable too.
    public static let maxSamples = 8

    /// One record's RE line: the FULL frame hex + the mapped SpO2 channels + unix + layout version.
    public static func recordLine(frame: [UInt8], version: Int?, unix: Int?,
                                  red: Int?, ir: Int?, skinRaw: Int?) -> String {
        let hex = frame.map { String(format: "%02x", $0) }.joined()
        func s(_ v: Int?) -> String { v.map(String.init) ?? "null" }
        return "spo2re v=\(s(version)) unix=\(s(unix)) red=\(s(red)) ir=\(s(ir)) "
            + "skinRaw=\(s(skinRaw)) len=\(frame.count) raw=\(hex)"
    }
}
