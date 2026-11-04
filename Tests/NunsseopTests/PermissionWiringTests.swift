import Combine
import Foundation
import Testing
@testable import Nunsseop

/// What `NotchViewModel` joins with `PermissionLink`: the server's held prompts, the board the notch shows, and the setting.
@MainActor
struct PermissionWiringTests {
    @MainActor private struct Rig {
        let server: PermissionTestServer
        let board = PermissionBoard()
        let setting = PassthroughSubject<Bool, Never>()
        let links: [AnyCancellable]

        init(enabled: @escaping @Sendable () -> Bool = { true },
             leavesToTerminal: @escaping @MainActor (PermissionPrompt) -> Bool = { _ in false }) async throws {
            server = try await PermissionTestServer()
            links = PermissionLink.connect(board: board, gate: server.server.permissions, isOn: setting.eraseToAnyPublisher(), enabled: enabled,
                                           leavesToTerminal: leavesToTerminal)
        }

        func ask(_ input: [String: Any] = ["command": "npm run build"]) throws -> RawClient {
            let client = try RawClient(port: server.port)
            client.send(server.request(body: PermissionTestServer.hookInput(input: input)))
            return client
        }
    }

    @Test func aPromptFromTheServerReachesTheBoard() async throws {
        let rig = try await Rig()
        let client = try rig.ask(["command": "make all"])
        await eventually { rig.board.prompts.count == 1 }
        #expect(rig.board.current?.detail == "make all")
        withExtendedLifetime(client) {}
    }

    @Test func aPromptLeftToTheTerminalShowsNoCardAndLetsTheHookGoAtOnce() async throws {
        var asked: [String?] = []
        let rig = try await Rig(leavesToTerminal: { asked.append($0.session); return true })
        let client = try rig.ask(["command": "make all"])
        // Nothing printed, as with "Answer in terminal": the terminal asks for itself.
        let text = String(decoding: await client.read(timeout: 10), as: UTF8.self)
        #expect(text.hasPrefix("HTTP/1.1 204"))
        #expect(rig.board.prompts.isEmpty)
        #expect(asked == ["s-1"])
    }

    @Test func turningTheSettingOffClearsThePromptsAndLetsTheirHooksGo() async throws {
        let rig = try await Rig()
        let clients = try [rig.ask(), rig.ask(["command": "ls"])]
        await eventually { rig.board.prompts.count == 2 }
        #expect(rig.board.prompts.count == 2)

        rig.setting.send(true)
        rig.setting.send(true)
        #expect(rig.board.prompts.count == 2, "only turning it off clears")

        rig.setting.send(false)
        #expect(rig.board.prompts.isEmpty)
        for client in clients { #expect(await client.closes(within: Int(eventDeadline)), "the hook is left waiting") }
    }

    @Test func aHookThatDisconnectsTakesItsCardOffTheBoard() async throws {
        let rig = try await Rig()
        let staying = try rig.ask(["command": "stays"])
        await eventually { rig.board.prompts.count == 1 }
        let leaving = try rig.ask(["command": "leaves"])
        await eventually { rig.board.prompts.count == 2 }
        leaving.close()
        await eventually { rig.board.prompts.count == 1 }
        #expect(rig.board.prompts.map(\.detail) == ["stays"])
        withExtendedLifetime(staying) {}
    }

    @Test func anAnswerGivenOnTheBoardReachesTheHook() async throws {
        let rig = try await Rig()
        let client = try rig.ask()
        await eventually { rig.board.prompts.count == 1 }
        let prompt = try #require(rig.board.current)
        rig.board.answer(prompt, .deny)
        #expect(rig.board.prompts.isEmpty)
        let text = String(decoding: await client.read(timeout: 10), as: UTF8.self)
        #expect(text.hasPrefix("HTTP/1.1 200 OK"))
        #expect(text.contains(#""behavior":"deny""#))
    }

    @Test func aServerWhoseSettingIsOffTakesNoPrompt() async throws {
        let rig = try await Rig(enabled: { false })
        let client = try rig.ask()
        #expect(await client.status() == "HTTP/1.1 404 Not Found")
        #expect(rig.board.prompts.isEmpty)
    }
}
