import AppKit
import CryptoKit
import Foundation
import os

/// How a prompt in the notch was answered.
enum PermissionAnswer: Equatable {
    case allow, deny, always
    /// The options chosen for each question of an `AskUserQuestion`: question index to option indexes.
    case answered([Int: [Int]])
    /// Let go of the hook with nothing said, so the terminal asks for itself.
    case terminal
}

/// The messages between Claude Code's PermissionRequest hook and the server. The key never travels: each side proves it
/// knows it with an HMAC-SHA256 keyed by the key, over a domain, the request's nonce and a SHA-256 of what is vouched for,
/// so neither a request nor an answer can be forged or moved to another request. The key is the permission key, a secret
/// of its own: the notify token, which every notice hook sends to whatever listens on the port, is not it and proves nothing here.
enum PermissionWire {
    static let requestDomain = "nunsseop-permission-request"
    static let responseDomain = "nunsseop-permission-response"

    /// 16 random bytes as lowercase hex.
    static func isNonce(_ value: String) -> Bool {
        value.utf8.count == 32 && value.utf8.allSatisfy { ($0 >= 48 && $0 <= 57) || ($0 >= 97 && $0 <= 102) }
    }

    static func mac(key: String, domain: String, nonce: String, payload: Data) -> String {
        let digest = SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
        let message = Data("\(domain)\n\(nonce)\n\(digest)".utf8)
        return HMAC<SHA256>.authenticationCode(for: message, using: SymmetricKey(data: Data(key.utf8)))
            .map { String(format: "%02x", $0) }.joined()
    }

    /// Sent as `X-Proof`, with the nonce as `X-Nonce`; the payload is the request body.
    static func requestProof(key: String, nonce: String, body: Data) -> String {
        mac(key: key, domain: requestDomain, nonce: nonce, payload: body)
    }

    /// The answer's body is this, a space, and the decision the hook prints.
    static func responseProof(key: String, nonce: String, decision: Data) -> String {
        mac(key: key, domain: responseDomain, nonce: nonce, payload: decision)
    }

    static let denyMessage = "Denied in Nunsseop"
    static let allowMessage = "Allowed in Nunsseop"

    /// What Claude Code reads from the hook's stdout. `always` echoes the one suggestion the prompt offered. `questionInput` is
    /// the `tool_input` of a question: it takes `answered` and nothing else, and an approval takes everything but `answered`.
    static func decision(_ answer: PermissionAnswer, suggestion: [String: Any]?, questionInput: [String: Any]? = nil,
                         openCode: Bool = false, dialect: PermissionDialect? = nil) -> Data? {
        if let dialect {
            let object: [String: Any]
            switch answer {
            case .allow: object = dialect.allowed
            case .deny: object = dialect.denied
            case .always, .answered, .terminal: return nil
            }
            return try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
        }
        // OpenCode's plugin reads only the behavior; "Always allow" isn't offered for it.
        if openCode {
            let behavior: String
            switch answer {
            case .allow: behavior = "allow"
            case .deny: behavior = "deny"
            case .always, .answered, .terminal: return nil
            }
            return try? JSONSerialization.data(withJSONObject: ["behavior": behavior], options: [.sortedKeys])
        }
        if let questionInput {
            guard case .answered(let picked) = answer else { return nil }
            return questionDecision(picked, input: questionInput)
        }
        var decision: [String: Any]
        switch answer {
        case .allow:
            decision = ["behavior": "allow"]
        case .deny:
            decision = ["behavior": "deny", "message": denyMessage]
        case .always:
            guard let suggestion else { return nil }
            decision = ["behavior": "allow", "updatedPermissions": [suggestion]]
        case .answered, .terminal:
            return nil
        }
        let output: [String: Any] = ["hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": decision]]
        return try? JSONSerialization.data(withJSONObject: output, options: [.sortedKeys, .withoutEscapingSlashes])
    }
}

/// What a prompt shows is what the tool would do, so nothing is dropped or joined, nothing invisible is left invisible, and
/// nothing is drawn that the card can't lay out inside its row. Only what is listed here is shown; every other scalar is
/// written out.
enum PermissionText {
    /// Shown as they are, besides ASCII and the space: Latin-1, Latin Extended-A, -B and Additional, Greek, Cyrillic, general
    /// punctuation (not the separators, the joiners or the marks of direction), currency, letterlike symbols, arrows, math
    /// operators, a few keys of Miscellaneous Technical, box drawing, geometric shapes, a few stars, dingbats, CJK signs, kana,
    /// Hangul compatibility letters, CJK ideographs, Hangul syllables, and full and half width forms. Only letters, numbers,
    /// punctuation and symbols of them count: no mark, no space, no unassigned scalar. Those that read as ASCII only where
    /// the run they stand in lets them.
    private static let shown: [ClosedRange<UInt32>] = [
        0xA1...0xFF, 0x100...0x24F, 0x1E00...0x1EFF, 0x370...0x3FF, 0x400...0x4FF, 0x2010...0x2027, 0x2030...0x205E,
        0x20A0...0x20C0, 0x2100...0x214F, 0x2190...0x21FF, 0x2200...0x22FF, 0x2303...0x2303, 0x2318...0x2318, 0x2325...0x2325,
        0x23CE...0x23CE, 0x2500...0x257F, 0x25A0...0x25FF, 0x2605...0x2606, 0x2700...0x27BF, 0x3001...0x303F, 0x3041...0x309F,
        0x30A0...0x30FF, 0x3131...0x318E, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xAC00...0xD7A3, 0xFF01...0xFF5E, 0xFF61...0xFF9D]
    /// Scalars of those ranges that are written out nonetheless: the soft hyphen, the Hangul filler, the arrow that stands
    /// for a tab, and what drew outside its row, or more than a point past either side of its cell by its outline or by the
    /// pixels it paints, or nothing, or a fallback box, when every scalar was laid out in the card's fonts: Latin and Greek
    /// letters whose accents or hooks reach past the row or more than a point past the cell, the box-drawing pieces that run
    /// past the row, the radicals and slashes that run wide, the signs no font has, and a few more.
    private static let withheld: [ClosedRange<UInt32>] = [
        0xAD...0xAD, 0x187...0x187, 0x193...0x193, 0x1D7...0x1D7, 0x1D9...0x1D9, 0x1DB...0x1DB, 0x1FA...0x1FA, 0x208...0x209, 0x37A...0x37A,
        0x390...0x390, 0x3D3...0x3D3, 0x47C...0x47C, 0x1E00...0x1E01, 0x1E14...0x1E14, 0x1E16...0x1E16, 0x1E2E...0x1E2E,
        0x1E4C...0x1E4C, 0x1E4E...0x1E4E, 0x1E50...0x1E50, 0x1E52...0x1E52, 0x1E66...0x1E66, 0x1E78...0x1E78, 0x1E7A...0x1E7A,
        0x1E9C...0x1E9D, 0x1EA4...0x1EA4, 0x1EA6...0x1EA6, 0x1EA8...0x1EA8, 0x1EAA...0x1EAA, 0x1EAE...0x1EAE, 0x1EB0...0x1EB0,
        0x1EB2...0x1EB2, 0x1EB4...0x1EB4, 0x1EBE...0x1EBE, 0x1EC0...0x1EC0, 0x1EC2...0x1EC2, 0x1EC4...0x1EC4, 0x1ED0...0x1ED0,
        0x1ED2...0x1ED2, 0x1ED4...0x1ED4, 0x1ED6...0x1ED6, 0x1EFE...0x1EFE, 0x2017...0x2017, 0x2038...0x2038, 0x2044...0x2044, 0x20C0...0x20C0,
        0x21E5...0x21E5, 0x2215...0x2215, 0x221A...0x221B, 0x2502...0x2503, 0x250C...0x2513, 0x251C...0x2533, 0x253C...0x254B,
        0x254E...0x254F, 0x2551...0x2557, 0x255E...0x2566, 0x256A...0x256E, 0x2577...0x2577, 0x257B...0x257B, 0x257D...0x257D,
        0x257F...0x257F, 0x2700...0x2700, 0x275F...0x2760, 0x3164...0x3164]
    /// The letters of ASCII that rise no higher than the middle of the row and sink no lower than its baseline: the only ones
    /// that may carry a combining mark, because a mark on a taller or deeper one reaches into the next row.
    private static let markBases = Set("acemnorsuvwxz".unicodeScalars.map(\.value))
    /// The combining marks that may be shown on those letters: the block of U+0300-036F, but not the grapheme joiner, which
    /// draws nothing, the double marks of U+035C-0362, which reach over the next letter, and the marks that normalization
    /// turns into others. Of these, `fittingMarks` keeps the ones the machine's fonts draw inside the row.
    private static let marks: ClosedRange<UInt32> = 0x300...0x36F
    private static let refusedMarks: Set<UInt32> = Set([0x34F] + Array(0x35C...0x362))

