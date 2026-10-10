import Testing
@testable import Nunsseop

struct UpdateCheckerTests {
    @Test(arguments: [
        ("0.13.6", "0.13.5", true), ("0.14", "0.13.9", true), ("1.0.0", "0.99.99", true), ("0.10", "0.9", true),
        ("0.13.5", "0.13.5", false), ("0.13", "0.13.0", false), ("0.13.0", "0.13", false),
        ("0.9", "0.10", false), ("0.13.4", "0.13.5", false),
    ])
    func comparesVersions(candidate: String, current: String, newer: Bool) {
        #expect(UpdateChecker.isNewer(candidate, than: current) == newer)
    }

    @Test func updateCommandUpgradesAHomebrewInstallAndReplacesAnyOther() {
        #expect(UpdateChecker.brewCommand(installedWithBrew: true) == "brew update && brew upgrade --cask nunsseop")
        #expect(UpdateChecker.brewCommand(installedWithBrew: false) == "brew update && brew install --cask --force namekun/tap/nunsseop")
    }
}
