import Foundation
import CoreBluetooth
import WhoopProtocol

/// App-side glue around the pure `PuffinCapture`: gates on a user toggle, stamps each frame with a
/// wall-clock time and the live (standard-profile) heart rate, and persists the growing capture to a
/// JSON file under Application Support. Records both live/command frames and historical offload
/// frames (parity with Android's backfill capture). Read-only with respect to the strap — it only
/// records frames that already arrived, it never writes to the device — so it is always safe to leave on.
///
/// `@MainActor` because it reads `LiveState.heartRate` and updates published capture status; the
/// BLEManager delegate callbacks that feed it are already on the main queue.
@MainActor
final class PuffinFrameRecorder {
    /// UserDefaults flag, mirrored by the Settings toggle (`@AppStorage`). Separate from the puffin
    /// *probe* switch (`PuffinExperiment`): capturing is passive/safe, probing actively guesses.
    static let enabledKey = "noopPuffinCapture"

    /// Flush to disk every this-many frames so a crash/yank loses at most a handful of frames.
    private static let flushEvery = 25

    /// Soft cap on the total size of the puffin-captures directory (#27). One file is written per app
    /// launch and never trimmed, so without a cap the directory grows without bound — an experimental
    /// capture toggle a 5/MG user left on reached 19 GB. After each flush, oldest files are evicted
    /// (by filename, which is timestamp-sorted) until the total is back under the cap. Never deletes
    /// the file the current session is still writing.
    private static let directorySoftCapBytes = 50 * 1024 * 1024

    private weak var state: LiveState?
    private let buffer = PuffinCapture()
    private var sinceFlush = 0
    private var fileURL: URL?

    init(state: LiveState) {
        self.state = state
    }

    private var isEnabled: Bool { UserDefaults.standard.bool(forKey: Self.enabledKey) }

    /// `<AppSupport>/OpenWhoop/puffin-captures/`, created on demand.
    private static func captureDirectory() throws -> URL {
        let fm = FileManager.default
        let dir = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask,
                             appropriateFor: nil, create: true)
            .appendingPathComponent("OpenWhoop", isDirectory: true)
            .appendingPathComponent("puffin-captures", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Every on-disk `puffin-*.json` in the capture directory (newest last). Includes prior app-launch
    /// sessions the Settings "this session" export used to hide — that gap left multi-MB offload
    /// captures stranded on device while Export raw+log only shared the tiny current file.
    static func allCaptureURLs() -> [URL] {
        guard let dir = try? captureDirectory(),
              let entries = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.fileSizeKey],
                options: [.skipsHiddenFiles]) else { return [] }
        return entries
            .filter { $0.pathExtension == "json" && $0.lastPathComponent.hasPrefix("puffin-") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// `(fileCount, totalBytes)` for the capture directory — for Settings copy ("N files · X MB").
    static func diskInventory() -> (count: Int, bytes: Int) {
        let urls = allCaptureURLs()
        let bytes = urls.reduce(0) { sum, url in
            sum + ((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        }
        return (urls.count, bytes)
    }

    /// Record one puffin frame (off `fd4b0003/0004/0005/0007`). No-op unless capture is enabled.
    func capture(frame: [UInt8], char: CBUUID) {
        guard isEnabled else { return }
        let tsMs = Int(Date().timeIntervalSince1970 * 1000)
        buffer.record(frame: frame, char: char.uuidString.lowercased(),
                      tsMs: tsMs, hr: state?.heartRate)
        sinceFlush += 1
        state?.puffinCaptureCount = buffer.count
        if sinceFlush >= Self.flushEvery { flush() }
    }

    /// Write the full capture to disk (best-effort, atomic). Called periodically and on disconnect.
    func flush() {
        guard buffer.count > 0 else { return }
        do {
            let url = try sessionFileURL()
            let data = try buffer.encodedJSON()
            try data.write(to: url, options: .atomic)
            sinceFlush = 0
            state?.puffinCaptureURL = url
            // Bound on-disk growth (#27): evict oldest captures beyond the soft cap, never the
            // file this session is still writing.
            Self.evictOldCaptures(keeping: url)
        } catch {
            // Best-effort: a failed flush just means the next one rewrites the whole file.
        }
    }

    /// Enforce the directory soft cap by deleting the oldest capture files (best-effort). Filenames are
    /// `puffin-yyyyMMdd-HHmmss.json`, so lexicographic order is chronological — delete from the front
    /// until the total is back under the cap. `keep` (the active session file) is never deleted.
    private static func evictOldCaptures(keeping keep: URL) {
        let fm = FileManager.default
        guard let dir = try? captureDirectory() else { return }
        guard let entries = try? fm.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]) else { return }
        // Sort oldest-first by name (timestamped). Pair each with its size up front.
        let files = entries
            .filter { $0.pathExtension == "json" }
            .map { (url: $0, size: (try? $0.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0) }
            .sorted { $0.url.lastPathComponent < $1.url.lastPathComponent }
        var total = files.reduce(0) { $0 + $1.size }
        for file in files {
            guard total > directorySoftCapBytes else { break }
            if file.url == keep { continue }   // never delete the active session file
            do {
                try fm.removeItem(at: file.url)
                total -= file.size
            } catch {
                // Best-effort: skip a file we couldn't remove; the next flush retries.
            }
        }
    }

    /// One file per recorder lifetime (i.e. per app launch), named on first use. Re-flushing rewrites
    /// the same file, so the capture file always holds the complete session.
    private func sessionFileURL() throws -> URL {
        if let url = fileURL { return url }
        let stamp = Self.fileStampFormatter.string(from: Date())
        let url = try Self.captureDirectory().appendingPathComponent("puffin-\(stamp).json")
        fileURL = url
        return url
    }

    private static let fileStampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f
    }()
}