    /// The marks that fit above, below or beside every letter of `markBases` in every font the card uses, measured on this
    /// machine the first time a mark follows one of those letters (a few milliseconds, once; a static is initialised once and
    /// safely from any thread). The fonts, and so the marks that fit, differ from one macOS to the next, so no list of them is
    /// kept. A pair fits when CoreText draws it in a real glyph, with ink, inside the row and not more than a point past either
    /// side of its cell, by the outline or by the pixels it paints.
    private static let fittingMarks: Set<UInt32> = {
        let faces = [PermissionLayout.codeFont, PermissionLayout.titleFont, NSFont.systemFont(ofSize: 11)]
        let measure = MarkRaster()
        let letters = markBases.sorted().map { String(Unicode.Scalar($0)!) }
        return Set(marks.filter { value in
            guard !refusedMarks.contains(value), let mark = Unicode.Scalar(value),
                  String(mark).precomposedStringWithCanonicalMapping.unicodeScalars.elementsEqual(String(mark).unicodeScalars) else { return false }
            return letters.allSatisfy { letter in faces.allSatisfy { measure.fits(letter + String(mark), in: $0) } }
        })
    }()

    /// Draws a line into a bitmap, to read off the pixels what its outline may not tell.
    private final class MarkRaster {
        static let scale = 4, margin = 8, width = 96, height = 64
        /// Ink may pass the row's edge by a twentieth of a point, and the cell's sides by a point.
        static let slack: CGFloat = 0.05, sideways: CGFloat = 1.0
        private var pixels = [UInt8](repeating: 0, count: width * scale * height * scale * 4)
        private let context: CGContext

