import SwiftUI

struct HUDContent: View {
    let event: HUDEvent
    let height: CGFloat
    let earWidth: CGFloat
    /// Room kept clear before the symbol, so both ears can sit right of the camera.
    var leadingInset: CGFloat = 0
    /// The symbol and the text line side by side, for a display without a camera to keep clear.
    var singleLine = false

    static let lineFont = NSFont.systemFont(ofSize: 11, weight: .medium)
    /// The symbol's slot in the single line; the widest symbol a notice uses (a battery) fits.
    static let lineSymbolWidth: CGFloat = 20
    static let lineGap: CGFloat = 7

    /// The text a notice or headphone battery shows under the notch.
    static func line(for event: HUDEvent) -> String? {
        switch event {
        case .notice(_, let title, let detail):
            return ([title] + (detail.map { [$0] } ?? [])).joined(separator: "  ·  ")
        case .headphones(let battery):
            return ([battery.name] + battery.levels.map { "\($0.label) \($0.percent)%" }).joined(separator: "  ·  ")
        default:
            return nil
        }
    }

    var body: some View {
        if singleLine, let line = Self.line(for: event) {
            HStack(spacing: Self.lineGap) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: Self.lineSymbolWidth)
                Text(line)
                    .font(Font(Self.lineFont))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
            }
            .frame(height: height)
        } else {
            stacked
        }
    }

    private var stacked: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: earWidth - 16, alignment: .leading)
                Spacer()
                trailing
                    .frame(width: earWidth - 16, alignment: .trailing)
            }
            .padding(.leading, leadingInset)
            .frame(height: height)
            if let line = Self.line(for: event) {
                Text(line)
                    .font(Font(Self.lineFont))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                    .frame(height: NotchViewModel.sneakPeekHeight, alignment: .top)
            }
        }
    }

    private var symbol: String {
        switch event {
        case .volume(let level, let muted):
            if muted || level == 0 { return "speaker.slash.fill" }
            return level < 0.34 ? "speaker.wave.1.fill" : level < 0.67 ? "speaker.wave.2.fill" : "speaker.wave.3.fill"
        case .brightness(let level):
            return level < 0.5 ? "sun.min.fill" : "sun.max.fill"
        case .keyboard(let level):
            return level == 0 ? "light.min" : "light.max"
        case .power(let state):
            return state.onAC ? "bolt.fill" : BatteryBadge.symbol(for: state.percent)
        case .headphones:
            return "headphones"
        case .notice(let symbol, _, _):
            return symbol
        }
    }

    @ViewBuilder private var trailing: some View {
        switch event {
        case .volume(let level, let muted):
            LevelBar(value: muted ? 0 : Double(level))
        case .brightness(let level), .keyboard(let level):
            LevelBar(value: Double(level))
        case .power(let state):
            Text("\(state.percent)%")
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(state.onAC ? .green : .white)
        case .notice:
            EmptyView()
        case .headphones(let battery):
            Text("\(battery.levels.map(\.percent).min() ?? 0)%")
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white)
        }
    }
}

private struct LevelBar: View {
    let value: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.2))
                Capsule().fill(.white).frame(width: proxy.size.width * min(1, max(0, value)))
            }
        }
        .frame(height: 5)
        .animation(.easeOut(duration: 0.12), value: value)
    }
}

struct BatteryBadge: View {
    let state: PowerState

    static func symbol(for percent: Int) -> String {
        switch percent {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    var body: some View {
        HStack(spacing: 3) {
            Text("\(state.percent)%").font(.system(size: 10, weight: .medium).monospacedDigit())
            Image(systemName: state.isCharging ? "battery.100percent.bolt" : Self.symbol(for: state.percent))
                .font(.system(size: 13))
                .foregroundStyle(state.percent <= 20 && !state.onAC ? .red : (state.onAC ? .green : .white))
        }
        .foregroundStyle(.white.opacity(0.6))
        .padding(.trailing, 4)
        .fixedSize()
    }
}
