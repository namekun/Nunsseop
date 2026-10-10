import Darwin
import SwiftUI

/// CPU, memory, network and disk figures, sampled only while the System tab is visible.
@MainActor
final class SystemStats: ObservableObject {
    @Published private(set) var cpu: Double = 0
    @Published private(set) var memoryUsed: UInt64 = 0
    let memoryTotal = ProcessInfo.processInfo.physicalMemory
    @Published private(set) var downloadRate: Double = 0
    @Published private(set) var uploadRate: Double = 0
    @Published private(set) var diskFree: Int64 = 0
    @Published private(set) var diskTotal: Int64 = 0

    private var timer: Timer?
    private var lastTicks: (busy: UInt64, total: UInt64)?
    private var lastBytes: (received: UInt64, sent: UInt64, at: Date)?

    func start() {
        guard timer == nil else { return }
        lastTicks = nil
        lastBytes = nil
        sample()
        // CPU and network are rates, so take a second reading right away rather than showing zero until the next tick.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, self.timer != nil else { return }
            self.sample()
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
        timer?.tolerance = 0.15
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func sample() {
        if let ticks = Self.cpuTicks() {
            if let last = lastTicks, ticks.total > last.total {
                cpu = Double(ticks.busy - last.busy) / Double(ticks.total - last.total)
            }
            lastTicks = ticks
        }
        memoryUsed = Self.memoryInUse()
        let bytes = Self.networkBytes()
        let now = Date()
        if let last = lastBytes {
            let seconds = max(0.5, now.timeIntervalSince(last.at))
            downloadRate = Self.rate(previous: last.received, current: bytes.received, seconds: seconds)
            uploadRate = Self.rate(previous: last.sent, current: bytes.sent, seconds: seconds)
        }
        lastBytes = (bytes.received, bytes.sent, now)
        if let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]) {
            diskFree = values.volumeAvailableCapacityForImportantUsage ?? 0
            diskTotal = Int64(values.volumeTotalCapacity ?? 0)
        }
    }

    nonisolated static func rate(previous: UInt64, current: UInt64, seconds: Double) -> Double {
        // The counters are 32-bit sums over all interfaces, so one that wraps or disappears makes the total drop.
        current >= previous ? Double(current - previous) / seconds : 0
    }

    private static func cpuTicks() -> (busy: UInt64, total: UInt64)? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let user = UInt64(info.cpu_ticks.0), system = UInt64(info.cpu_ticks.1)
        let idle = UInt64(info.cpu_ticks.2), nice = UInt64(info.cpu_ticks.3)
        return (user + system + nice, user + system + nice + idle)
    }

    private static func memoryInUse() -> UInt64 {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        let page = UInt64(vm_kernel_page_size)
        return (UInt64(stats.active_count) + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)) * page
    }

    private static func networkBytes() -> (received: UInt64, sent: UInt64) {
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else { return (0, 0) }
        defer { freeifaddrs(pointer) }
        var received: UInt64 = 0, sent: UInt64 = 0
        for entry in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let interface = entry.pointee
            guard let address = interface.ifa_addr, address.pointee.sa_family == UInt8(AF_LINK),
                  let data = interface.ifa_data?.assumingMemoryBound(to: if_data.self) else { continue }
            let name = String(cString: interface.ifa_name)
            guard !name.hasPrefix("lo") else { continue }
            received += UInt64(data.pointee.ifi_ibytes)
            sent += UInt64(data.pointee.ifi_obytes)
        }
        return (received, sent)
    }
}

struct SystemTab: View {
    @ObservedObject var stats: SystemStats
    let peripherals: PeripheralMonitor?

    var body: some View {
        // Narrower gauges leave the network card room on a narrow notch.
        ViewThatFits(in: .horizontal) {
            row(gaugeWidth: 112)
            row(gaugeWidth: 96)
        }
        .foregroundStyle(.white)
        .onAppear { stats.start() }
        .onDisappear { stats.stop() }
    }