        init() {
            let (width, height, scale) = (Self.width, Self.height, Self.scale)
            context = pixels.withUnsafeMutableBytes {
                CGContext(data: $0.baseAddress, width: width * scale, height: height * scale, bitsPerComponent: 8, bytesPerRow: width * scale * 4,
                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            }
            context.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
        }

        /// Whether `text` lays out in a row of `font`: it has a width, no fallback glyph, ink; its ink, by its outline and by
        /// its pixels, is no more than a point past either side of the advance, and none passes above or below the row.
        func fits(_ text: String, in font: NSFont) -> Bool {
            let above = ceil(font.ascender), below = ceil(-font.descender) + ceil(font.leading)
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font]))
            let advance = CTLineGetTypographicBounds(line, nil, nil, nil)
            guard advance > 0, !drawsFallback(line) else { return false }
            let ink = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
            guard !ink.isNull, ink.width > 0, ink.height > 0, ink.minX >= -Self.sideways, ink.maxX <= advance + Self.sideways,
                  ink.maxY <= above + Self.slack, ink.minY >= -below - Self.slack else { return false }
            guard ink.minX < -Self.sideways / 2 || ink.maxX > advance + Self.sideways / 2 else { return true }
            guard let past = overshoot(line, advance: advance, below: below) else { return true }
            return past <= Self.sideways
        }

        /// The line is in the LastResort font, which draws a box, or has glyph 0, the one a font keeps for what it can't draw.
        private func drawsFallback(_ line: CTLine) -> Bool {
            for run in CTLineGetGlyphRuns(line) as? [CTRun] ?? [] {
                if let font = (CTRunGetAttributes(run) as NSDictionary)[kCTFontAttributeName],
                   (CTFontCopyPostScriptName(font as! CTFont) as String).hasPrefix("LastResort") { return true }
                var glyphs = [CGGlyph](repeating: 0, count: CTRunGetGlyphCount(run))
                CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
                if glyphs.contains(0) { return true }
            }
            return false
        }

        /// How many points the pixels (alpha of 48 or more) pass the advance on the side they pass it by most; nil when the line
        /// is too wide for the bitmap.
        private func overshoot(_ line: CTLine, advance: Double, below: CGFloat) -> CGFloat? {
            let (scale, margin) = (Self.scale, Self.margin)
            guard advance + Double(2 * margin) <= Double(Self.width) else { return nil }
            let used = Int(ceil(advance)) + 2 * margin
            context.clear(CGRect(x: 0, y: 0, width: used, height: Self.height))
            context.textPosition = CGPoint(x: Double(margin), y: Double(Self.height / 2) + below)
            CTLineDraw(line, context)
            let stride = Self.width * scale * 4, rows = Self.height * scale
            let leftEdge = margin * scale, rightEdge = Int(((Double(margin) + advance) * Double(scale)).rounded()), usedPixels = used * scale
            return pixels.withUnsafeBufferPointer { buffer in
                func inked(_ x: Int) -> Bool {
                    for y in 0..<rows where buffer[y * stride + x * 4 + 3] >= 48 { return true }
                    return false
                }
                var past = 0
                if let x = (0..<leftEdge).first(where: inked) { past = leftEdge - x }
                if let x = (rightEdge..<usedPixels).last(where: inked) { past = max(past, x + 1 - rightEdge) }
                return CGFloat(past) / CGFloat(scale)
            }
        }
    }
    /// The pictures: assigned emoji of the Mahjong tiles to Symbols and Pictographs Extended-A, and of Miscellaneous Symbols
    /// and Dingbats. Text symbols such as ©, ™ and ↔ are not among them, and nothing joins to those.
    private static let pictures: [ClosedRange<UInt32>] = [0x2600...0x27BF, 0x1F000...0x1FAFF]
    /// What ICU says about the scalars of `shown`, `pictures` and `marks`, worked out once, on first use. Nil when ICU can't be
    /// loaded: nothing past ASCII is shown then.
    private struct Confusables {
        /// Letters and digits that pass for ASCII ones in the middle of a word: every letter of Cyrillic and of Greek, the full
        /// width Latin letters, and the letters of Latin that ICU's spoof checker calls look-alikes (its skeleton, or the
        /// compatibility form, is ASCII), but not the ligatures whose form is two letters or more (`œ`, `æ`, `ĳ`). Of any other
        /// script or category as well, when its skeleton or compatibility form is one ASCII letter or digit (`ℓ`, `ℯ`, `ℝ`, `∣`,
        /// `∨`, `∪`, `⊤`, `╳`, `〇`), except `readAsText`. Not the full width digits, which `hideConfusables` judges by their run.
        let foreign: Set<UInt32>
        /// The letters and digits of Latin, Greek and Cyrillic past ASCII, and the full width ones.
        let letters: Set<UInt32>
        /// The one ASCII character of `-/\\.:@~|;&$<>=*?#` that a punctuation mark or symbol stands for: by the skeleton, by the
        /// compatibility form, or by `drawnLike`.
        let stands: [UInt32: UInt8]
        /// The pictures that can be read as a printable ASCII character (`➕`, `➖`, `✖`): ICU's skeleton of it, or its NFKC or NFKD
        /// form, holds one.
        let asciiPictures: Set<UInt32>
    }

    /// Scalars whose skeleton or compatibility form is an ASCII letter or digit and that are ordinary text nonetheless: the
    /// multiplication sign (written out only between two ASCII letters, `hideConfusables`) and the superscript digits of units and notes (`m²`, `cm³`, `¹`). Not the trademark and service mark
    /// signs, nor the infinity sign: their forms are two letters (`TM`, `SM`, `oo`).
    private static let readAsText: Set<UInt32> = [0xD7, 0xB2, 0xB3, 0xB9]

    private static func isFullWidthDigit(_ value: UInt32) -> Bool { (0xFF10...0xFF19).contains(value) }

    /// ICU's codes of the scripts that are judged.
    private static let latinScript: Int32 = 25, greekScript: Int32 = 14, cyrillicScript: Int32 = 8

    /// Scalars the checker misses that draw like ASCII punctuation: the Korean and CJK strokes and the prolonged sound mark
    /// like a hyphen or a vertical bar, the long dashes, and the ideographic full stops that IDNA maps to a period.
    private static let drawnLike: [UInt32: UInt8] = [
        0x3161: 0x2D, 0x4E00: 0x2D, 0x30FC: 0x2D, 0xFF70: 0x2D, 0x2014: 0x2D, 0x2015: 0x2D,
        0x3163: 0x7C, 0x4E28: 0x7C, 0x3021: 0x7C, 0x2758: 0x7C,
        0x3002: 0x2E, 0xFF61: 0x2E]

    private static let confusables: Confusables? = {
        typealias Open = @convention(c) (UnsafeMutablePointer<Int32>) -> OpaquePointer?
        typealias Close = @convention(c) (OpaquePointer?) -> Void
        typealias Skeleton = @convention(c) (OpaquePointer?, UInt32, UnsafePointer<UInt8>?, Int32, UnsafeMutablePointer<UInt8>?, Int32,
                                             UnsafeMutablePointer<Int32>) -> Int32
        typealias Script = @convention(c) (Int32, UnsafeMutablePointer<Int32>) -> Int32
        guard let library = dlopen("/usr/lib/libicucore.dylib", RTLD_NOW), let open = dlsym(library, "uspoof_open"),
              let close = dlsym(library, "uspoof_close"), let skeleton = dlsym(library, "uspoof_getSkeletonUTF8"),
              let script = dlsym(library, "uscript_getScript") else { return nil }
        var status: Int32 = 0
        guard let checker = unsafeBitCast(open, to: Open.self)(&status), status <= 0 else { return nil }
        defer { unsafeBitCast(close, to: Close.self)(checker) }
        let skeletonOf = unsafeBitCast(skeleton, to: Skeleton.self), scriptOf = unsafeBitCast(script, to: Script.self)
        let targets = Set("-/\\.:@~|;&$<>=*?#".unicodeScalars.map(\.value))
        func isASCII(_ bytes: [UInt8]) -> Bool { !bytes.isEmpty && bytes.allSatisfy { $0 < 0x80 } }
        func isASCIIAlnum(_ byte: UInt8) -> Bool { (0x30...0x39).contains(byte) || (0x41...0x5A).contains(byte) || (0x61...0x7A).contains(byte) }
        var foreign = Set<UInt32>(), letters = Set<UInt32>(), stands = [UInt32: UInt8](), asciiPictures = Set<UInt32>()
        var out = [UInt8](repeating: 0, count: 64)
        for value in (shown + pictures + [marks]).lazy.flatMap({ $0 }) where value >= 0x80 {
            guard let scalar = Unicode.Scalar(value) else { continue }
            let text = Array(String(scalar).utf8)
            status = 0
            let length = skeletonOf(checker, 0, text, Int32(text.count), &out, Int32(out.count), &status)
            let form = status > 0 ? [] : Array(out[0..<Int(length)])
            let compatible = Array(String(scalar).decomposedStringWithCompatibilityMapping.utf8)
            let composed = Array(String(scalar).precomposedStringWithCompatibilityMapping.utf8)
            if isPicture(scalar), [form, compatible, composed].contains(where: { $0.contains { (0x21...0x7E).contains($0) } }) { asciiPictures.insert(value) }
            switch scalar.properties.generalCategory {
            case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
                 .decimalNumber, .letterNumber, .otherNumber:
                var code: Int32 = 0
                let fullWidth = isFullWidthDigit(value) || (0xFF21...0xFF3A).contains(value) || (0xFF41...0xFF5A).contains(value)
                let script = fullWidth ? latinScript : scriptOf(Int32(value), &code)
                guard script == latinScript || script == greekScript || script == cyrillicScript else { break }
                letters.insert(value)
                if fullWidth || script != latinScript {
                    if !isFullWidthDigit(value) { foreign.insert(value) }
                } else {
                    // A look-alike by the checker's skeleton or the compatibility form; a ligature of two letters or more is not one.
                    let ascii = isASCII(form) ? form : compatible
                    let spelled = ascii.filter { ($0 | 0x20) >= 0x61 && ($0 | 0x20) <= 0x7A }.count
                    if status > 0 || (isASCII(ascii) && spelled < 2) { foreign.insert(value) }
                }
            default: break
            }
            // Of any script or category, when its form is one ASCII letter or digit: a letter of the letterlike block, a bar or a cup of
            // maths, a cross of box drawing, Han's zero. A form of two letters or more is a digraph, and is not one.
            if !foreign.contains(value), !isFullWidthDigit(value), !readAsText.contains(value), shown.contains(where: { $0.contains(value) }) {
                let ascii = isASCII(form) ? form : compatible
                if ascii.count == 1, isASCIIAlnum(ascii[0]) { foreign.insert(value) }
            }
            if foreign.contains(value) { continue }
            if let drawn = drawnLike[value] { stands[value] = drawn; continue }
            for candidate in [form, compatible] where candidate.count == 1 && candidate != text && targets.contains(UInt32(candidate[0])) {
                stands[value] = candidate[0]
                break
            }
        }
        return Confusables(foreign: foreign, letters: letters, stands: stands, asciiPictures: asciiPictures)
    }()

    /// Whether the zero-width joiners in a sequence of pictures draw it as one picture in the card's font, by sequence. Asked of
    /// CoreText once each; the cache stops growing at a few thousand.
    private static let sequences = OSAllocatedUnfairLock(initialState: [String: Bool]())
    /// Joiners one emoji may hold. A cluster is one unit that can't be broken across rows, so a longer chain could not wrap.
    static let maxJoiners = 4
    /// What a tab is shown as; `⇥` itself is written out, so this can't be faked.
    static let tab = "⇥ "

    /// A scalar whose own normalization form C is another is written out first, so normalizing can never turn what is shown
    /// into something else (the Kelvin sign into K, the Greek question mark into a semicolon, a compatibility ideograph
    /// into its unified one). The rest is put in form C, so a path macOS stored decomposed reads as it was typed.
    /// What is shown is ASCII, the space, and the scalars of `shown`; a tab is shown as `tab`, and a line break stays one
    /// when `multiline`. Anything else is written out as `⟨U+202E⟩`, and so are the angle brackets that mark one, so an
    /// escape can't be faked. Of what reads as ASCII, only the certain cases are written out (the rest is shown, and
    /// `hasUnusualCharacters` tells the card to say so):
    /// - A letter of `Confusables.foreign` in a letter run that holds an ASCII letter or digit; a full width digit in a run that holds
    ///   an ASCII letter. A letter run is the longest stretch of the input made of letters, digits and combining marks of any script,
    ///   the scalars of `Confusables.foreign` whatever they are, and the ASCII `. - _ / : @ \ ~ ' "`.
    /// - A hyphen-like scalar (`-`) right before an ASCII letter or digit, but not a stroke or a prolonged sound mark after a
    ///   letter of CJK text that is no such scalar itself (`ユーザーID`, `统一API`), nor the en dash between two digits (`10–20`);
    ///   a full stop, colon or at sign look-alike between two letters or digits of ASCII, Latin, Cyrillic or Greek; a slash,
    ///   backslash, bar or shell operator look-alike (`/ \ | ; & $ < > = * ? # ~`) beside an ASCII letter, digit or punctuation
    ///   mark, but not the full width tilde between two digits (`1～3日`); `×` between two ASCII letters (`e×ample`); `〈` right
    ///   before an ASCII letter or digit and `〉` right after one, which pass for the brackets of an escape.
    /// What emoji are made of stays: the emoji
    /// variation selector right after a picture that it changes (not one drawn in colour already), the text one, and one skin
    /// tone right after a picture that takes it, each only when CoreText draws the picture differently with it; the zero-width
    /// joiners of a sequence of pictures, up to `maxJoiners` in a row, that CoreText draws as one picture, and the colour
    /// selectors in it; regional indicators two by two; the keycap of a digit, `#` or `*`. A combining mark of `fittingMarks` stays
    /// when it is the only one on a letter of `markBases`. CR LF counts as one break. When ICU can't be loaded, or with
    /// `failClosed` (for a test), every scalar past ASCII is written out, those of emoji included.
    /// Constraint, accepted: the colour selector that stays inside a sequence drawn as one glyph changes nothing a reader sees, so
    /// two paths made of nothing but such emoji could differ by an invisible selector.
    static func escape(_ text: String, multiline: Bool, failClosed: Bool = false) -> String {
        let confusables = failClosed ? nil : Self.confusables
        var tokens: [Token] = []
        var run = String.UnicodeScalarView()
        func flush() {
            guard !run.isEmpty else { return }
            tokens.append(contentsOf: String(run).precomposedStringWithCanonicalMapping.unicodeScalars.map { Token(scalar: $0, changes: false) })
            run = String.UnicodeScalarView()
        }
        for scalar in text.unicodeScalars {
            if scalar.value < 0x300 || String(scalar).precomposedStringWithCanonicalMapping.unicodeScalars.elementsEqual([scalar]) {
                run.append(scalar)
            } else {
                flush()
                tokens.append(Token(scalar: scalar, changes: true))
            }
        }
        flush()
        if let confusables { hideConfusables(&tokens, confusables) }

        var result = String.UnicodeScalarView()
        // What was just shown, and what may follow it.
        var previous: Unicode.Scalar?
        var takesMark = false, takesTone = false, selected = false, keycap = false, pairOpen = false
        // The joiners in the picture being shown, nil when what was just shown isn't one; and whether its sequence draws as one.
        var joined: Int?, joins = false
        func reset() {
            previous = nil
            takesMark = false
            takesTone = false
            selected = false
            keycap = false
            pairOpen = false
            joined = nil
        }
        var index = 0
        while index < tokens.count {
            let (scalar, changes, hidden) = (tokens[index].scalar, tokens[index].changes, tokens[index].hidden)
            index += 1
            let next = index < tokens.count && !tokens[index].changes ? tokens[index].scalar : nil
            if scalar == "\r", next == "\n" { continue }
            if scalar == "\n" && multiline {
                result.append(scalar)
                reset()
            } else if scalar == "\t" {
                result.append(contentsOf: tab.unicodeScalars)
                reset()
            } else if changes || confusables == nil && scalar.value >= 0x80 {
                appendEscape(scalar, to: &result)
                reset()
            } else if scalar.value == 0xFE0E || scalar.value == 0xFE0F, let before = previous, !selected,
                      (isPicture(before) && (keeps(scalar, after: before) || (scalar.value == 0xFE0F && joins && joined != nil && !before.properties.isEmojiPresentation)))
                        || (scalar.value == 0xFE0F && next?.value == 0x20E3 && isKeycapBase(before)) {
                result.append(scalar)
                keycap = !isPicture(before)
                selected = true
                takesMark = false
                takesTone = false
            } else if scalar.value == 0x20E3, keycap, selected {
                result.append(scalar)
                reset()
                previous = scalar
            } else if scalar.value == 0x200D, joins, let count = joined, count < maxJoiners, let after = next, isPicture(after), !tokens[index].hidden {
                result.append(scalar)
                joined = count + 1
                previous = scalar
                takesMark = false
                takesTone = false
                selected = false
            } else if (0x1F3FB...0x1F3FF).contains(scalar.value), takesTone, let before = previous, keeps(scalar, after: before) {
                result.append(scalar)
                previous = scalar
                takesTone = false
                selected = false
            } else if isRegional(scalar), pairOpen || next.map(isRegional) == true {
                result.append(scalar)
                let opened = !pairOpen
                reset()
                previous = scalar
                pairOpen = opened
            } else if takesMark, marks.contains(scalar.value), fittingMarks.contains(scalar.value) {
                result.append(scalar)
                reset()
                previous = scalar
            } else if isPicture(scalar), !hidden {
                result.append(scalar)
                let afterJoiner = previous?.value == 0x200D
                let count = joined
                reset()
                previous = scalar
                joined = afterJoiner ? count : 0
                if !afterJoiner {
                    let candidate = chain(tokens, from: index - 1)
                    joins = candidate.joiners > 0 && drawsAsOne(candidate.text)
                }
                takesTone = scalar.properties.isEmojiModifierBase
            } else if isShown(scalar), !hidden {
                result.append(scalar)
                reset()
                previous = scalar
                takesMark = markBases.contains(scalar.value)
            } else {
                appendEscape(scalar, to: &result)
                reset()
            }
        }
        return String(result)
    }

    private static func isShown(_ scalar: Unicode.Scalar) -> Bool {
        if (0x20...0x7E).contains(scalar.value) { return true }
        guard shown.contains(where: { $0.contains(scalar.value) }), !withheld.contains(where: { $0.contains(scalar.value) }) else { return false }
        switch scalar.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
             .decimalNumber, .letterNumber, .otherNumber,
             .connectorPunctuation, .dashPunctuation, .openPunctuation, .closePunctuation, .initialPunctuation, .finalPunctuation,
             .otherPunctuation, .mathSymbol, .currencySymbol, .modifierSymbol, .otherSymbol: return true
        default: return false
        }
    }

    private static func isPicture(_ scalar: Unicode.Scalar) -> Bool {
        scalar.properties.isEmoji && !scalar.properties.isEmojiModifier && !isRegional(scalar)
            && pictures.contains { $0.contains(scalar.value) } && scalar.properties.generalCategory != .unassigned
            && !withheld.contains { $0.contains(scalar.value) }
    }

    /// Han's zero is a look-alike of `O` but not beside an ideograph, where it is the zero of a number written in Han (`二〇二四年`).
    private static func isLatinLike(_ scalar: Unicode.Scalar, before: Unicode.Scalar?, after: Unicode.Scalar?, _ confusables: Confusables) -> Bool {
        guard confusables.foreign.contains(scalar.value) else { return false }
        func isIdeograph(_ scalar: Unicode.Scalar?) -> Bool {
            guard let value = scalar?.value else { return false }
            return value == 0x3007 || (0x3400...0x4DBF).contains(value) || (0x4E00...0x9FFF).contains(value)
        }
        return scalar.value != 0x3007 || !(isIdeograph(before) || isIdeograph(after))
    }

    /// The letters of CJK text: kana, Hangul and ideographs, which no one reads as Latin ones. `hideConfusables` judges the strokes
    /// among them by these.
    private static let cjkLetters: [ClosedRange<UInt32>] = [
        0x3041...0x30FF, 0x3131...0x318E, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xAC00...0xD7A3, 0xFF66...0xFF9D]
    /// The controls that go with an emoji and that `escape` keeps only inside one: selectors, the joiner, tones, regional
    /// indicators and the keycap.
    private static let emojiControls: [ClosedRange<UInt32>] = [0xFE0E...0xFE0F, 0x200D...0x200D, 0x20E3...0x20E3, 0x1F3FB...0x1F3FF, 0x1F1E6...0x1F1FF]
    /// The letters of Korean, Japanese and Chinese text that read as themselves: Hangul syllables and compatibility letters (not
    /// `ㅡ ㅣ ㆍ` and not the filler), ideographs (not `一` and `丨`), kana letters (not the middle dot, the prolonged sound mark, the voiced sound marks
    /// or `゠`), half width katakana letters (not `ｰ` and `･`).
    private static func isCJKLetter(_ scalar: Unicode.Scalar?) -> Bool {
        guard let value = scalar?.value else { return false }
        switch value {
        case 0x3161, 0x3163, 0x3164, 0x318D, 0x4E00, 0x4E28: return false
        case 0xAC00...0xD7A3, 0x3131...0x318E, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0x3041...0x3096, 0x309D...0x309F, 0x30A1...0x30FA, 0x30FD...0x30FF,
             0xFF66...0xFF6F, 0xFF71...0xFF9D: return true
        default: return false
        }
    }

    /// Whether the card says "Unusual characters" about `shown`: it holds a scalar past ASCII that is not a letter of Korean, Japanese
    /// or Chinese text or an emoji. All punctuation, signs, symbols, digits and letters of other scripts and widths say so, because
    /// they can pass for ASCII and are not all written out. Neither a picture that can be read as ASCII (`➕`, `➖`) nor a dash-shaped
    /// letter (`ー 一 ㅡ ｰ`) is exempt, but for the dash-shaped one that is part of CJK text: before a letter of CJK text, a space, a line
    /// break, ASCII punctuation other than `-` or the end of the text, and after a letter of CJK text, or after the start of the text,
    /// a space, a line break or ASCII punctuation when a letter of CJK text follows it (`ユーザー`, `统一`, `echo 一个`, `fix(サーバー):`).
    /// An escape and the arrow of a tab are not shown, and no neighbour.
    static func hasUnusualCharacters(_ shown: String) -> Bool {
        // The scalars shown, in order; nil for a written-out scalar or the arrow of a tab.
        var items: [Unicode.Scalar?] = [], inEscape = false
        for scalar in shown.unicodeScalars {
            if scalar.value == 0x27E8 { inEscape = true; items.append(nil) } else if scalar.value == 0x27E9 { inEscape = false } else if inEscape { continue } else if scalar.value == 0x21E5 { items.append(nil) } else { items.append(scalar) }
        }
        for (at, item) in items.enumerated() {
            guard let scalar = item, scalar.value >= 0x80, !emojiControls.contains(where: { $0.contains(scalar.value) }) else { continue }
            if isCJKLetter(scalar) || (isPicture(scalar) && confusables?.asciiPictures.contains(scalar.value) != true) { continue }
            if [0x30FC, 0x4E00, 0x3161, 0xFF70].contains(scalar.value) {
                // The neighbours shown; a written-out scalar or a tab is `nil` among them, and neither a letter nor a space.
                let atStart = at == 0, atEnd = at + 1 == items.count
                let before = atStart ? nil : items[at - 1], after = atEnd ? nil : items[at + 1]
                // A space, a line break or ASCII punctuation makes a quiet edge of a word; `-` does not on the right.
                func isEdge(_ neighbour: Unicode.Scalar?, dash: Bool) -> Bool {
                    guard let mark = neighbour else { return false }
                    return [0x20, 0x0A, 0x0D].contains(mark.value) || (isASCIIPunctuation(mark) && (dash || mark.value != 0x2D))
                }
                let letterAfter = isCJKLetter(after)
                let quietAfter = letterAfter || atEnd || isEdge(after, dash: false)
                let quietBefore = isCJKLetter(before) || (letterAfter && (atStart || isEdge(before, dash: true)))
                if quietAfter && quietBefore { continue }
            }
            return true
        }
        return false
    }

    /// A scalar of the input, in form C unless its own form C is another, and whether it is written out for reading as ASCII.
    private struct Token {
        let scalar: Unicode.Scalar
        let changes: Bool
        var hidden = false
    }

    private static func isASCIILetterOrDigit(_ scalar: Unicode.Scalar?) -> Bool {
        guard let value = scalar?.value else { return false }
        return (0x30...0x39).contains(value) || (0x41...0x5A).contains(value) || (0x61...0x7A).contains(value)
    }

    private static func isASCIILetter(_ scalar: Unicode.Scalar?) -> Bool {
        guard let value = scalar?.value else { return false }
        return (0x41...0x5A).contains(value) || (0x61...0x7A).contains(value)
    }

    private static func isASCIIPunctuation(_ scalar: Unicode.Scalar?) -> Bool {
        guard let value = scalar?.value else { return false }
        return (0x21...0x2F).contains(value) || (0x3A...0x40).contains(value) || (0x5B...0x60).contains(value) || (0x7B...0x7E).contains(value)
    }

    /// Letters, digits and combining marks of any script, the look-alikes of letters whatever they are (a bar, a cup, a cross), and
    /// the ASCII marks that join them in a name or a path.
    private static func isLetterRun(_ token: Token, _ confusables: Confusables) -> Bool {
        guard !token.changes else { return false }
        let scalar = token.scalar
        if scalar.value < 0x80 { return isASCIILetterOrDigit(scalar) || ".-_/:@\\~'\"".unicodeScalars.contains(scalar) }
        if confusables.foreign.contains(scalar.value) { return true }
        switch scalar.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
             .decimalNumber, .letterNumber, .otherNumber, .nonspacingMark, .spacingMark, .enclosingMark: return true
        default: return false
        }
    }

    /// Marks the scalars that are written out for reading as ASCII; the rules are in `escape`.
    private static func hideConfusables(_ tokens: inout [Token], _ confusables: Confusables) {
        func scalar(_ at: Int) -> Unicode.Scalar? { tokens.indices.contains(at) && !tokens[at].changes ? tokens[at].scalar : nil }
        func isWordLetter(_ scalar: Unicode.Scalar?) -> Bool {
            isASCIILetterOrDigit(scalar) || scalar.map { confusables.letters.contains($0.value) } == true
        }
        var start = 0
        while start < tokens.count {
            guard isLetterRun(tokens[start], confusables) else { start += 1; continue }
            var end = start
            while end < tokens.count, isLetterRun(tokens[end], confusables) { end += 1 }
            // A full width digit is a look-alike only beside an ASCII letter: in `第１回` or `（１）` it is the text's own.
            let hasLetter = tokens[start..<end].contains { !$0.changes && isASCIILetter($0.scalar) }
            if tokens[start..<end].contains(where: { isASCIILetterOrDigit($0.scalar) }) {
                for at in start..<end {
                    if isFullWidthDigit(tokens[at].scalar.value) {
                        if hasLetter { tokens[at].hidden = true }
                    } else if isLatinLike(tokens[at].scalar, before: scalar(at - 1), after: scalar(at + 1), confusables) {
                        tokens[at].hidden = true
                    }
                }
            }
            start = end
        }
        for at in tokens.indices where !tokens[at].changes && tokens[at].scalar.value >= 0x80 {
            let (before, after) = (scalar(at - 1), scalar(at + 1))
            func isDigit(_ scalar: Unicode.Scalar?) -> Bool { scalar.map { (0x30...0x39).contains($0.value) } == true }
            switch tokens[at].scalar.value {
            case 0x3008: tokens[at].hidden = isASCIILetterOrDigit(after)
            case 0x3009: tokens[at].hidden = isASCIILetterOrDigit(before)
            case 0xD7: tokens[at].hidden = isASCIILetter(before) && isASCIILetter(after)
            case let value:
                guard let ascii = confusables.stands[value] else { continue }
                let range = isDigit(before) && isDigit(after)
                switch ascii {
                // A flag, or a dash drawn into a name: an ASCII letter or digit right after it. Not the stroke or the prolonged sound
                // mark inside CJK text (the letter before it is no dash itself), nor the en dash of a range.
                case 0x2D:
                    let inText = before.map { before in cjkLetters.contains { $0.contains(value) } && cjkLetters.contains { $0.contains(before.value) } && confusables.stands[before.value] != 0x2D } == true
                    tokens[at].hidden = isASCIILetterOrDigit(after) && !inText && !(value == 0x2013 && range)
                case 0x2E, 0x3A, 0x40: tokens[at].hidden = isWordLetter(before) && isWordLetter(after)
                default:
                    tokens[at].hidden = [before, after].contains { isASCIILetterOrDigit($0) || isASCIIPunctuation($0) } && !(value == 0xFF5E && range)
                }
            }
        }
    }

    /// Whether `control`, right after `picture`, stays: a selector or a skin tone that makes CoreText draw the picture
    /// differently in the card's font. The colour selector never stays after a picture that is in colour already, and a tone
    /// only after one that takes it.
    private static func keeps(_ control: Unicode.Scalar, after picture: Unicode.Scalar) -> Bool {
        switch control.value {
        case 0xFE0F: return !picture.properties.isEmojiPresentation && changesDrawing(picture, with: control)
        case 0xFE0E: return changesDrawing(picture, with: control)
        case 0x1F3FB...0x1F3FF: return picture.properties.isEmojiModifierBase && changesDrawing(picture, with: control)
        default: return false
        }
    }

    /// The pictures from `tokens[start]` that `escape` would join, with their selectors and tones, and how many joiners hold them.
    /// A colour selector is counted after any picture that isn't in colour already: it stays only if the whole is drawn as one.
    private static func chain(_ tokens: [Token], from start: Int) -> (text: String, joiners: Int) {
        var text = String.UnicodeScalarView(), joiners = 0, index = start
        func kept(_ at: Int, _ test: (Unicode.Scalar) -> Bool) -> Bool {
            at < tokens.count && !tokens[at].changes && !tokens[at].hidden && test(tokens[at].scalar)
        }
        while true {
            let picture = tokens[index].scalar
            text.append(picture)
            index += 1
            if kept(index, { ($0.value == 0xFE0E || $0.value == 0xFE0F) && (keeps($0, after: picture) || ($0.value == 0xFE0F && !picture.properties.isEmojiPresentation)) }) {
                text.append(tokens[index].scalar)
                index += 1
            } else if kept(index, { (0x1F3FB...0x1F3FF).contains($0.value) && keeps($0, after: picture) }) {
                text.append(tokens[index].scalar)
                index += 1
            }
            guard joiners < maxJoiners, kept(index, { $0.value == 0x200D }), kept(index + 1, isPicture) else { break }
            text.append("\u{200D}")
            joiners += 1
            index += 1
        }
        return (String(text), joiners)
    }

    /// What CoreText draws `text` as in the card's code font: the font and glyph of each one that takes room. A selector may
    /// leave a glyph of no width behind, which is not a drawing.
    private static func drawing(_ text: String) -> [String] {
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: PermissionLayout.codeFont]))
        var drawn: [String] = []
        for run in CTLineGetGlyphRuns(line) as? [CTRun] ?? [] {
            let count = CTRunGetGlyphCount(run)
            var glyphs = [CGGlyph](repeating: 0, count: count), advances = [CGSize](repeating: .zero, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
            CTRunGetAdvances(run, CFRange(location: 0, length: 0), &advances)
            let font = (CTRunGetAttributes(run) as NSDictionary)[kCTFontAttributeName].map { CTFontCopyPostScriptName($0 as! CTFont) as String } ?? ""
            for (glyph, advance) in zip(glyphs, advances) where advance.width > 0 { drawn.append("\(font):\(glyph)") }
        }
        return drawn
    }

    /// Whether `picture` is drawn differently with `control` after it, by pair. Asked of CoreText once each; the cache stops
    /// growing at a few thousand.
    private static let controls = OSAllocatedUnfairLock(initialState: [String: Bool]())

    private static func changesDrawing(_ picture: Unicode.Scalar, with control: Unicode.Scalar) -> Bool {
        let key = String(picture) + String(control)
        if let known = controls.withLock({ $0[key] }) { return known }
        let differs = drawing(String(picture)) != drawing(key)
        controls.withLock { if $0.count < 4_096 { $0[key] = differs } }
        return differs
    }

    /// Whether the card's font draws `sequence` as one glyph that exists.
    private static func drawsAsOne(_ sequence: String) -> Bool {
        if let known = sequences.withLock({ $0[sequence] }) { return known }
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: sequence, attributes: [.font: PermissionLayout.codeFont]))
        var glyph: CGGlyph = 0
        if let runs = CTLineGetGlyphRuns(line) as? [CTRun], runs.count == 1, CTRunGetGlyphCount(runs[0]) == 1 {
            CTRunGetGlyphs(runs[0], CFRange(location: 0, length: 1), &glyph)
        }
        let drawn = glyph != 0
        sequences.withLock { if $0.count < 4_096 { $0[sequence] = drawn } }
        return drawn
    }

    private static func isRegional(_ scalar: Unicode.Scalar) -> Bool { (0x1F1E6...0x1F1FF).contains(scalar.value) }

    private static func isKeycapBase(_ scalar: Unicode.Scalar) -> Bool {
        (0x30...0x39).contains(scalar.value) || scalar == "#" || scalar == "*"
    }

    /// Every line of `text` between U+2066 and U+2069, so letters that read right to left can't turn the line around or
    /// reorder the clauses around them. It is applied after `escape` has written out the isolates and overrides the text
    /// itself held, in drawing and in measuring alike. A word joiner follows the isolate: without it SwiftUI breaks a
    /// line of Hangul with no spaces right after the isolate, leaving its first row empty and a row taller than measured.
    static func isolated(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        return text.components(separatedBy: "\n").map { "\u{2066}\u{2060}\($0)\u{2069}" }.joined(separator: "\n")
    }

    private static func appendEscape(_ scalar: Unicode.Scalar, to result: inout String.UnicodeScalarView) {
        result.append(contentsOf: String(format: "⟨U+%04X⟩", scalar.value).unicodeScalars)
    }

    /// `text` cut to `limit` characters with a visible mark, for what is only context.
    static func clipped(_ text: String, limit: Int) -> String {
        text.count > limit ? String(text.prefix(limit - 1)) + "…" : text
    }
}

