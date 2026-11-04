import CryptoKit
import Foundation
import Testing
@testable import Nunsseop

struct PermissionWireTests {
    private func json(_ data: Data) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func theProofIsAnHMACOverTheDomainTheNonceAndTheBodysDigest() {
        let key = String(repeating: "ab", count: 32), nonce = String(repeating: "0f", count: 16)
        let body = Data("{\"tool_name\":\"Bash\"}".utf8)
        let digest = SHA256.hash(data: body).map { String(format: "%02x", $0) }.joined()
        let message = Data("nunsseop-permission-request\n\(nonce)\n\(digest)".utf8)
        let expected = HMAC<SHA256>.authenticationCode(for: message, using: SymmetricKey(data: Data(key.utf8)))
            .map { String(format: "%02x", $0) }.joined()
        #expect(PermissionWire.requestProof(key: key, nonce: nonce, body: body) == expected)
        #expect(expected.count == 64)
    }

    @Test func requestAndResponseProofsAreBoundToTheirDomainAndNonce() {
        let key = String(repeating: "cd", count: 32), nonce = String(repeating: "1a", count: 16)
        let other = String(repeating: "2b", count: 16)
        let bytes = Data("same bytes".utf8)
        let request = PermissionWire.requestProof(key: key, nonce: nonce, body: bytes)
        let response = PermissionWire.responseProof(key: key, nonce: nonce, decision: bytes)
        #expect(request != response)
        #expect(response != PermissionWire.responseProof(key: key, nonce: other, decision: bytes))
        #expect(response != PermissionWire.responseProof(key: key + "0", nonce: nonce, decision: bytes))
        #expect(response != PermissionWire.responseProof(key: key, nonce: nonce, decision: bytes + [0x20]))
    }

    @Test func aNonceIsSixteenBytesOfLowercaseHex() {
        #expect(PermissionWire.isNonce(String(repeating: "0a", count: 16)))
        for bad in ["", String(repeating: "0a", count: 15), String(repeating: "0a", count: 17), String(repeating: "0A", count: 16),
                    String(repeating: "g0", count: 16), String(repeating: "0a", count: 15) + "0\n"] {
            #expect(!PermissionWire.isNonce(bad), "\(bad)")
        }
    }

    @Test func theDecisionsAreExactlyWhatClaudeCodeReads() throws {
        let prefix = #"{"hookSpecificOutput":{"decision":{"#
        let suffix = #"},"hookEventName":"PermissionRequest"}}"#
        #expect(String(decoding: try #require(PermissionWire.decision(.allow, suggestion: nil)), as: UTF8.self)
                == prefix + #""behavior":"allow""# + suffix)
        #expect(String(decoding: try #require(PermissionWire.decision(.deny, suggestion: nil)), as: UTF8.self)
                == prefix + #""behavior":"deny","message":"Denied in Nunsseop""# + suffix)
    }

    @Test func alwaysAllowEchoesTheOneSuggestionAndNeedsOne() throws {
        let data = try #require(PermissionWire.decision(.always, suggestion: PermissionTestServer.addRules))
        let decision = try #require((try json(data)["hookSpecificOutput"] as? [String: Any])?["decision"] as? [String: Any])
        #expect(decision["behavior"] as? String == "allow")
        let updated = try #require(decision["updatedPermissions"] as? [[String: Any]])
        #expect(updated.count == 1)
        #expect(NSDictionary(dictionary: updated[0]).isEqual(to: PermissionTestServer.addRules))
        #expect(!String(decoding: data, as: UTF8.self).contains("setMode"))
        #expect(PermissionWire.decision(.always, suggestion: nil) == nil)
    }

    @Test func aDecisionIsOneLineEvenForAnAwkwardRule() throws {
        let rule: [String: Any] = ["type": "addRules", "behavior": "allow", "destination": "localSettings",
                                   "rules": [["toolName": "Bash", "ruleContent": "echo \"a\\b\"\n100% $HOME `x`"]]]
        let data = try #require(PermissionWire.decision(.always, suggestion: rule))
        #expect(!data.contains(0x0a))
    }
}

struct PermissionPromptParseTests {
    private func parse(_ tool: String, _ input: [String: Any], cwd: String = "/Users/me/proj",
                       suggestions: [[String: Any]]? = nil) -> PermissionPrompt.Parsed? {
        PermissionPrompt.parse(PermissionTestServer.hookInput(tool: tool, input: input, cwd: cwd, suggestions: suggestions))
    }

    private func addRules(_ rules: [[String: Any]], destination: String? = "localSettings") -> [String: Any] {
        var suggestion: [String: Any] = ["type": "addRules", "behavior": "allow", "rules": rules]
        suggestion["destination"] = destination
        return suggestion
    }

    @Test func aCommandIsShownWithItsFolderAndTheRuleItWouldAdd() throws {
        let parsed = try #require(parse("Bash", ["command": "npm run build"], suggestions: [PermissionTestServer.addRules]))
        #expect(parsed.prompt.title == "Run a command")
        #expect(parsed.prompt.detail == "npm run build")
        #expect(parsed.prompt.folder == "proj")
        #expect(parsed.prompt.grant == PermissionPrompt.Grant(rules: ["Bash(npm run *)"], place: .localSettings))
        #expect(parsed.prompt.symbol == "terminal")
        #expect(parsed.suggestion != nil)
    }

    @Test func fileAndWebToolsSayWhatTheyDoInPlainWords() throws {
        let cases: [(String, [String: Any], String, String)] = [
            ("Edit", ["file_path": "/a/b.swift"], "Edit a file", "/a/b.swift"),
            ("MultiEdit", ["file_path": "/a/c.swift"], "Edit a file", "/a/c.swift"),
            ("Write", ["file_path": "/a/new.txt"], "Write a file", "/a/new.txt"),
            ("NotebookEdit", ["notebook_path": "/a/n.ipynb"], "Edit a notebook", "/a/n.ipynb"),
            ("Read", ["file_path": "/etc/hosts"], "Read a file", "/etc/hosts"),
            ("WebFetch", ["url": "https://example.com/x"], "Fetch a web page", "https://example.com/x"),
            ("WebSearch", ["query": "swift nio"], "Search the web", "swift nio"),
        ]
        for (tool, input, title, detail) in cases {
            let parsed = try #require(parse(tool, input), "\(tool)")
            #expect(parsed.prompt.title == title && parsed.prompt.detail == detail && parsed.prompt.secondary.isEmpty, "\(tool)")
        }
    }

    // MARK: Known tools hide nothing

    @Test func aCommandShowsItsDescriptionAndEveryOtherFieldItWasGiven() throws {
        let prompt = try #require(parse("Bash", ["command": "make", "description": "Build it", "timeout": 120000, "cwd": "/tmp"])).prompt
        #expect(prompt.detail == "make" && prompt.flags.isEmpty)
        #expect(prompt.secondary == "description: Build it\ncwd: /tmp\ntimeout: 120000")
        #expect(prompt.scrollText == "make\ndescription: Build it\ncwd: /tmp\ntimeout: 120000")
        let plain = try #require(parse("Bash", ["command": "make"])).prompt
        #expect(plain.secondary.isEmpty && plain.scrollText == "make")
    }

    @Test func aCommandWithTheSandboxOffOrInTheBackgroundSaysSoAboveIt() throws {
        let both = try #require(parse("Bash", ["command": "curl x", "dangerouslyDisableSandbox": true, "run_in_background": true])).prompt
        #expect(both.flags == [.init(text: "Sandbox off", warns: true), .init(text: "Runs in the background", warns: false)])
        #expect(both.scrollText == "Sandbox off\nRuns in the background\ncurl x")
        #expect(both.secondary.isEmpty, "the flags are not listed twice")
        let sandbox = try #require(parse("Bash", ["command": "x", "dangerouslyDisableSandbox": true])).prompt
        #expect(sandbox.flags == [.init(text: "Sandbox off", warns: true)])
        let background = try #require(parse("Bash", ["command": "x", "run_in_background": true])).prompt
        #expect(background.flags == [.init(text: "Runs in the background", warns: false)])
        // Anything that is not true is only listed.
        for value: Any in [false, "false", "yes", "", 0, 0.0, NSNull(), [1], ["a": 1]] {
            let prompt = try #require(parse("Bash", ["command": "x", "dangerouslyDisableSandbox": value])).prompt
            #expect(prompt.flags.isEmpty && prompt.secondary.hasPrefix("dangerouslyDisableSandbox: "), "\(value)")
        }
    }

