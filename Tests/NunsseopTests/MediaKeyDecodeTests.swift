import Testing
@testable import Nunsseop

struct MediaKeyDecodeTests {
    @Test(arguments: [
        (0x0000_0A00, 0, true), (0x0000_0B00, 0, false), (0x0007_0A01, 7, true), (0x0015_0A00, 21, true), (0x0015_0B00, 21, false),
    ])
    func readsKeyCodeAndState(data1: Int, code: Int, isDown: Bool) {
        let decoded = MediaKeyInterceptor.decode(data1: data1)
        #expect(decoded.code == code)
        #expect(decoded.isDown == isDown)
    }

    private func key(_ code: Int, volume: Bool = true, brightness: Bool = true, keyboard: Bool = true) -> MediaKey? {
        MediaKeyInterceptor.key(forCode: code, volume: { volume }, brightness: { brightness }, keyboard: { keyboard })
    }

    @Test func mapsCodesToKeys() {
        let expected: [(Int, MediaKey)] = [
            (0, .volumeUp), (1, .volumeDown), (7, .mute), (2, .brightnessUp), (3, .brightnessDown),
            (21, .keyboardUp), (22, .keyboardDown), (23, .keyboardToggle),
        ]
        for (code, media) in expected { #expect(key(code) == media, "code \(code)") }
        #expect(key(4) == nil)
    }

    @Test func leavesKeysToTheSystemWhenNotHandled() {
        for code in [0, 1, 7] { #expect(key(code, volume: false) == nil) }
        for code in [2, 3] { #expect(key(code, brightness: false) == nil) }
        for code in [21, 22, 23] { #expect(key(code, keyboard: false) == nil) }
        #expect(key(0, brightness: false, keyboard: false) == .volumeUp)
    }
}