/// One tool call waiting for an answer, as the card shows it. Kept in memory only.
struct PermissionPrompt: Identifiable, Equatable {
    let id: UUID
    /// "Run a command", "Edit a file", or a tool's own name as Claude Code sends it.
    let title: String
    let symbol: String
    /// The command, path, address or input in full, escaped; line breaks are line breaks. For a file it is the path and
    /// what goes into the file.
    let detail: String
    /// The tool's whole name when the title is too long to show in full, so it can be read in the scrolling text; else empty.
    let toolLine: String
    /// Facts about the call that change what it does, such as a sandbox that is off; shown above `detail`.
    let flags: [Flag]
    /// Everything else the call carries, escaped, shown after `detail` in a quieter colour: a command's description and any
    /// other field as `key: value`.
    let secondary: String
    /// The folder the session runs in.
    let folder: String
    /// What "Always allow" would add; nil when it isn't offered.
    let grant: Grant?
    /// The asking tool's own session id, which finds the terminal it runs in on the agents board.
    var session: String?
    /// How tall what it shows is, at the narrowest closed card and at the narrowest open panel.
    let card: PermissionLayout.Measure
    let panel: PermissionLayout.Measure
    /// The questions of an `AskUserQuestion`, which the card shows in place of `detail` and the three buttons; nil for an approval.
    let asking: Asking?
    /// The call is Codex's, not Claude Code's: the card says so and offers "Answer in terminal", since Codex shows its own prompt
    /// only once the hook lets go.
    let isCodex: Bool
    /// The tool the card names before the title when the call isn't Claude Code's ("Codex", "OpenCode"); such a card offers
    /// "Answer in terminal" in place of "Always allow".
    let tag: String?