    @Test func aSandboxSwitchedOffInAnyFormTheToolMayReadAsTrueIsFlaggedAndStillListedAsItCame() throws {
        let cases: [(Any, String)] = [("true", "dangerouslyDisableSandbox: true"), ("TRUE", "dangerouslyDisableSandbox: TRUE"),
                                      ("True", "dangerouslyDisableSandbox: True"), (1, "dangerouslyDisableSandbox: 1"),
                                      (-2, "dangerouslyDisableSandbox: -2"), (0.5, "dangerouslyDisableSandbox: 0.5")]
        for (value, listed) in cases {
            let prompt = try #require(parse("Bash", ["command": "x", "dangerouslyDisableSandbox": value])).prompt
            #expect(prompt.flags == [.init(text: "Sandbox off", warns: true)], "\(value)")
            #expect(prompt.secondary == listed, "\(value)")
            #expect(prompt.scrollText == "Sandbox off\nx\n\(listed)", "\(value)")
        }
    }

    @Test func aFileEditShowsThePathAndBothSidesOfTheChange() throws {
        let edit = try #require(parse("Edit", ["file_path": "/a/b.swift", "old_string": "let a = 1", "new_string": "let a = 2\nlet b = 3",
                                                "replace_all": true])).prompt
        #expect(edit.title == "Edit a file")
        #expect(edit.detail == "/a/b.swift\nold:\nlet a = 1\nnew:\nlet a = 2\nlet b = 3")
        #expect(edit.secondary == "replace_all: true")
        // Deleting text is an edit with nothing new in it, and is shown as one.
        let deletion = try #require(parse("Edit", ["file_path": "/a", "old_string": "x", "new_string": ""])).prompt
        #expect(deletion.detail == "/a\nold:\nx\nnew:\n")
    }

    @Test func aMultiEditShowsEveryEdit() throws {
        let edits: [[String: Any]] = [["old_string": "a", "new_string": "b"], ["old_string": "c", "new_string": "d", "replace_all": true]]
        let prompt = try #require(parse("MultiEdit", ["file_path": "/a/b.swift", "edits": edits])).prompt
        #expect(prompt.detail == "/a/b.swift\nedit 1 of 2:\nold:\na\nnew:\nb\nedit 2 of 2:\nold:\nc\nnew:\nd\nreplace_all: true")
        #expect(prompt.secondary.isEmpty)
        // Edits that are not a list of objects are listed as they came.
        let odd = try #require(parse("MultiEdit", ["file_path": "/a", "edits": ["x", 3]])).prompt
        #expect(odd.detail == "/a" && odd.secondary == #"edits: ["x",3]"#)
    }

    @Test func aWriteShowsThePathAndWhatGoesInTheFile() throws {
        let prompt = try #require(parse("Write", ["file_path": "/a/new.txt", "content": "line 1\nline 2"])).prompt
        #expect(prompt.title == "Write a file")
        #expect(prompt.detail == "/a/new.txt\ncontent:\nline 1\nline 2" && prompt.secondary.isEmpty)
        let hidden = try #require(parse("Write", ["file_path": "/a", "content": "x\u{202E}y"])).prompt
        #expect(hidden.detail == "/a\ncontent:\nx⟨U+202E⟩y")
    }

    @Test func aNotebookEditShowsThePathTheNewSourceAndTheCell() throws {
        let prompt = try #require(parse("NotebookEdit", ["notebook_path": "/a/n.ipynb", "new_source": "print(1)", "cell_id": "c3",
                                                          "edit_mode": "replace", "cell_type": "code"])).prompt
        #expect(prompt.detail == "/a/n.ipynb\nnew_source:\nprint(1)")
        #expect(prompt.secondary == "cell_id: c3\ncell_type: code\nedit_mode: replace")
    }

    @Test func anyUnexpectedFieldOfAKnownToolIsListedEscaped() throws {
        let cases: [(String, [String: Any], String)] = [
            ("Bash", ["command": "ls", "extra": "a\u{202E}b"], "extra: a⟨U+202E⟩b"),
            ("Edit", ["file_path": "/a", "old_string": "x", "new_string": "y", "hidden": ["k": 1]], #"hidden: {"k":1}"#),
            ("Write", ["file_path": "/a", "content": "x", "mode": "0777"], "mode: 0777"),
            ("NotebookEdit", ["notebook_path": "/a", "new_source": "x", "n": 2], "n: 2"),
            ("Read", ["file_path": "/a", "offset": 10, "limit": 5], "limit: 5\noffset: 10"),
            ("WebFetch", ["url": "https://x.y", "prompt": "Summarize it"], "prompt: Summarize it"),
            ("WebSearch", ["query": "q", "allowed_domains": ["a.com"]], #"allowed_domains: ["a.com"]"#),
        ]
        for (tool, input, secondary) in cases {
            #expect(try #require(parse(tool, input), "\(tool)").prompt.secondary == secondary, "\(tool)")
        }
        // A field's name is escaped like its value.
        #expect(try #require(parse("Bash", ["command": "ls", "k\u{200B}ey": 1])).prompt.secondary == "k⟨U+200B⟩ey: 1")
    }

    @Test func whatIsShownAcrossAllItsPartsCountsAgainstTheLimit() {
        let half = String(repeating: "a", count: PermissionPrompt.detailLimit / 2)
        #expect(parse("Write", ["file_path": "/a", "content": half]) != nil)
        #expect(parse("Write", ["file_path": "/a", "content": half + half]) == nil)
        #expect(parse("Bash", ["command": "ls", "description": String(repeating: "d", count: PermissionPrompt.detailLimit)]) == nil)
        #expect(parse("Edit", ["file_path": "/a", "old_string": half, "new_string": half]) == nil)
    }

    // MARK: Tools without a plain description

    @Test func anyOtherToolShowsItsOwnNameAndAllOfItsInput() throws {
        let parsed = try #require(parse("mcp__github__create_issue", ["title": "Bug", "labels": ["a", "b"]]))
        #expect(parsed.prompt.title == "mcp__github__create_issue")
        #expect(parsed.prompt.detail == "{\n  \"labels\" : [\n    \"a\",\n    \"b\"\n  ],\n  \"title\" : \"Bug\"\n}")
        for tool in ["Task", "Skill", "TodoWrite"] {
            let prompt = try #require(parse(tool, ["description": "run /deploy", "n": 1])).prompt
            #expect(prompt.title == tool, "\(tool)")
            #expect(prompt.detail.contains(#""description" : "run /deploy""#) && prompt.detail.contains(#""n" : 1"#), "\(tool)")
        }
        #expect(try #require(parse("mcp__a__b", [:])).prompt.detail.isEmpty)
    }

    @Test func aKnownToolWhoseFieldIsNotTheTextItShouldBeShowsEverythingInstead() throws {
        for input: [String: Any] in [["command": 7, "timeout": 5], ["cmd": "ls"], ["command": ""]] {
            let prompt = try #require(parse("Bash", input)).prompt
            #expect(prompt.title == "Bash" && prompt.symbol == "puzzlepiece.extension")
            #expect(prompt.detail.contains(input.keys.sorted().first!))
        }
    }

    @Test func aToolNameIsEscapedLikeTheRestAndNotAcceptedWhenTooLongToShow() throws {
        let prompt = try #require(parse("Task\u{202E}x", [:])).prompt
        #expect(prompt.title == "Task⟨U+202E⟩x")
        #expect(parse(String(repeating: "t", count: PermissionPrompt.titleLimit), [:]) != nil)
        #expect(parse(String(repeating: "t", count: PermissionPrompt.titleLimit + 1), [:]) == nil)
    }

    @Test func questionsPlansAndNonsenseAreLeftToTheTerminal() {
        #expect(parse("AskUserQuestion", ["questions": []]) == nil)
        #expect(parse("ExitPlanMode", ["plan": "x"]) == nil)
        #expect(PermissionPrompt.parse(Data("not json".utf8)) == nil)
        #expect(PermissionPrompt.parse(Data()) == nil)
        let other = try! JSONSerialization.data(withJSONObject: ["hook_event_name": "Stop", "tool_name": "Bash"])
        #expect(PermissionPrompt.parse(other) == nil)
        let nameless = try! JSONSerialization.data(withJSONObject: ["hook_event_name": "PermissionRequest"])
        #expect(PermissionPrompt.parse(nameless) == nil)
    }

    // MARK: Lines and invisible characters

    @Test func lineBreaksStayLineBreaksAndNothingIsJoined() throws {
        let command = "echo safe\n\n\nrm -rf ~\r\nls"
        let prompt = try #require(parse("Bash", ["command": command])).prompt
        #expect(prompt.detail == "echo safe\n\n\nrm -rf ~\nls")
        #expect(prompt.detail.components(separatedBy: "\n").count == 5)
        #expect(PermissionText.escape("a\nb", multiline: false) == "a⟨U+000A⟩b")
    }

    @Test func controlZeroWidthAndDirectionCharactersAreShownNotRemoved() {
        #expect(PermissionText.escape("rm\u{202E} -rf\u{200B} /", multiline: true) == "rm⟨U+202E⟩ -rf⟨U+200B⟩ /")
        let invisible: [UInt32] = Array(0x200B...0x200F) + Array(0x202A...0x202E) + Array(0x2066...0x2069)
            + [0xFEFF, 0x00AD, 0x2060, 0xE0041, 0x0000, 0x0007, 0x001B, 0x007F, 0x0085, 0x2028, 0x2029, 0x00A0, 0x3000, 0x2003]
        for value in invisible {
            let scalar = Character(Unicode.Scalar(value)!)
            #expect(PermissionText.escape("a\(scalar)b", multiline: true) == "a" + String(format: "⟨U+%04X⟩", value) + "b",
                    "U+\(String(value, radix: 16, uppercase: true))")
        }
        #expect(PermissionText.escape("a\tb\rc", multiline: true) == "a⇥ b⟨U+000D⟩c")
        // A written-out escape can't be told from a real one, so the brackets are escaped too.
        #expect(PermissionText.escape("⟨U+202E⟩", multiline: true) == "⟨U+27E8⟩U+202E⟨U+27E9⟩")
        for plain in ["echo \"한글 😀 é\" 'x' $HOME `id` 100% \\n", "👨‍👩‍👧"] where plain != "👨‍👩‍👧" {
            #expect(PermissionText.escape(plain, multiline: true) == plain)
        }
    }

    @Test func scalarsThatDrawNothingAreShownEvenWhenNotFormatCharacters() {
        func hex(_ value: UInt32) -> String { String(format: "⟨U+%04X⟩", value) }
        var blanks: [UInt32] = [0x2800, 0x3164, 0xFFA0, 0x115F, 0x1160, 0x17B4, 0x17B5, 0x034F, 0x061C, 0x180E, 0x1680, 0x202F, 0x205F,
                                0xFFFC, 0xFFF9, 0xE000, 0xF8FF, 0x0378, 0xE0001, 0x1D173, 0x2063, 0x2064]
        blanks += Array(0xFE00...0xFE0F) + Array(0xE0100...0xE01EF) + Array(0x180B...0x180F) + Array(0x2000...0x200A)
        for value in blanks {
            let scalar = Character(Unicode.Scalar(value)!)
            #expect(PermissionText.escape("a\(scalar)b", multiline: true) == "a" + hex(value) + "b", "U+\(String(value, radix: 16, uppercase: true))")
        }
        // Every default-ignorable scalar of the table, whatever the list above says.
        var checked = 0
        for value in UInt32(0)...0xE01EF {
            guard let scalar = Unicode.Scalar(value), scalar.properties.isDefaultIgnorableCodePoint else { continue }
            #expect(PermissionText.escape("a\(scalar)b", multiline: true) == "a" + hex(value) + "b", "U+\(String(value, radix: 16, uppercase: true))")
            checked += 1
        }
        #expect(checked > 300)
        // A variation selector with nothing to select for is written out.
        #expect(PermissionText.escape("a\u{FE0F}", multiline: true) == "a⟨U+FE0F⟩")
    }

    // MARK: Noise that is not a danger

    @Test func aTabIsShownAsAGlyphAndAnArrowLikeItIsWrittenOutSoTheTwoCantBeConfused() throws {
        #expect(PermissionText.escape("a\tb", multiline: true) == "a⇥ b")
        #expect(PermissionText.escape("a\tb", multiline: false) == "a⇥ b")
        #expect(PermissionText.escape("\t\tx", multiline: true) == "⇥ ⇥ x")
        #expect(PermissionText.escape("a⇥ b", multiline: true) == "a⟨U+21E5⟩ b")
        let prompt = try #require(parse("Bash", ["command": "if x\n\tthen y", "description": "a\tb"])).prompt
        #expect(prompt.detail == "if x\n⇥ then y" && prompt.secondary == "description: a⇥ b")
        // A mark has nothing to sit on after a tab, as after any other escape.
        #expect(scalars(PermissionText.escape("x\u{323}\t\u{323}", multiline: true)) == scalars("x\u{323}⇥ ⟨U+0323⟩"))
    }

    @Test func whatEmojiAreMadeOfDisplaysAndNothingElseOfTheKindDoes() {
        let emoji = ["⚠\u{FE0F}", "❤\u{FE0F}", "👨\u{200D}👩\u{200D}👧", "❤\u{FE0F}\u{200D}🔥", "👩🏽\u{200D}⚕\u{FE0F}", "1\u{FE0F}\u{20E3}",
                     "🧑\u{200D}🧑\u{200D}🧒\u{200D}🧒",
                     "echo ⚠\u{FE0F} done"]
        for text in emoji {
            #expect(PermissionText.escape(text, multiline: true) == text, "\(text.unicodeScalars.map(\.value))")
        }
        func hex(_ value: UInt32) -> String { String(format: "⟨U+%04X⟩", value) }
        let escaped: [(String, String)] = [
            ("a\u{FE0F}", "a" + hex(0xFE0F)),
            ("\u{FE0F}", hex(0xFE0F)),
            ("\nx\u{FE0F}", "\nx" + hex(0xFE0F)),
            ("❤\u{FE0F}\u{FE0F}", "❤\u{FE0F}" + hex(0xFE0F)),
            ("1\u{FE0F}", "1" + hex(0xFE0F)),
            ("#\u{FE0F}x", "#" + hex(0xFE0F) + "x"),
            ("😀\u{FE00}", "😀" + hex(0xFE00)),
            ("😀\u{FE0D}", "😀" + hex(0xFE0D)),
            ("\u{200D}", hex(0x200D)),
            ("a\u{200D}b", "a" + hex(0x200D) + "b"),
            ("😀\u{200D}b", "😀" + hex(0x200D) + "b"),
            ("a\u{200D}😀", "a" + hex(0x200D) + "😀"),
            ("😀\u{200D}", "😀" + hex(0x200D)),
            ("😀\u{200D}\u{200D}😀", "😀" + hex(0x200D) + hex(0x200D) + "😀"),
            ("😀\u{200D}1", "😀" + hex(0x200D) + "1"),
            ("😀\u{200D}\u{FE0F}😀", "😀" + hex(0x200D) + hex(0xFE0F) + "😀"),
            ("😀\n\u{200D}😀", "😀\n" + hex(0x200D) + "😀"),
            ("😀\u{202E}\u{200D}😀", "😀" + hex(0x202E) + hex(0x200D) + "😀"),
        ]
        for (text, expected) in escaped {
            #expect(PermissionText.escape(text, multiline: true) == expected, "\(text.unicodeScalars.map(\.value))")
        }
    }

    @Test func joinersAndSelectorsNeverStayBesideATextSymbol() {
        func hex(_ value: UInt32) -> String { String(format: "⟨U+%04X⟩", value) }
        for symbol in ["©", "®", "↔", "↩", "〰", "▶"] {
            #expect(PermissionText.escape(symbol + "\u{FE0F}", multiline: true) == symbol + hex(0xFE0F), "\(symbol) then selector")
            #expect(PermissionText.escape(symbol + "\u{200D}" + symbol, multiline: true) == symbol + hex(0x200D) + symbol, "\(symbol) joined")
            #expect(PermissionText.escape(symbol + "\u{200D}😀", multiline: true) == symbol + hex(0x200D) + "😀", "\(symbol) before a face")
            #expect(PermissionText.escape("😀\u{200D}" + symbol, multiline: true) == "😀" + hex(0x200D) + symbol, "\(symbol) after a face")
        }
        // Text symbols that no block of the allowlist holds are written out whole, and nothing is left to join to.
        for symbol: UInt32 in [0x24C2, 0x2934, 0x3297] {
            let text = String(Unicode.Scalar(symbol)!)
            #expect(PermissionText.escape(text + "\u{FE0F}", multiline: true) == hex(symbol) + hex(0xFE0F), "U+\(String(symbol, radix: 16))")
            #expect(PermissionText.escape("😀\u{200D}" + text, multiline: true) == "😀" + hex(0x200D) + hex(symbol), "U+\(String(symbol, radix: 16))")
        }
        #expect(PermissionText.escape("©\u{200D}®", multiline: true) == "©⟨U+200D⟩®")
        // Nor beside the ones that read as ASCII, which are shown, with a word of ASCII or not, and take neither.
        for symbol: UInt32 in [0x2122, 0x2139, 0x203C] {
            let text = String(Unicode.Scalar(symbol)!)
            #expect(PermissionText.escape(text + "\u{FE0F}", multiline: true) == text + hex(0xFE0F), "U+\(String(symbol, radix: 16))")
            #expect(PermissionText.escape("😀\u{200D}" + text, multiline: true) == "😀" + hex(0x200D) + text, "U+\(String(symbol, radix: 16))")
            // The information source is the letter i of the letterlike block, a look-alike written out beside an ASCII letter.
            #expect(PermissionText.escape("a" + text, multiline: true) == "a" + (symbol == 0x2139 ? hex(symbol) : text), "U+\(String(symbol, radix: 16))")
        }
        // Neither a flag letter, a skin tone nor a digit takes a joiner.
        #expect(PermissionText.escape("😀\u{200D}🇫", multiline: true) == "😀" + hex(0x200D) + hex(0x1F1EB))
        #expect(PermissionText.escape("😀\u{200D}🏽", multiline: true) == "😀" + hex(0x200D) + hex(0x1F3FD))
        #expect(PermissionText.escape("😀\u{200D}1", multiline: true) == "😀" + hex(0x200D) + "1")
        // The pictures that joiners and selectors really serve stay.
        for text in ["👨\u{200D}👩\u{200D}👧", "❤\u{FE0F}\u{200D}🔥", "🏳\u{200D}⚧\u{FE0F}", "🏴\u{200D}☠\u{FE0F}",
                     "🏃\u{200D}♀\u{FE0F}", "🐻\u{200D}❄\u{FE0F}", "👩\u{200D}⚖\u{FE0F}", "1\u{FE0F}\u{20E3}"] {
            #expect(PermissionText.escape(text, multiline: true) == text, "\(text.unicodeScalars.map(\.value))")
        }
    }

    @Test func aChainOfJoinersCoreTextDrawsAsMoreThanOnePictureIsWrittenOutWhole() {
        func hex(_ value: UInt32) -> String { String(format: "⟨U+%04X⟩", value) }
        let woman = "👩", joiner = "\u{200D}"
        func chain(_ people: Int) -> String { Array(repeating: woman, count: people).joined(separator: joiner) }
        func written(_ people: Int) -> String { Array(repeating: woman, count: people).joined(separator: hex(0x200D)) }
        // None of these is a sequence of the emoji standard: every joiner goes, not only the ones past four.
        for people in [2, 3, 5, 6] {
            #expect(PermissionText.escape(chain(people), multiline: true) == written(people), "\(people)")
        }
        let heart = "❤\u{FE0F}", tone = "👩🏽"
        #expect(PermissionText.escape([heart, heart, heart, heart, heart, heart].joined(separator: joiner), multiline: true)
                == [heart, heart, heart, heart, heart, heart].joined(separator: hex(0x200D)))
        #expect(PermissionText.escape([tone, tone, tone, tone, tone, tone].joined(separator: joiner), multiline: true)
                == [tone, tone, tone, tone, tone, tone].joined(separator: hex(0x200D)))
        // Sixty of them, each with its joiner after it: the joiners are all written out, and nothing is lost.
        let sixty = String(repeating: woman + joiner, count: 60)
        let shown = PermissionText.escape(sixty, multiline: true)
        #expect(shown == String(repeating: woman + hex(0x200D), count: 60))
        // A real sequence stays, beside the others.
        let family = "👨\u{200D}👩\u{200D}👧\u{200D}👦"
        #expect(PermissionText.escape(family + " " + chain(3) + " " + family, multiline: true) == family + " " + written(3) + " " + family)
        #expect(PermissionText.escape(family + chain(2), multiline: true) == family + written(2))
        // A real sequence with one more picture joined on is no longer one picture: all its joiners go.
        #expect(PermissionText.escape(family + joiner + woman, multiline: true) == "👨" + hex(0x200D) + "👩" + hex(0x200D) + "👧" + hex(0x200D) + "👦" + hex(0x200D) + woman)
    }

    @Test func lettersAndDigitsThatReadRightToLeftAreWrittenOutSoNoRunOfThemIsReordered() throws {
        func hex(_ values: UInt32...) -> String { values.map { String(format: "⟨U+%04X⟩", $0) }.joined() }
        let hebrewPath = try #require(parse("Bash", ["command": "rm -rf /home/אבג/דהו"])).prompt
        #expect(hebrewPath.detail == "rm -rf /home/" + hex(0x5D0, 0x5D1, 0x5D2) + "/" + hex(0x5D3, 0x5D4, 0x5D5))
        let arabicPath = try #require(parse("Bash", ["command": "ls /tmp/مرحبا/١٢٣/456"])).prompt
        #expect(arabicPath.detail == "ls /tmp/" + hex(0x645, 0x631, 0x62D, 0x628, 0x627) + "/" + hex(0x661, 0x662, 0x663) + "/456")
        // Every part that is drawn: the title, the folder, the other fields, a tool's own input.
        let named = try #require(parse("mcp__שרת__tool", ["ש": "ב"], cwd: "/Users/me/תיקייה")).prompt
        #expect(named.title == "mcp__" + hex(0x5E9, 0x5E8, 0x5EA) + "__tool" && named.folder == hex(0x5EA, 0x5D9, 0x5E7, 0x5D9, 0x5D9, 0x5D4))
        #expect(named.detail.contains(hex(0x5E9)) && named.detail.contains(hex(0x5D1)) && !named.detail.contains("ש"))
        let described = try #require(parse("Bash", ["command": "ls", "description": "רשימה", "timeout": 5])).prompt
        #expect(described.secondary.contains(hex(0x5E8, 0x5E9, 0x5D9, 0x5DE, 0x5D4)))
        // Hebrew points, Arabic marks and Syriac, N'Ko, Adlam and Arabic mathematical letters are right to left as well.
        for scalar in [0x05B0, 0x061C, 0x064B, 0x0710, 0x07CA, 0x0840, 0x08A0, 0xFB1D, 0xFB50, 0xFE70, 0x10800, 0x10D00, 0x1E900, 0x1EE00] as [UInt32] {
            #expect(PermissionText.escape("a\(Character(Unicode.Scalar(scalar)!))b", multiline: true) == "a" + hex(scalar) + "b", "U+\(String(scalar, radix: 16))")
        }
        // The digits of the Latin script and the signs between them are not.
        #expect(PermissionText.escape("echo 456 ; 1.5, (x) -- é", multiline: true) == "echo 456 ; 1.5, (x) -- é")
    }

    /// The system's ICU, which knows every scalar's bidi class, asked about all of them.
    @Test(.tags(.exhaustive)) func exhaustiveEveryScalarOfBidiClassRightToLeftOrArabicNumberIsWrittenOut() throws {
        typealias CharDirection = @convention(c) (Int32) -> Int32
        let library = try #require(dlopen("/usr/lib/libicucore.dylib", RTLD_NOW))
        let direction = unsafeBitCast(try #require(dlsym(library, "u_charDirection")), to: CharDirection.self)
        // R, AN and AL.
        let strong: Set<Int32> = [1, 5, 13]
        var checked = 0
        for value in UInt32(0)...0x10FFFF {
            guard let scalar = Unicode.Scalar(value), strong.contains(direction(Int32(value))) else { continue }
            let text = "a" + String(Character(scalar)) + "b"
            #expect(PermissionText.escape(text, multiline: true) != text, "U+\(String(value, radix: 16, uppercase: true))")
            checked += 1
        }
        #expect(checked > 1_000)
        // The letters of Latin, CJK and Hangul text are not touched by it, besides the ones that read as ASCII, which are written out beside the
        // ASCII letters here, and the two ideographs that are drawn as a stroke (the checker doesn't know them). The letters of Greek and Cyrillic are
        // all written out beside them, whatever they look like.
        let lookalike = try asciiLookalikes()
        for value in Array(0x3B1...0x3C9) + Array(0x410...0x44F) {
            guard let scalar = Unicode.Scalar(UInt32(value)), scalar.properties.isAlphabetic, direction(Int32(value)) == 0 else { continue }
            #expect(PermissionText.escape("a" + String(Character(scalar)) + "b", multiline: true) == "a" + String(format: "⟨U+%04X⟩", value) + "b", "U+\(String(value, radix: 16, uppercase: true))")
        }
        for range in [0x41...0x7A, 0xC0...0xFF, 0x4E00...0x4FFF, 0xAC00...0xACFF] {
            for value in range {
                guard let scalar = Unicode.Scalar(UInt32(value)), scalar.properties.isAlphabetic, direction(Int32(value)) == 0,
                      lookalike(scalar) == nil, ![0x4E00, 0x4E28].contains(value) else { continue }
                let text = "a" + String(Character(scalar)) + "b"
                #expect(PermissionText.escape(text, multiline: true) == text.precomposedStringWithCanonicalMapping, "U+\(String(value, radix: 16, uppercase: true))")
            }
        }
    }

    @Test func aRuleWithRightToLeftTextIsNotOfferedAsAlwaysAllow() throws {
        func offered(_ content: String) throws -> PermissionPrompt.Parsed {
            try #require(parse("Bash", ["command": "ls"], suggestions: [addRules([["toolName": "Bash", "ruleContent": content]])]))
        }
        for content in ["echo א 1 ; ב 2", "ls /tmp/مرحبا", "echo ١٢٣", "ls:*" + "\u{05B0}"] {
            let parsed = try offered(content)
            #expect(parsed.prompt.grant == nil && parsed.suggestion == nil, "\(content)")
        }
        // Nor one the card would show as something else: normalization turns the Kelvin sign into K, the Greek question mark into ;.
        for content in ["echo \u{212A}", "echo a\u{37E} rm", "echo \u{1FEF}x\u{1FEF}", "ls /a/\u{1100}", "ls \u{1DD8}", "ls \u{FF76}\u{FF9E}"] {
            let parsed = try offered(content)
            #expect(parsed.prompt.grant == nil && parsed.suggestion == nil, "\(content)")
        }
        #expect(try offered("echo a 1 ; b 2").prompt.grant != nil)
        // Nothing past ASCII is offered, whatever its script.
        #expect(try offered("echo r\u{E9}sum\u{E9} \u{D55C}\u{AE00} \u{65E5}\u{672C}").prompt.grant == nil)
        let tool = try #require(parse("Bash", ["command": "ls"], suggestions: [addRules([["toolName": "mcp__אבג", "ruleContent": "x"]])]))
        #expect(tool.prompt.grant == nil && tool.suggestion == nil)
    }

    @Test func aRuleWithAScalarPastASCIIIsNotOfferedAsAlwaysAllow() throws {
        func offered(_ content: String) throws -> PermissionPrompt.Parsed {
            try #require(parse("Bash", ["command": "ls"], suggestions: [addRules([["toolName": "Bash", "ruleContent": content]])]))
        }
        for content in ["rm \u{2010}rf", "git push \u{2011}\u{2011}force", "g\u{456}t status", "/etc/pa\u{455}\u{455}wd", "ls \u{2212}la", "echo \u{FF41}\u{FF42}"] {
            let parsed = try offered(content)
            #expect(parsed.prompt.grant == nil && parsed.suggestion == nil, "\(content)")
        }
        let tool = try #require(parse("Bash", ["command": "ls"], suggestions: [addRules([["toolName": "mcp__s\u{435}rver", "ruleContent": "x"]])]))
        #expect(tool.prompt.grant == nil && tool.suggestion == nil)
        // Nor does the card show them as they are: the one before a letter is written out.
        let command = try #require(parse("Bash", ["command": "git push \u{2011}\u{2011}force"])).prompt
        #expect(command.detail == "git push \u{2011}⟨U+2011⟩force")
        // Nor one with a look-alike beside a punctuation mark of another script, or with a run that is all of them.
        for content in ["ls \u{3161}la", "echo a\u{3002}b", "rm \u{2014}rf", "echo \u{FF52}\u{FF4D}", "ls\u{3000}\u{3161}la", "echo \u{2795}"] {
            let parsed = try offered(content)
            #expect(parsed.prompt.grant == nil && parsed.suggestion == nil, "\(content)")
        }
        // Nor one that the card would show as it is: a host name made of look-alikes, one by itself, a word of its own language.
        for content in ["curl \u{430}\u{440}\u{440}\u{4CF}\u{435}\u{3002}\u{441}\u{43E}:*", "curl \u{430}\u{440}\u{440}\u{4CF}\u{435}.\u{441}\u{43E}\u{43C}:*", "echo ノート:*",
                        "echo \u{FF52}\u{FF4D}:*", "echo \u{2122}:*", "echo \u{2026}:*", "echo привет:*", "echo \u{3A9}\u{3BF}:*", "echo \u{4E00}:*"] {
            let parsed = try offered(content)
            #expect(parsed.prompt.grant == nil && parsed.suggestion == nil, "\(content)")
        }
        // ASCII is offered, and words of a language of their own are not: nothing past ASCII is certain to read as what it is.
        for content in ["npm test:*", "git status", "ls /Users/me/proj/*.txt:*"] {
            #expect(try offered(content).prompt.grant != nil, "\(content)")
        }
        for content in ["echo 안녕:*", "ls /Users/me/한글 日本語 中文:*", "cp /home/ひらがな/문서.txt .:*", "echo r\u{E9}sum\u{E9}:*", "echo \u{43C}\u{442}:*", "echo a\tb:*"] {
            let parsed = try offered(content)
            #expect(parsed.prompt.grant == nil && parsed.suggestion == nil, "\(content)")
        }
        // The same through grant(from:) itself, one rule among others and in the name of a tool.
        func suggestion(_ rules: [[String: Any]]) -> [String: Any] { ["type": "addRules", "behavior": "allow", "destination": "localSettings", "rules": rules] }
        let fine: [String: Any] = ["toolName": "Bash", "ruleContent": "npm test:*"]
        #expect(PermissionPrompt.grant(from: suggestion([fine])) != nil)
        #expect(PermissionPrompt.grant(from: suggestion([fine, ["toolName": "Bash", "ruleContent": "curl \u{430}\u{440}\u{440}\u{4CF}\u{435}\u{3002}\u{441}\u{43E}:*"]])) == nil)
        #expect(PermissionPrompt.grant(from: suggestion([["toolName": "Bash", "ruleContent": "echo ノート:*"], fine])) == nil)
        #expect(PermissionPrompt.grant(from: suggestion([["toolName": "mcp__ノート", "ruleContent": "x"]])) == nil)
        #expect(PermissionPrompt.grant(from: suggestion([["toolName": "mcp__\u{FF52}"]])) == nil)
        #expect(PermissionPrompt.grant(from: suggestion([["toolName": "mcp__한글", "ruleContent": "x"]])) == nil)
        #expect(PermissionPrompt.grant(from: suggestion([["toolName": "mcp__server", "ruleContent": "x"]])) != nil)
    }

    @Test func lettersThatSitOnTheCharacterBeforeThemAreWrittenOutLikeMarks() {
        let letters: [UInt32] = [0x0D4E, 0x0EB3, 0x0F88, 0x1843, 0x0F3E, 0x0F3F, 0x0F7F, 0x1A55]
        for value in letters {
            let letter = Character(Unicode.Scalar(value)!)
            #expect(PermissionText.escape("a\(letter)", multiline: false) == "a" + String(format: "⟨U+%04X⟩", value), "U+\(String(value, radix: 16, uppercase: true))")
            #expect(PermissionText.escape("ab\(letter)c", multiline: false) == "ab" + String(format: "⟨U+%04X⟩", value) + "c")
        }
        // As are the Arabic ones that did, which are letters that read right to left.
        for value in Array(0xFE70...0xFE7F) + Array(0xFC5E...0xFC63) + [0x0674] {
            #expect(PermissionText.escape("a\(Character(Unicode.Scalar(value)!))", multiline: false) == "a" + String(format: "⟨U+%04X⟩", value))
        }
    }

    @Test func everyLineIsBetweenAnIsolateAndItsEndAndTheTextsOwnIsolatesStayWrittenOut() throws {
        #expect(PermissionText.isolated("a\nb\n\nc") == "\u{2066}\u{2060}a\u{2069}\n\u{2066}\u{2060}b\u{2069}\n\u{2066}\u{2060}\u{2069}\n\u{2066}\u{2060}c\u{2069}")
        #expect(PermissionText.isolated("") == "")
        let prompt = try #require(parse("Bash", ["command": "x\u{2066}y\u{2069}z\n\u{2067}w"])).prompt
        #expect(prompt.detail == "x⟨U+2066⟩y⟨U+2069⟩z\n⟨U+2067⟩w")
        let drawn = PermissionText.isolated(prompt.detail)
        // The only isolates in what is drawn are the two around each line.
        #expect(drawn.unicodeScalars.filter { $0.value == 0x2066 }.count == 2 && drawn.unicodeScalars.filter { $0.value == 0x2069 }.count == 2)
        #expect(drawn.contains("x⟨U+2066⟩y⟨U+2069⟩z") && drawn.contains("⟨U+2067⟩w"))
    }

    @Test func aToolNameTooLongForTheTitleIsAlsoTheFirstLineOfTheScrollingText() throws {
        let long = "mcp__" + String(repeating: "serverpart_", count: 9) + "tool"
        #expect(long.count > 100)
        let prompt = try #require(parse(long, ["q": "x"])).prompt
        #expect(prompt.title == long && prompt.toolLine == "tool: " + long)
        #expect(prompt.scrollText.hasPrefix("tool: " + long + "\n{"))
        // It is escaped like the title.
        let odd = try #require(parse(long + "\u{202E}", [:])).prompt
        #expect(odd.toolLine == "tool: " + long + "⟨U+202E⟩")
        // A name that fits, and the fixed titles of the known tools, add nothing.
        for (tool, input) in [("mcp__github__create_issue", ["title": "x"]), ("Task", [:]), ("Bash", ["command": "ls"]), ("Edit", ["file_path": "/a"])] as [(String, [String: Any])] {
            let short = try #require(parse(tool, input)).prompt
            #expect(short.toolLine.isEmpty && !short.scrollText.contains("tool: "), "\(tool)")
        }
        // The folder shares the line with the name, so a name that would fit alone but not beside a long folder is written out too.
        let name = "mcp__github__create_issue"
        #expect(try #require(parse(name, [:])).prompt.toolLine.isEmpty)
        let beside = try #require(parse(name, [:], cwd: "/Users/me/" + String(repeating: "folder", count: 12))).prompt
        #expect(beside.toolLine == "tool: " + name)
    }

    // MARK: Combining marks

    /// Swift compares strings by canonical equivalence, so a composed and a decomposed text are equal; the scalars tell them apart.
    private func scalars(_ text: String) -> [UInt32] { text.unicodeScalars.map(\.value) }

    @Test func aKoreanPathMacOSStoredDecomposedReadsAsNormalHangul() throws {
        let decomposed = "/Users/me/\u{1112}\u{1161}\u{11AB}\u{1100}\u{1173}\u{11AF}/\u{110B}\u{1175}\u{1105}\u{1161}\u{11A8}\u{1109}\u{1165}.txt"
        let composed = "/Users/me/한글/이락서.txt"
        #expect(scalars(decomposed) != scalars(composed))
        #expect(scalars(PermissionText.escape(decomposed, multiline: false)) == scalars(composed))
        let prompt = try #require(parse("Read", ["file_path": decomposed])).prompt
        #expect(scalars(prompt.detail) == scalars(composed))
    }

    @Test func accentsOnLatinLettersComposeAndStayReadable() throws {
        let decomposed = "re\u{301}sume\u{301}-nau\u{308}ve.pdf"
        #expect(scalars(PermissionText.escape(decomposed, multiline: false)) == scalars("r\u{E9}sum\u{E9}-na\u{FC}ve.pdf"))
        #expect(scalars(try #require(parse("Read", ["file_path": "/a/" + decomposed])).prompt.detail) == scalars("/a/r\u{E9}sum\u{E9}-na\u{FC}ve.pdf"))
        // A letter that has no composed form keeps one mark, in the order normalization puts them; the other is written out.
        #expect(scalars(PermissionText.escape("x\u{301}\u{323}", multiline: false)) == scalars("x\u{323}⟨U+0301⟩"))
    }

    @Test func aCombiningMarkPastTheFirstOnOneLetterIsWrittenOut() {
        let escape = "⟨U+0301⟩"
        // "s" with the first acute composes to U+015B, which takes no mark: the 39 left are written out.
        let ls = PermissionText.escape("ls" + String(repeating: "\u{301}", count: 40), multiline: false)
        #expect(Array(scalars(ls).prefix(2)) == [0x6C, 0x15B])
        #expect(ls.components(separatedBy: escape).count - 1 == 39)
        #expect(ls.unicodeScalars.filter { $0.value == 0x301 }.count == 0)

        let x = PermissionText.escape("x" + String(repeating: "\u{323}", count: 40), multiline: false)
        #expect(x.components(separatedBy: "⟨U+0323⟩").count - 1 == 39 && x.unicodeScalars.filter { $0.value == 0x323 }.count == 1)
        // A mark after a line break or an escape has no letter to sit on, and nor has one before any letter.
        #expect(scalars(PermissionText.escape("x\u{323}\u{323}\n\u{323}", multiline: true)) == scalars("x\u{323}⟨U+0323⟩\n⟨U+0323⟩"))
        #expect(scalars(PermissionText.escape("\u{200B}\u{323}", multiline: true)) == scalars("⟨U+200B⟩⟨U+0323⟩"))
        // Enclosing marks are marks of another block: written out.
        #expect(scalars(PermissionText.escape("x\u{20D2}\u{20D3}", multiline: false)) == scalars("x⟨U+20D2⟩⟨U+20D3⟩"))
        // One mark on each of two letters is kept.
        #expect(scalars(PermissionText.escape("x\u{323}c\u{330}", multiline: false)) == [0x78, 0x323, 0x63, 0x330])
        #expect(scalars(PermissionText.escape("x\u{323}c\u{330}\u{330}", multiline: false)) == scalars("x\u{323}c\u{330}⟨U+0330⟩"))
    }

    @Test func theLimitCountsScalarsNotCharacters() {
        // A letter with a mark is one character and two scalars.
        func command(letters: Int, plain: Int) -> String { String(repeating: "x\u{323}", count: letters) + String(repeating: "b", count: plain) }
        // The shown mark raises the chip, which counts against the limit with the detail.
        let chip = "Unusual characters".unicodeScalars.count, limit = PermissionPrompt.detailLimit - chip
        let exact = "echo " + command(letters: 100, plain: limit - 205)
        #expect(exact.unicodeScalars.count == limit && exact.count == limit - 100)
        #expect(parse("Bash", ["command": exact])?.prompt.flags.last?.text == "Unusual characters")
        let over = "echo " + command(letters: 100, plain: limit - 204)
        #expect(over.unicodeScalars.count == limit + 1 && over.count < limit)
        #expect(parse("Bash", ["command": over]) == nil)
        // A second mark is written out, eight scalars, and counts as such.
        let escaped = "x\u{323}\u{323}" + String(repeating: "b", count: PermissionPrompt.detailLimit - 3)
        #expect(escaped.unicodeScalars.count == PermissionPrompt.detailLimit && parse("Bash", ["command": escaped]) == nil)
    }

    @Test func everyEscapeInACommandReachesTheDetail() throws {
        let prompt = try #require(parse("Bash", ["command": "git status\u{202E}\u{2066}; rm -rf /\u{FEFF}"])).prompt
        #expect(prompt.detail == "git status⟨U+202E⟩⟨U+2066⟩; rm -rf /⟨U+FEFF⟩")
        let path = try #require(parse("Edit", ["file_path": "/a/\u{200B}.ssh/config"])).prompt
        #expect(path.detail == "/a/⟨U+200B⟩.ssh/config")
        let folder = try #require(parse("Bash", ["command": "ls"], cwd: "/x/pro\u{202E}j")).prompt.folder
        #expect(folder == "pro⟨U+202E⟩j")
    }

    // MARK: Long commands

    @Test func aLongCommandIsKeptWholeWithItsEnd() throws {
        let command = (1...400).map { "step \($0) of the build" }.joined(separator: "\n") + "\nrm -rf ~/the-end"
        #expect(command.count < PermissionPrompt.detailLimit)
        let prompt = try #require(parse("Bash", ["command": command])).prompt
        #expect(prompt.detail == command)
        #expect(prompt.detail.hasSuffix("the-end"))
    }

    @Test func whatIsTooLongToShowInFullIsLeftToTheTerminalNotCut() {
        #expect(parse("Bash", ["command": String(repeating: "a", count: PermissionPrompt.detailLimit)]) != nil)
        #expect(parse("Bash", ["command": String(repeating: "a", count: PermissionPrompt.detailLimit + 1)]) == nil)
        // The escapes count: each of these takes eight characters on the card.
        #expect(parse("Bash", ["command": String(repeating: "\u{200B}", count: PermissionPrompt.detailLimit / 8 + 1)]) == nil)
        #expect(parse("Write", ["file_path": String(repeating: "/a", count: PermissionPrompt.detailLimit)]) == nil)
    }

    // MARK: What "Always allow" would add

    @Test func aModeChangeIsNeverTheRuleOffered() throws {
        let deny: [String: Any] = ["type": "addRules", "behavior": "deny", "rules": [["toolName": "Bash"]]]
        let empty: [String: Any] = ["type": "addRules", "behavior": "allow", "rules": []]
        let only = try #require(parse("Bash", ["command": "ls"], suggestions: [PermissionTestServer.setMode, deny, empty]))
        // None of those is offered; the rule of that one command is, as for a prompt with no suggestion.
        #expect(only.prompt.grant?.rules == ["Bash(ls)"])
        #expect(only.suggestion?["type"] as? String == "addRules" && only.suggestion?["behavior"] as? String == "allow")
        let other = try #require(parse("Bash", ["command": "ls *"], suggestions: [PermissionTestServer.setMode, deny, empty]))
        #expect(other.prompt.grant == nil && other.suggestion == nil)

        let both = try #require(parse("Bash", ["command": "ls"], suggestions: [PermissionTestServer.setMode, PermissionTestServer.addRules]))
        #expect(both.prompt.grant?.rules == ["Bash(npm run *)"])
        #expect(both.suggestion?["type"] as? String == "addRules")
    }

    @Test func everyRuleOfTheSuggestionIsShownAsClaudeCodeWritesItAndTheSuggestionIsEchoedAsItIs() throws {
        let rules: [[String: Any]] = [["toolName": "WebFetch"], ["toolName": "Read", "ruleContent": "/a/**"],
                                      ["toolName": "Bash", "ruleContent": "git status:*"]]
        let suggestion = addRules(rules, destination: "projectSettings")
        let parsed = try #require(parse("WebFetch", ["url": "https://x.y"], suggestions: [suggestion]))
        #expect(parsed.prompt.grant == PermissionPrompt.Grant(rules: ["WebFetch", "Read(/a/**)", "Bash(git status:*)"], place: .projectSettings))
        #expect(NSDictionary(dictionary: try #require(parsed.suggestion)).isEqual(to: suggestion))
    }

    @Test func theButtonSaysWhereTheRuleIsSaved() throws {
        let places: [(String, PermissionPrompt.Grant.Place, String)] = [
            ("localSettings", .localSettings, "in this project, just for you"),
            ("projectSettings", .projectSettings, "in this project"),
            ("userSettings", .userSettings, "everywhere"),
            ("session", .session, "for this session"),
        ]
        for (destination, place, phrase) in places {
            let rule = addRules([["toolName": "Bash", "ruleContent": "ls:*"]], destination: destination)
            let parsed = try #require(parse("Bash", ["command": "ls"], suggestions: [rule]))
            let grant = try #require(parsed.prompt.grant, "\(destination)")
            #expect(grant.place == place && grant.place.phrase == phrase, "\(destination)")
        }
    }

    @Test func aRuleThatCouldNotBeShownAsItIsIsNotOffered() throws {
        let fine: [String: Any] = ["toolName": "Bash", "ruleContent": "ls:*"]
        let cases: [(String, [String: Any])] = [
            ("four rules", addRules(Array(repeating: fine, count: 4))),
            ("a newline in a rule", addRules([["toolName": "Bash", "ruleContent": "ls\nrm -rf /"]])),
            ("a direction override", addRules([["toolName": "Bash", "ruleContent": "ls\u{202E}"]])),
            ("a tab", addRules([["toolName": "Bash", "ruleContent": "a\tb"]])),
            ("four words of 29 that wrap to four rows though 125 characters is three rows of a character count",
             addRules([["toolName": "Bash", "ruleContent": Array(repeating: String(repeating: "x", count: 29), count: 4).joined(separator: " ")]])),
            ("a rule too long for three rows", addRules([["toolName": "Bash", "ruleContent": String(repeating: "x", count: 200)]])),
            ("a rule that is not an object", addRules([fine, ["noName": 1]])),
            ("a rule that is a string", ["type": "addRules", "behavior": "allow", "destination": "session", "rules": ["Bash"]]),
            ("a rule without a tool", addRules([["ruleContent": "ls"]])),
            ("a tool name that is empty", addRules([["toolName": ""]])),
            ("a rule with a key nobody knows", addRules([["toolName": "Bash", "ruleContent": "ls", "extra": "x"]])),
            ("a rule content that is not text", addRules([["toolName": "Bash", "ruleContent": 5]])),
            ("a rule content that is empty", addRules([["toolName": "Bash", "ruleContent": ""]])),
            ("a suggestion with a key nobody knows", {
                var suggestion = addRules([fine]); suggestion["directories"] = ["/"]; return suggestion }()),
            ("no place", addRules([fine], destination: nil)),
            ("a place that is not known", addRules([fine], destination: "everyone")),
        ]
        for (name, suggestion) in cases {
            let parsed = try #require(parse("Bash", ["command": "ls"], suggestions: [suggestion]), Comment(rawValue: name))
            #expect(parsed.prompt.grant == nil, Comment(rawValue: name))
            #expect(parsed.suggestion == nil, Comment(rawValue: name))
        }
    }

    @Test func threeRulesAreTheMostOffered() throws {
        let rules = (1...3).map { ["toolName": "Bash", "ruleContent": "cmd\($0):*"] as [String: Any] }
        #expect(try #require(parse("Bash", ["command": "ls"], suggestions: [addRules(rules)])).prompt.grant?.rules.count == 3)
    }
}

