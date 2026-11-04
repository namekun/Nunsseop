import Foundation
import Testing
@testable import Nunsseop

struct ToolSettingsStringsTests {
    private static let keys = [
        "Gemini CLI, GitHub Copilot, Antigravity, Cursor, Hermes and Amp also report their sessions to the agents count and the Agents tab once connected.",
        "Approvals from GitHub Copilot, Antigravity and Cursor show in the notch too, where you can allow or deny them. While the notch holds one, the tool waits for it; “Answer in terminal” (“Answer in Cursor” for Cursor) hands it back. If Nunsseop isn't running, the tool asks as before.",
        "Hermes loads a plugin only after you enable it: run `hermes plugins enable nunsseop` in a terminal once.",
        "Copy Hermes enable command", "Enabled in Hermes", "Not enabled in Hermes yet",
        "Amp's plugin API is experimental, so an Amp update may stop this from working.",
        "Answer in Cursor",
        "Leave them to the terminal while it's in front",
    ]

    private func table(_ language: String) throws -> NSDictionary {
        let resources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources")
        return try #require(NSDictionary(contentsOfFile: resources.appendingPathComponent("\(language).lproj/Localizable.strings").path), Comment(rawValue: language))
    }

    @Test func theSentencesAboutTheNewToolsAreTranslatedIntoEveryLanguage() throws {
        for language in ["de", "es", "fr", "ja", "ko", "zh-Hans"] {
            let strings = try table(language)
            for key in Self.keys {
                let text = strings[key] as? String ?? ""
                #expect(!text.isEmpty && text != key, Comment(rawValue: "\(language): \(key)"))
                #expect(!text.contains("%"), Comment(rawValue: "\(language): \(key)"))
            }
            // The command to run, and the names of the tools, are not translated.
            let command = strings[Self.keys[2]] as? String ?? ""
            #expect(command.contains("`hermes plugins enable nunsseop`"), Comment(rawValue: language))
            for name in ["Gemini CLI", "GitHub Copilot", "Antigravity", "Cursor", "Hermes", "Amp"] {
                #expect((strings[Self.keys[0]] as? String ?? "").contains(name), Comment(rawValue: "\(language): \(name)"))
            }
            // The button the card shows for Cursor is the one the Settings text names, as the terminal's is.
            let approvals = strings[Self.keys[1]] as? String ?? ""
            #expect(approvals.contains(strings["Answer in terminal"] as? String ?? "?") && approvals.contains(strings["Answer in Cursor"] as? String ?? "?"),
                    Comment(rawValue: language))
        }
    }

    @Test func theCardNamesCursorsButtonForCursorOnly() {
        #expect(PermissionDialect.cursor.tag == "Cursor" && PermissionDialect.copilot.tag != "Cursor" && PermissionDialect.agy.tag != "Cursor")
    }

    @Test func theNewerToolsAreTheSixThatCameAfterTheFirstOnes() {
        #expect(NotifyIntegration.newerTools == [.gemini, .copilot, .antigravity, .cursor, .hermes, .amp])
        #expect(Set(NotifyIntegration.allCases).subtracting(NotifyIntegration.newerTools) == [.claudeCode, .codex, .openCode, .omp, .omo, .pi])
        for tool in NotifyIntegration.newerTools { #expect(NotifyIntegration.reportingSessions.contains(tool), "\(tool)") }
    }
}