    struct Flag: Equatable {
        let text: String
        /// Drawn in the warning colour.
        let warns: Bool
    }

    init(id: UUID, title: String, symbol: String, detail: String, flags: [Flag] = [], secondary: String = "", folder: String,
         grant: Grant?, codex: Bool = false, tag: String? = nil) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.detail = detail
        self.flags = flags
        self.secondary = secondary
        self.folder = folder
        self.grant = grant
        asking = nil
        isCodex = codex
        self.tag = tag ?? (codex ? PermissionLayout.codexTag : nil)
        toolLine = PermissionLayout.titleFits(title, folder: folder, tag: self.tag) ? "" : "tool: \(title)"
        let text = PermissionText.isolated(Self.scrollText(toolLine: toolLine, flags: flags, detail: detail, secondary: secondary))
        card = PermissionLayout.measure(isolatedText: text, grant: grant, place: .card)
        panel = PermissionLayout.measure(isolatedText: text, grant: grant, place: .panel)
    }

    /// A question: titled "Question", with nothing of an approval to measure.
    init(id: UUID, asking: Asking, folder: String) {
        self.id = id
        title = String(localized: "Question")
        symbol = "questionmark.bubble"
        detail = ""
        toolLine = ""
        flags = []
        secondary = ""
        self.folder = folder
        grant = nil
        card = PermissionLayout.Measure(scroll: 0, rules: 0, caption: 0)
        panel = card
        self.asking = asking
        isCodex = false
        tag = nil
    }

    /// The scrolling text before its lines are isolated: the tool's name if needed, flags, detail and the rest, a line break between.
    var scrollText: String { Self.scrollText(toolLine: toolLine, flags: flags, detail: detail, secondary: secondary) }

    private static func scrollText(toolLine: String, flags: [Flag], detail: String, secondary: String) -> String {
        ([toolLine].filter { !$0.isEmpty } + flags.map(\.text) + [detail, secondary].filter { !$0.isEmpty }).joined(separator: "\n")
    }

    func measure(_ place: PermissionLayout.Place) -> PermissionLayout.Measure {
        place == .card ? card : panel
    }

    /// The one `addRules` suggestion, and only when everything it would add can be shown as it is.
    struct Grant: Equatable {
        enum Place: String {
            case localSettings, projectSettings, userSettings, session

            /// Completes "Always allow saves this …".
            var phrase: String {
                switch self {
                case .localSettings: String(localized: "in this project, just for you")
                case .projectSettings: String(localized: "in this project")
                case .userSettings: String(localized: "everywhere")
                case .session: String(localized: "for this session")
                }
            }
        }

        let rules: [String]
        let place: Place

        static let maxRules = 3
        /// Rows the rules may take on the card; a suggestion that needs more is not offered.
        static let maxRuleRows = 3

        var caption: String { String(localized: "Always allow saves this \(place.phrase)") }
    }

    /// What is too long to show in full is not taken: the terminal asks, and shows all of it. Counted in Unicode scalars.
    static let detailLimit = 20_000
    static let titleLimit = 120

    struct Parsed {
        var prompt: PermissionPrompt
        /// The `addRules` suggestion "Always allow" echoes back; nil unless the prompt offers it.
        let suggestion: [String: Any]?
        /// The `tool_input` of a question, which the answer is built from; nil for an approval.
        var questionInput: [String: Any]?
        /// The call is OpenCode's, whose plugin reads a smaller answer (see `PermissionWire.decision`).
        var openCode = false
        /// The call is Copilot's, Antigravity's or Cursor's, which read each their own answer.
        var dialect: PermissionDialect?
    }

    /// Plan approvals are answered in the terminal, and so is anything unreadable. A question is no approval: it comes as a
    /// PreToolUse (see `parseQuestion`), and as a PermissionRequest it stays in the terminal too.
    private static let terminalOnly: Set<String> = ["AskUserQuestion", "ExitPlanMode"]

    /// - tag: the program the call comes through, named on the card as Codex and OpenCode are; such a card has "Answer in terminal" or its
    ///   like in place of "Always allow".
    /// - dialect: the tool whose hook sent it, when it is none of Claude Code, Codex and OpenCode (see `PermissionDialect`).
    static func parse(_ body: Data, tag: String? = nil, dialect: PermissionDialect? = nil) -> Parsed? {
        guard var parsed = parseRequest(body, tag: tag, dialect: dialect) else { return nil }
        parsed.prompt.session = sessionID(body)
        return parsed
    }

    /// The hook's `session_id` (`sessionId` for some tools), when it is a plain id.
    static func sessionID(_ body: Data) -> String? {
        guard let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any],
              let id = (json["session_id"] ?? json["sessionId"]) as? String, (1...128).contains(id.count),
              id.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) || "-_.:".unicodeScalars.contains($0) }) else { return nil }
        return id
    }

    private static func parseRequest(_ body: Data, tag: String?, dialect: PermissionDialect?) -> Parsed? {
        // A key twice is read one way here and maybe the other by the tool that sent it; and two keys that differ only in how their
        // letters are composed are one key to Swift, which a dictionary bridged from Foundation's can't hold. Looked for before parsing.
        guard !StrictJSON.hasDuplicateKeys(body), var json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] else { return nil }
        if let dialect {
            guard let request = dialect.normalized(json) else { return nil }
            json = request
        } else if json["hook_event_name"] as? String == "PreToolUse" {
            return parseQuestion(json)
        }
        guard json["hook_event_name"] as? String == "PermissionRequest",
              let tool = json["tool_name"] as? String, !tool.isEmpty, !terminalOnly.contains(tool) else { return nil }
        let input = json["tool_input"] as? [String: Any] ?? [:]
        let codex = isCodex(json), openCode = isOpenCode(json)
        let described = openCode ? describeOpenCode(permission: tool, input: input) : describe(tool: tool, input: input, codex: codex)
        let detail = PermissionText.escape(described.detail, multiline: true)
        let note = PermissionText.escape(described.note, multiline: true)
        let rest = PermissionText.escape(described.secondary, multiline: true)
        let secondary = [note, rest].filter { !$0.isEmpty }.joined(separator: "\n")
        let shownTitle = PermissionText.escape(described.title, multiline: false)
        let folder = folderName(json)
        // Anything shown past ASCII that is no letter of CJK text or emoji is said, since it can pass for ASCII and is not all written
        // out. What is judged is what the call acts on: the tool's name when it is the title, the detail and the listing, but not the
        // folder, the Bash tool's description (Claude's own words, nothing runs it) or the titles of the card.
        var flags = described.flags
        if (described.namesTool ? [shownTitle, detail, rest] : [detail, rest]).contains(where: PermissionText.hasUnusualCharacters) {
            flags.append(Flag(text: String(localized: "Unusual characters"), warns: true))
        }
        let shown = detail.unicodeScalars.count + secondary.unicodeScalars.count + flags.reduce(0) { $0 + $1.text.unicodeScalars.count }
        guard shown <= detailLimit, shownTitle.unicodeScalars.count <= titleLimit else { return nil }
        // Codex takes neither updated permissions nor input from a hook, and OpenCode's plugin gets only allow or deny, so neither is
        // ever offered "Always allow".
        let suggestion = codex || openCode ? nil : addRulesSuggestion(in: json["permission_suggestions"])
        let grant = suggestion.flatMap(grant(from:))
        let prompt = PermissionPrompt(id: UUID(), title: shownTitle, symbol: described.symbol, detail: detail, flags: flags,
                                      secondary: secondary, folder: folder, grant: grant, codex: codex, tag: tag ?? dialect?.tag ?? (openCode ? "OpenCode" : nil))
        return Parsed(prompt: prompt, suggestion: grant == nil ? nil : suggestion, openCode: openCode, dialect: dialect)
    }

    /// Whether the body is OpenCode's plugin's (see `OpenCodePlugin`): it says so in `agent`, which no other tool's hook does.
    static func isOpenCode(_ json: [String: Any]) -> Bool { json["agent"] as? String == "opencode" }

    /// An OpenCode permission request: `tool_name` is its `permission` (`bash`, `edit`, `webfetch`, `external_directory`...) and
    /// `tool_input` holds the `patterns` it asks about, the `title` older versions give, and its `metadata` (an edit's `filepath`
    /// and `diff`, a fetch's `url`). The patterns are the detail; everything else is listed after them, as for any other tool.
    private static func describeOpenCode(permission: String, input: [String: Any]) -> Described {
        let patterns = (input["patterns"] as? [Any])?.compactMap { $0 as? String } ?? []
        var rest = input["metadata"] as? [String: Any] ?? [:]
        if let title = input["title"] as? String, !title.isEmpty { rest["title"] = title }
        let titles: [String: (String, String)] = [
            "bash": (String(localized: "Run a command"), "terminal"), "edit": (String(localized: "Edit a file"), "pencil"),
            "read": (String(localized: "Read a file"), "doc.text"), "webfetch": (String(localized: "Fetch a web page"), "globe"),
            "websearch": (String(localized: "Search the web"), "magnifyingglass"),
            "external_directory": (String(localized: "Use files outside the project"), "folder")]
        var described = Described(title: titles[permission]?.0 ?? permission, symbol: titles[permission]?.1 ?? "puzzlepiece.extension",
                                  detail: patterns.joined(separator: "\n"), namesTool: titles[permission] == nil)
        described.secondary = listing(rest).joined(separator: "\n")
        return described
    }

    /// Whether the hook input is Codex's: it names the turn, which Claude Code's never does.
    static func isCodex(_ json: [String: Any]) -> Bool {
        (json["turn_id"] as? String).map { !$0.isEmpty } ?? false
    }

    /// The folder the session runs in, as the card shows it.
    static func folderName(_ json: [String: Any]) -> String {
        PermissionText.clipped(PermissionText.escape(((json["cwd"] as? String).map { ($0 as NSString).lastPathComponent }) ?? "",
                                                     multiline: false), limit: 80)
    }

    private struct Described {
        var title: String
        var symbol: String
        var detail: String
        var flags: [Flag] = []
        /// The Bash tool's description, quieter than the rest and first of it.
        var note = ""
        var secondary = ""
        /// The title is the tool's own name, as Claude Code sends it.
        var namesTool = false
    }

    /// A known tool says what it does in plain words, shows the field that says what it acts on and the text it would put
    /// there, and lists every other field it was given; any other tool, or a known one whose field isn't the text it
    /// should be, shows its own name and its whole input.
    private static func describe(tool: String, input: [String: Any], codex: Bool) -> Described {
        func label(_ name: String) -> String {
            switch name {
            case "old_string": "old"
            case "new_string": "new"
            default: name
            }
        }
        func known(_ key: String, _ title: String, _ symbol: String, texts: [String] = [], flagged: Bool = false) -> Described? {
            guard let value = input[key] as? String, !value.isEmpty else { return nil }
            var rest = input
            rest[key] = nil
            var described = Described(title: title, symbol: symbol, detail: value)
            for name in texts {
                guard let text = rest[name] as? String else { continue }
                described.detail += "\n\(label(name)):\n\(text)"
                rest[name] = nil
            }
            if let edits = rest["edits"] as? [Any], !edits.isEmpty, edits.allSatisfy({ $0 is [String: Any] }) {
                for (index, edit) in edits.enumerated() {
                    var fields = edit as? [String: Any] ?? [:]
                    described.detail += "\nedit \(index + 1) of \(edits.count):"
                    for name in ["old_string", "new_string"] {
                        guard let text = fields[name] as? String else { continue }
                        described.detail += "\n\(label(name)):\n\(text)"
                        fields[name] = nil
                    }
                    if !fields.isEmpty { described.detail += "\n" + listing(fields).joined(separator: "\n") }
                }
                rest["edits"] = nil
            }
            if flagged {
                if let value = rest["dangerouslyDisableSandbox"], isTruthy(value) {
                    described.flags.append(Flag(text: String(localized: "Sandbox off"), warns: true))
                    // A real true is said by the flag; any other form is listed as it came as well.
                    if isTrue(value) { rest["dangerouslyDisableSandbox"] = nil }
                }
                if isTrue(rest["run_in_background"]) {
                    described.flags.append(Flag(text: String(localized: "Runs in the background"), warns: false))
                    rest["run_in_background"] = nil
                }
                if let note = rest["description"] as? String, !note.isEmpty {
                    described.note = "description: \(note)"
                    rest["description"] = nil
                }
            }
            described.secondary = listing(rest).joined(separator: "\n")
            return described
        }
        /// Codex's `apply_patch`: the files its headers name, then the patch itself.
        func patch() -> Described? {
            guard let text = input["command"] as? String, !text.isEmpty else { return nil }
            var rest = input
            rest["command"] = nil
            let files = text.components(separatedBy: "\n").compactMap { line -> String? in
                let line = line.hasSuffix("\r") ? String(line.dropLast()) : line
                let header = line.unicodeScalars.drop { patchPadding.contains($0) }
                for (prefix, word) in patchHeaders where header.starts(with: prefix.unicodeScalars) {
                    return word + String(String.UnicodeScalarView(header.dropFirst(prefix.unicodeScalars.count)))
                }
                return nil
            }
            var described = Described(title: String(localized: "Edit files"), symbol: "pencil",
                                      detail: files.isEmpty ? text : files.joined(separator: "\n") + "\npatch:\n" + text)
            if let note = rest["description"] as? String, !note.isEmpty {
                described.note = "description: \(note)"
                rest["description"] = nil
            }
            described.secondary = listing(rest).joined(separator: "\n")
            return described
        }
        let described: Described?
        if codex {
            described = tool == "Bash" ? known("command", String(localized: "Run a command"), "terminal", flagged: true)
                : tool == "apply_patch" ? patch() : nil
        } else {
            described = switch tool {
            case "Bash": known("command", String(localized: "Run a command"), "terminal", flagged: true)
            case "Edit", "MultiEdit": known("file_path", String(localized: "Edit a file"), "pencil", texts: ["old_string", "new_string"])
            case "Write": known("file_path", String(localized: "Write a file"), "doc.badge.plus", texts: ["content"])
            case "NotebookEdit": known("notebook_path", String(localized: "Edit a notebook"), "pencil", texts: ["new_source"])
            case "Read": known("file_path", String(localized: "Read a file"), "doc.text")
            case "WebFetch": known("url", String(localized: "Fetch a web page"), "globe")
            case "WebSearch": known("query", String(localized: "Search the web"), "magnifyingglass")
            default: nil
            }
        }
        if let described { return described }
        let json = (try? JSONSerialization.data(withJSONObject: input, options: [.sortedKeys, .withoutEscapingSlashes, .prettyPrinted]))
            .flatMap { String(data: $0, encoding: .utf8) } ?? ""
        return Described(title: tool, symbol: "puzzlepiece.extension", detail: input.isEmpty ? "" : json, namesTool: true)
    }

    /// The headers of an `apply_patch` that name a file, and the word each is listed with.
    private static let patchHeaders = [("*** Add File: ", "add "), ("*** Update File: ", "update "), ("*** Delete File: ", "delete "),
                                       ("*** Move to: ", "move to ")]

    /// What Codex trims off a patch line before it reads a header: Rust's `char::is_whitespace`.
    private static let patchPadding = CharacterSet(charactersIn: "\u{9}\u{A}\u{B}\u{C}\u{D}\u{20}\u{85}\u{A0}\u{1680}\u{2028}\u{2029}\u{202F}\u{205F}\u{3000}")
        .union(CharacterSet(charactersIn: "\u{2000}"..."\u{200A}"))

    /// A real JSON `true`.
    private static func isTrue(_ value: Any?) -> Bool {
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return false }
        return number.boolValue
    }

    /// Anything a tool may read as true: `true`, the string "true" in any case, a number that isn't zero.
    private static func isTruthy(_ value: Any) -> Bool {
        if isTrue(value) { return true }
        if let text = value as? String { return text.lowercased() == "true" }
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return false }
        return number.doubleValue != 0
    }

    /// Every field as `key: value`, in key order; text as it is, anything else as JSON.
    private static func listing(_ fields: [String: Any]) -> [String] {
        fields.keys.sorted().map { key in
            let value = fields[key] as Any
            if let text = value as? String { return "\(key): \(text)" }
            let json = (try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes, .fragmentsAllowed]))
                .flatMap { String(data: $0, encoding: .utf8) }
            return "\(key): \(json ?? "\(value)")"
        }
    }

    /// The first suggestion that adds allow rules; a mode change is never offered.
    static func addRulesSuggestion(in value: Any?) -> [String: Any]? {
        (value as? [Any])?.lazy.compactMap { $0 as? [String: Any] }.first { entry in
            entry["type"] as? String == "addRules" && entry["behavior"] as? String == "allow"
                && !((entry["rules"] as? [Any]) ?? []).isEmpty
        }
    }

    /// Every rule as Claude Code writes it, or nil when any part of the suggestion can't be shown as it is: a rule with a scalar
    /// that isn't printable ASCII, wherever it stands (what is saved is what was approved, and nothing past ASCII is certain to
    /// read as what it is), one that is missing or odd, a key nobody has seen, too many rules, rules that take more rows than
    /// the card has for them, or a place that isn't known.
    static func grant(from suggestion: [String: Any]) -> Grant? {
        guard Set(suggestion.keys).isSubset(of: ["type", "behavior", "rules", "destination"]),
              let place = (suggestion["destination"] as? String).flatMap(Grant.Place.init(rawValue:)),
              let entries = suggestion["rules"] as? [Any], (1...Grant.maxRules).contains(entries.count) else { return nil }
        var rules: [String] = []
        for entry in entries {
            guard let rule = entry as? [String: Any], Set(rule.keys).isSubset(of: ["toolName", "ruleContent"]),
                  let tool = rule["toolName"] as? String, !tool.isEmpty else { return nil }
            var text = tool
            if let content = rule["ruleContent"] {
                guard let content = content as? String, !content.isEmpty else { return nil }
                text += "(\(content))"
            }
            guard text.unicodeScalars.allSatisfy({ (0x20...0x7E).contains($0.value) }) else { return nil }
            rules.append(text)
        }
        let grant = Grant(rules: rules, place: place)
        guard PermissionLayout.offers(grant, place: .card) else { return nil }
        return grant
    }

    #if DEBUG
    /// `--demo-permission` shows this.
    static var demo: PermissionPrompt {
        PermissionPrompt(id: UUID(), title: String(localized: "Run a command"), symbol: "terminal",
                         detail: "npm run build && npm test -- --coverage", folder: "nunsseop-web",
                         grant: Grant(rules: ["Bash(npm run *)"], place: .localSettings))
    }

    /// `--demo-codex-permission` shows this.
    static var demoCodex: PermissionPrompt {
        let body = try! JSONSerialization.data(withJSONObject: [
            "hook_event_name": "PermissionRequest", "turn_id": "demo", "tool_name": "Bash", "cwd": "/Users/me/nunsseop-web",
            "tool_input": ["command": "touch /Users/me/nunsseop-web/notes.txt", "description": "May I create notes.txt as requested?"]])
        return parse(body)!.prompt
    }

    /// `--demo-question` shows this: two questions, the second one with several answers.
    static var demoQuestion: PermissionPrompt {
        let input: [String: Any] = ["questions": [
            ["question": "Which database should the new service use?", "header": "Database", "multiSelect": false,
             "options": [["label": "PostgreSQL", "description": "Relational, what the other services already run on"],
                         ["label": "SQLite", "description": "A single file, nothing to operate"],
                         ["label": "DynamoDB", "description": "Managed key-value store"]]],
            ["question": "Which checks should run before every deploy?", "header": "Checks", "multiSelect": true,
             "options": [["label": "Unit tests", "description": "About 40 seconds"],
                         ["label": "Type check", "description": "About 15 seconds"],
                         ["label": "Lint", "description": ""],
                         ["label": "End-to-end tests", "description": "Slow: around 6 minutes"]]],
        ]]
        let body = try! JSONSerialization.data(withJSONObject: ["hook_event_name": "PreToolUse", "tool_name": "AskUserQuestion",
                                                                  "cwd": "/Users/me/nunsseop-web", "tool_input": input])
        return parse(body)!.prompt
    }
    #endif
}

