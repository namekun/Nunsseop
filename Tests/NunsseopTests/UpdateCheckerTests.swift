import Foundation
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

struct UpdateCheckerReleaseTests {
    private func release(tag: String? = "v0.14.0", url: String? = "https://github.com/namekun/Nunsseop/releases/tag/v0.14.0") -> Data {
        var json: [String: Any] = [:]
        json["tag_name"] = tag
        json["html_url"] = url
        return (try? JSONSerialization.data(withJSONObject: json)) ?? Data()
    }

    @Test func parseAcceptsOnlyOurReleasePage() {
        #expect(UpdateChecker.parse(release()) == UpdateChecker.Release(version: "0.14.0"))
        #expect(UpdateChecker.parse(release(tag: "V1.2.3")) == UpdateChecker.Release(version: "1.2.3"))
        #expect(UpdateChecker.parse(release(tag: "0.14.0")) == UpdateChecker.Release(version: "0.14.0"))
        for url in [
            "http://github.com/namekun/Nunsseop/releases/tag/v0.14.0",
            "https://github.com.evil.com/namekun/Nunsseop/releases/tag/v0.14.0",
            "https://evil.com/github.com/namekun/Nunsseop/releases/tag/v0.14.0",
            "https://github.com/namekun/Nunsseop-evil/releases/tag/v0.14.0",
            "https://github.com/other/repo/releases/tag/v0.14.0",
            "https://github.com/namekun/Nunsseop",
            "github.com/namekun/Nunsseop/releases",
            "",
        ] {
            #expect(UpdateChecker.parse(release(url: url)) == nil, "\(url)")
        }
        #expect(UpdateChecker.parse(release(tag: nil)) == nil)
        #expect(UpdateChecker.parse(release(url: nil)) == nil)
        #expect(UpdateChecker.parse(Data("not json".utf8)) == nil)
        #expect(UpdateChecker.parse(Data("[]".utf8)) == nil)
    }

    @Test func aCheckFindsANewerReleaseOrNothing() {
        let newer = UpdateChecker.outcome(status: 200, data: release(tag: "v0.14.1"), current: "0.14.0")
        #expect(newer.newer == UpdateChecker.Release(version: "0.14.1") && !newer.failed)
        let same = UpdateChecker.outcome(status: 200, data: release(), current: "0.14.0")
        #expect(same.newer == nil && !same.failed)
        let older = UpdateChecker.outcome(status: 200, data: release(tag: "v0.13.9"), current: "0.14.0")
        #expect(older.newer == nil && !older.failed)
    }

    @Test func noReleasesYetIsNotAFailure() {
        let none = UpdateChecker.outcome(status: 404, data: Data(#"{"message":"Not Found"}"#.utf8), current: "0.14.0")
        #expect(none.newer == nil && !none.failed)
    }

    @Test func failedChecksAreFailuresThatLeaveWhatWasShown() {
        let failures: [(Int?, Data?)] = [(200, Data("not json".utf8)), (200, release(url: "https://evil.com/")), (500, release(tag: "v9.9.9")),
                                         (403, Data()), (nil, nil)]
        for (status, data) in failures {
            let result = UpdateChecker.outcome(status: status, data: data, current: "0.14.0")
            #expect(result.failed, "\(String(describing: status))")
            #expect(result.newer == nil)
        }
    }
}
