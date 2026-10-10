import Foundation
import Testing
@testable import Nunsseop

struct CalculatorFormatTests {
    private let english = Locale(identifier: "en_US")
    private let german = Locale(identifier: "de_DE")

    @Test func displayFollowsTheLocale() {
        #expect(Calculator.format(1234.5, locale: english) == "1,234.5")
        #expect(Calculator.format(1234.5, locale: german) == "1.234,5")
        #expect(Calculator.format(0.1 + 0.2, locale: english) == "0.3")
        #expect(Calculator.format(-2, locale: english) == "-2")
    }

    @Test(arguments: [(1.5, "1.5"), (1234.5, "1234.5"), (0.1 + 0.2, "0.3"), (-2.25, "-2.25"), (1_000_000.125, "1000000.125")])
    func copiedResultHasNoGroupingAndADecimalPoint(value: Double, expected: String) {
        #expect(Calculator.copyString(value) == expected)
    }

    @Test func commasInTheInputAreThousandsSeparators() {
        #expect(Calculator.evaluate("3,5*2") == 70)
    }
}