@MainActor
struct PermissionBoardTests {
    private func prompt(_ detail: String, grant: PermissionPrompt.Grant? = nil) -> PermissionPrompt {
        PermissionPrompt(id: UUID(), title: "Run a command", symbol: "terminal", detail: detail, folder: "proj", grant: grant)
    }

    /// Time that moves only when a test says so.
    final class Clock {
        var now: TimeInterval = 1_000
    }

    @Test func promptsQueueOldestFirstAndEachIsAnsweredOnce() {
        let board = PermissionBoard()
        var answers: [(UUID, PermissionAnswer)] = []
        board.onAnswer = { answers.append(($0, $1)) }
        let first = prompt("one"), second = prompt("two")
        board.add(first)
        board.add(second)
        #expect(board.current == first && board.prompts.count == 2)
        board.answer(first, .allow)
        board.answer(first, .deny)
        #expect(board.current == second)
        #expect(answers.count == 1 && answers[0].0 == first.id && answers[0].1 == .allow)
    }

    @Test func aHookThatIsGoneTakesItsPromptAwayWithoutAnAnswer() {
        let board = PermissionBoard()
        var answers = 0
        board.onAnswer = { _, _ in answers += 1 }
        let first = prompt("one"), second = prompt("two")
        board.add(first)
        board.add(second)
        board.remove(first.id)
        #expect(board.prompts == [second])
        board.answer(first, .allow)
        #expect(answers == 0)
        board.clear()
        #expect(board.current == nil)
    }

