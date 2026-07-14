import XCTest
@testable import Strand

/// Fresh-install restore must skip the onboarding wizard on relaunch: `noop.onboarded` is
/// install-local (not in BackupSettings whitelist), so prepareRelaunchAfterRestore sets it.
final class DataBackupRelaunchTests: XCTestCase {

    func testPrepareRelaunchMarksOnboarded() {
        let suite = "DataBackupRelaunchTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertFalse(defaults.bool(forKey: DataBackup.onboardedDefaultsKey))
        DataBackup.prepareRelaunchAfterRestore(defaults: defaults)
        XCTAssertTrue(defaults.bool(forKey: DataBackup.onboardedDefaultsKey))
    }
}