/// Keeps a click from answering a prompt it was not meant for: a card that has just appeared, or just changed, may be
/// under a click aimed at something else. Buttons ignore clicks for `delay` after that, and a click whose mouse-down
/// came before the end of it doesn't count either, however late its mouse-up is.
@MainActor
final class PermissionClickGate: ObservableObject {
    static let delay: TimeInterval = 0.7

    /// Whether the buttons are live; they look dimmed until then.
    @Published private(set) var isReady = false
    private let clock: () -> TimeInterval
    private var readyAt = TimeInterval.infinity
    private var pressedAt: TimeInterval?
    private var wake: DispatchWorkItem?

    init(clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.clock = clock
    }

    /// The card appeared or its prompt changed.
    func arm() {
        readyAt = clock() + Self.delay
        isReady = false
        schedule(after: Self.delay)
    }

    /// The mouse went down on a button.
    func pressBegan() {
        pressedAt = clock()
    }

    /// The mouse came up. The click's own action runs first, so what it saw is dropped a moment later.
    func pressEnded() {
        let pressed = pressedAt
        DispatchQueue.main.async { [self] in
            if pressedAt == pressed { pressedAt = nil }
        }
    }

    /// Whether the click that just happened counts. A press and a release are two clocks apart in a test, so both are read.
    func accepts() -> Bool {
        refresh()
        guard isReady else { return false }
        if let pressedAt, pressedAt < readyAt { return false }
        return true
    }