    @Test func theClosedNotchGrowsForAPromptWhateverElseItShows() {
        let notch = CGSize(width: 200, height: 32), brow = CGSize(width: 44, height: 18)
        let live = HUDEvent.notice(symbol: "bolt", title: "Hi", detail: nil)
        for (base, hasNotch) in [(notch, true), (brow, false)] {
            let plain = NotchViewModel.collapsedSize(base: base, hasNotch: hasNotch, screenWidth: 1440, event: nil, showsLiveActivity: false,
                                                     liveSides: LiveEars.Sides(left: 38, right: 38), idleGrowth: nil, showsSneakPeek: false, inlinePeekWidth: 240)
            let asked = NotchViewModel.collapsedSize(base: base, hasNotch: hasNotch, screenWidth: 1440, event: live, showsLiveActivity: true,
                                                     liveSides: LiveEars.Sides(left: 38, right: 38), idleGrowth: 140, showsSneakPeek: true, inlinePeekWidth: 240,
                                                     approvalHeight: 90)
            #expect(asked.height == plain.height + 90)
            #expect(asked.width >= NotchViewModel.approvalWidth)
        }
    }

    // MARK: Accidental clicks

    private func board(_ clock: Clock) -> PermissionBoard {
        PermissionBoard(gate: PermissionClickGate(clock: { clock.now }))
    }

