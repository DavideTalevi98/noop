import XCTest
@testable import Strand

/// Fresh-install restore must skip the onboarding wizard on relaunch: `noop.onboarded` is
/// install-local (not in BackupSettings whitelist), so prepareRelaunchAfterRestore sets it.
final class DataBackupRelaunchTests: XCTestCase {

    func testPrepareRelaunchMarksOnboarded() {
        let defaults = UserDefaults(suiteName: "DataBackupRelaunchTests.\(UUID().uuidString)")!
        defer { defaults.removePersistentDomain(forName: defaults.suiteName!) }
        XCTAssertFalse(defaults.bool(forKey: DataBackup.onboardedDefaultsKey))
        DataBackup.prepareRelaunchAfterRestore(defaults: defaults)
        XCTAssertTrue(defaults.bool(forKey: DataBackup.onboardedDefaultsKey))
    }
}