    private func row(gaugeWidth: CGFloat) -> some View {
        HStack(spacing: 10) {
            Gauge(title: "CPU", value: stats.cpu, caption: String(localized: "\(ProcessInfo.processInfo.activeProcessorCount) cores"), tint: .orange,
                  width: gaugeWidth)
            Gauge(title: String(localized: "Memory"),
                  value: stats.memoryTotal > 0 ? Double(stats.memoryUsed) / Double(stats.memoryTotal) : 0,
                  caption: "\(Self.bytes(Int64(stats.memoryUsed))) / \(Self.bytes(Int64(stats.memoryTotal)))", tint: .blue,
                  width: gaugeWidth)
            Gauge(title: String(localized: "Disk"),
                  value: stats.diskTotal > 0 ? 1 - Double(stats.diskFree) / Double(stats.diskTotal) : 0,
                  caption: String(localized: "\(Self.bytes(stats.diskFree)) free"), tint: .purple, width: gaugeWidth)
            VStack(alignment: .leading, spacing: 6) {
                Text("Network").font(.system(size: 12, weight: .semibold))
                HStack(spacing: 10) {
                    Label(Self.bytes(Int64(stats.downloadRate)) + "/s", systemImage: "arrow.down")
                    Label(Self.bytes(Int64(stats.uploadRate)) + "/s", systemImage: "arrow.up")
                        .foregroundStyle(.white.opacity(0.7))
                }
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .lineLimit(1).minimumScaleFactor(0.7)
                if let peripherals {
                    Divider().overlay(.white.opacity(0.15)).padding(.vertical, 2)
                    DeviceList(monitor: peripherals)
                }
            }
            .padding(14)
            // The ideal width is what the network rates need; the card still takes any spare room.
            .frame(idealWidth: 160, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .surface(RoundedRectangle(cornerRadius: 14))
        }
    }

    static func bytes(_ value: Int64) -> String {
        // The formatter spells out "bytes" in the user's language; keep "B" like KB and MB.
        if value < 1024 { return "\(max(0, value)) B" }
        return ByteCountFormatter.string(fromByteCount: value, countStyle: .memory)
    }
}

private struct DeviceList: View {
    @ObservedObject var monitor: PeripheralMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Devices").font(.system(size: 12, weight: .semibold))
            if monitor.devices.isEmpty {
                Text("No battery devices connected").font(.system(size: 10)).foregroundStyle(.white.opacity(0.45))
            }
            // Four or more devices scroll inside the card instead of running past the bottom of the notch.
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(monitor.devices) { device in
                        HStack(spacing: 6) {
                            Image(systemName: device.symbol).font(.system(size: 10)).frame(width: 14)
                            Text(device.name).font(.system(size: 10)).lineLimit(1)
                            Spacer(minLength: 4)
                            Text("\(device.percent)%").font(.system(size: 10, weight: .semibold).monospacedDigit())
                                .foregroundStyle(device.percent <= 15 ? .red : .white)
                        }
                    }
                }
            }
        }
        .onAppear { monitor.refresh() }
    }
}

private struct Gauge: View {
    let title: String
    let value: Double
    let caption: String
    let tint: Color
    let width: CGFloat

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().stroke(.white.opacity(0.12), lineWidth: 7)
                Circle()
                    .trim(from: 0, to: min(1, max(0, value)))
                    .stroke(tint, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.4), value: value)
                Text("\(Int((min(1, max(0, value)) * 100).rounded()))%")
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
            }
            .frame(width: 58, height: 58)
            Text(title).font(.system(size: 12, weight: .semibold))
            Text(caption).font(.system(size: 9).monospacedDigit()).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
        }
        .padding(.vertical, 12).padding(.horizontal, 8)
        .frame(width: width)
        .frame(maxHeight: .infinity)
        .surface(RoundedRectangle(cornerRadius: 14))
    }
}