    @Test func aClickJustAfterACardAppearsDoesNotAnswerIt() {
        let clock = Clock(), board = board(clock)
        var answers: [PermissionAnswer] = []
        board.onAnswer = { answers.append($1) }
        let first = prompt("one")
        board.add(first)
        #expect(!board.gate.isReady)
        board.gate.pressBegan()
        board.answerByClick(first, .allow)
        clock.now += PermissionClickGate.delay - 0.01
        board.gate.pressBegan()
        board.answerByClick(first, .allow)
        #expect(answers.isEmpty && board.current == first)

        clock.now += 0.02
        board.gate.pressBegan()
        clock.now += 0.1
        board.answerByClick(first, .allow)
        #expect(answers == [.allow] && board.current == nil)
    }

    @Test func aClickThatBeganBeforeTheDelayEndedDoesNotCountWhenItEndsAfter() {
        let clock = Clock(), board = board(clock)
        var answers = 0
        board.onAnswer = { _, _ in answers += 1 }
        let first = prompt("one")
        board.add(first)
        clock.now += 0.3
        board.gate.pressBegan()
        clock.now += 2
        board.gate.refresh()
        #expect(board.gate.isReady)
        board.answerByClick(first, .deny)
        #expect(answers == 0 && board.current == first)
    }

    @Test func theNextCardInTheQueueGetsTheDelayAgain() {
        let clock = Clock(), board = board(clock)
        var answers: [(UUID, PermissionAnswer)] = []
        board.onAnswer = { answers.append(($0, $1)) }
        let first = prompt("one"), second = prompt("two"), third = prompt("three")
        board.add(first)
        board.add(second)
        board.add(third)
        clock.now += 1
        board.gate.refresh()
        #expect(board.gate.isReady)
        board.answerByClick(first, .allow)
        // The first was answered; the second is in front now, and a click aimed at the first lands on it.
        #expect(answers.count == 1 && board.current == second && !board.gate.isReady)
        board.answerByClick(second, .allow)
        #expect(answers.count == 1 && board.current == second)

        clock.now += 1
        board.gate.refresh()
        board.gate.pressBegan()
        // The hook of the front card is gone, so the third takes its place under the same mouse button.
        board.remove(second.id)
        #expect(board.current == third && !board.gate.isReady)
        clock.now += 0.1
        board.answerByClick(third, .allow)
        clock.now += 1
        board.answerByClick(third, .allow)
        #expect(answers.count == 1 && board.current == third, "a press that began on the card before is not a click on this one")

        board.gate.pressBegan()
        board.answerByClick(third, .allow)
        #expect(answers.count == 2 && board.current == nil)
    }