    /// `isReady` from the clock.
    func refresh() {
        isReady = clock() >= readyAt
    }

    private func schedule(after seconds: TimeInterval) {
        wake?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.refresh()
                if !self.isReady { self.schedule(after: max(self.readyAt - self.clock(), 0.02)) }
            }
        }
        wake = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }
}

/// The prompts waiting for an answer, oldest first. A prompt leaves when it is answered or when its hook is gone
/// (the terminal answered first, Claude Code stopped it, or it timed out).
@MainActor
final class PermissionBoard: ObservableObject {
    @Published private(set) var prompts: [PermissionPrompt] = [] {
        didSet { if prompts.first != oldValue.first, prompts.first != nil { gate.arm() } }
    }
    /// Where the user is in each question prompt that waits.
    @Published private(set) var drafts: [UUID: QuestionDraft] = [:]
    let gate: PermissionClickGate
    /// Hands an answer to the server, which holds the hook's connection.
    var onAnswer: ((UUID, PermissionAnswer) -> Void)?

    init(gate: PermissionClickGate? = nil) {
        self.gate = gate ?? PermissionClickGate()
    }

    var current: PermissionPrompt? { prompts.first }

    func add(_ prompt: PermissionPrompt) {
        prompts.append(prompt)
    }

    /// An answer by a click on the card, which counts only when the gate lets it.
    func answerByClick(_ prompt: PermissionPrompt, _ answer: PermissionAnswer) {
        guard gate.accepts() else { return }
        self.answer(prompt, answer)
    }

    func answer(_ prompt: PermissionPrompt, _ answer: PermissionAnswer) {
        guard prompts.contains(where: { $0.id == prompt.id }) else { return }
        remove(prompt.id)
        onAnswer?(prompt.id, answer)
    }

    func draft(for prompt: PermissionPrompt) -> QuestionDraft { drafts[prompt.id] ?? QuestionDraft() }

    /// A click on the question card in front, which counts only when the gate lets it. Moving on to the next question closes the gate
    /// again, so a second click on the same spot can't answer it unseen; the last answer goes to the server.
    func act(_ prompt: PermissionPrompt, _ action: QuestionAction) {
        guard gate.accepts(), let asking = prompt.asking, current?.id == prompt.id else { return }
        var draft = draft(for: prompt)
        switch draft.apply(action, to: asking) {
        case .stay:
            drafts[prompt.id] = draft
        case .next:
            drafts[prompt.id] = draft
            gate.arm()
        case .finished(let picked):
            answer(prompt, .answered(picked))
        case .terminal:
            answer(prompt, .terminal)
        }
    }

    func remove(_ id: UUID) {
        prompts.removeAll { $0.id == id }
        drafts[id] = nil
    }

    func clear() {
        prompts = []
        drafts = [:]
    }
}