    @Test func aCardThatAppearsAgainGetsTheDelayAgain() {
        let clock = Clock(), gate = PermissionClickGate(clock: { clock.now })
        gate.arm()
        clock.now += 1
        #expect(gate.accepts() && gate.isReady)
        gate.arm()
        #expect(!gate.isReady && !gate.accepts())
    }

    @Test func theDelayIsAboutSevenTenthsOfASecond() {
        let clock = Clock(), gate = PermissionClickGate(clock: { clock.now })
        #expect(PermissionClickGate.delay == 0.7)
        #expect(!gate.accepts(), "never armed")
        gate.arm()
        clock.now += 0.699
        gate.refresh()
        #expect(!gate.isReady && !gate.accepts())
        clock.now += 0.002
        gate.refresh()
        #expect(gate.isReady && gate.accepts())
    }

    @Test func aPressBeforeTheCardChangedNeverCountsOnTheNewOne() {
        let clock = Clock(), gate = PermissionClickGate(clock: { clock.now })
        gate.arm()
        clock.now += 1
        gate.pressBegan()
        clock.now += 0.1
        gate.arm()
        clock.now += 5
        #expect(!gate.accepts())
        gate.pressBegan()
        #expect(gate.accepts())
    }

    @Test func aReleaseWithoutAPressIsAnActivationByAccessibilityAndCountsOnceTheDelayIsOver() {
        let clock = Clock(), gate = PermissionClickGate(clock: { clock.now })
        gate.arm()
        #expect(!gate.accepts())
        clock.now += 1
        #expect(gate.accepts())
    }

    @Test func theButtonsAreLiveOnceTheRealDelayHasPassed() async {
        let gate = PermissionClickGate()
        gate.arm()
        #expect(!gate.isReady)
        await eventually { gate.isReady }
        #expect(gate.isReady)
    }

    // MARK: Room

    @Test func aLongCommandShowsAFewRowsAndSaysThereIsMore() {
        func shown(_ detail: String, grant: PermissionPrompt.Grant? = nil) -> (rows: Int, hidden: Int) {
            let prompt = prompt(detail, grant: grant)
            let visible = PermissionLayout.visibleDetail(prompt, .card)
            return (PermissionLayout.rows(visible), PermissionLayout.hiddenRows(content: prompt.measure(.card).scroll, visible: visible))
        }
        #expect(shown("ls").rows == 1 && shown("ls").hidden == 0)
        #expect(shown("a\nb\nc").rows == 3 && shown("a\nb\nc").hidden == 0)
        let six = (1...6).map(String.init).joined(separator: "\n")
        #expect(shown(six).rows == 6 && shown(six).hidden == 0)
        let seven = (1...7).map(String.init).joined(separator: "\n")
        #expect(shown(seven).rows == 6 && shown(seven).hidden == 1)
        // One line that wraps counts for the rows it takes.
        let wide = String(repeating: "x", count: 50 * 7)
        #expect(shown(wide).rows == 6 && shown(wide).hidden > 0)
        let rule = PermissionPrompt.Grant(rules: ["Bash(a:*)", "Bash(b:*)", "Bash(c:*)"], place: .session)
        #expect(shown(six, grant: rule).rows == 3 && shown(six, grant: rule).hidden == 3)
    }

    @Test func noPromptTakesMoreRoomThanTheNotchHas() {
        let rules = [1, 2, 3].map { "Bash(\(String(repeating: "r", count: 40 * $0)):*)" }
        let grants: [PermissionPrompt.Grant?] = [nil, .init(rules: ["Bash(ls:*)"], place: .session),
                                                 .init(rules: Array(rules.prefix(1)), place: .userSettings),
                                                 .init(rules: ["a", "b", "c"], place: .projectSettings)]
        let details = ["", "ls", String(repeating: "line\n", count: 3) + "x", String(repeating: "line\n", count: 100),
                       String(repeating: "w", count: 20_000)]
        for grant in grants {
            for detail in details {
                let prompt = PermissionPrompt(id: UUID(), title: "Run a command", symbol: "terminal", detail: detail,
                                              flags: [.init(text: "Sandbox off", warns: true), .init(text: "Runs in the background", warns: false)],
                                              secondary: "description\ntimeout: 5", folder: "proj", grant: grant)
                // The closed card under the top row of a tall notch, and the open panel under the header, in the window's 280 points.
                #expect(PermissionCard.bodyHeight(for: prompt, hasNotch: true) + 40 <= 280, "\(grant?.rules.count ?? 0) rules, \(detail.count) characters")
                #expect(PermissionPanel.height(for: prompt) <= AppSettings.expandedHeightRange.upperBound - 56,
                        "\(grant?.rules.count ?? 0) rules, \(detail.count) characters")
            }
        }
    }

    @Test func theCardIsTallerForARuleAndForAnOpenTitleLine() {
        func height(grant: PermissionPrompt.Grant?, hasNotch: Bool) -> CGFloat {
            PermissionCard.bodyHeight(for: prompt("d", grant: grant), hasNotch: hasNotch)
        }
        let rule = PermissionPrompt.Grant(rules: ["Bash(ls)"], place: .session)
        #expect(height(grant: rule, hasNotch: true) > height(grant: nil, hasNotch: true))
        #expect(height(grant: nil, hasNotch: true) > height(grant: nil, hasNotch: false))
    }
}

struct PermissionSessionTests {
    @Test func aPromptKnowsTheSessionThatAsked() throws {
        let parsed = try #require(PermissionPrompt.parse(PermissionTestServer.hookInput()))
        #expect(parsed.prompt.session == "s-1")
    }

    @Test func aSessionIdThatIsNoPlainIdIsLeftOut() throws {
        for value in [42, "", String(repeating: "a", count: 200), "s 1\n"] as [Any] {
            var json = try #require(try JSONSerialization.jsonObject(with: PermissionTestServer.hookInput()) as? [String: Any])
            json["session_id"] = value
            let parsed = try #require(PermissionPrompt.parse(try JSONSerialization.data(withJSONObject: json)))
            #expect(parsed.prompt.session == nil, "\(value)")
        }
    }
}

struct ExactCommandRuleTests {
    private func grant(_ command: String, tool: String = "Bash", suggestions: [[String: Any]]? = nil) -> PermissionPrompt.Grant? {
        let input: [String: Any] = tool == "Bash" ? ["command": command] : ["file_path": "/Users/me/proj/a.swift", "old_string": "a", "new_string": "b"]
        return PermissionPrompt.parse(PermissionTestServer.hookInput(tool: tool, input: input, suggestions: suggestions))?.prompt.grant
    }

    @Test func aPlainCommandWithNoSuggestionCanBeAlwaysAllowedAsItIs() throws {
        let offered = try #require(grant("swift test --filter HeaderBar"))
        #expect(offered.rules == ["Bash(swift test --filter HeaderBar)"])
        #expect(offered.place == .localSettings)
    }

    @Test func claudeCodesOwnSuggestionStillWins() throws {
        let offered = try #require(grant("npm run build", suggestions: [PermissionTestServer.addRules]))
        #expect(offered.rules != ["Bash(npm run build)"])
    }

    @Test func anythingARuleWouldReadWiderOrNeverMatchIsNotOffered() {
        // A * is a wildcard in a rule; compound commands match part by part; substitutions, redirects and leading assignments
        // change what runs or keep the rule from matching.
        for command in ["rm -rf build/*", "ls *.txt", "make && make install", "a || b", "a; b", "cat x | wc -l", "sleep 1 &",
                        "echo $(whoami)", "echo `id`", "echo $HOME", "ls > out.txt", "sort < in.txt", "FOO=1 make", "(cd a; ls)",
                        "echo {a,b}", "ls ?.txt", "ls ~", "echo a\\ b", "echo hi # x", "", " ls", "ls ", "ls\nrm x", "echo é",
                        String(repeating: "a", count: 201)] {
            #expect(grant(command) == nil, Comment(rawValue: command))
        }
    }

    @Test func onlyBashGetsOne() {
        #expect(grant("", tool: "Edit") == nil)
    }

    @Test func alwaysAllowSendsThatOneRule() throws {
        let parsed = try #require(PermissionPrompt.parse(PermissionTestServer.hookInput(input: ["command": "swift build"])))
        let data = try #require(PermissionWire.decision(.always, suggestion: parsed.suggestion))
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains(#""ruleContent":"swift build""#))
        #expect(text.contains(#""destination":"localSettings""#))
        #expect(text.contains(#""behavior":"allow""#))
    }
}
