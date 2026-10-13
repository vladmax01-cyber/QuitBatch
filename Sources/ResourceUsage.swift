import Darwin
import Foundation

struct ResourceUsage: Equatable {
    let cpuPercent: Double?
    let memoryBytes: UInt64?
}

struct ProcessResourceSnapshot {
    let cpuTicks: UInt64
    let memoryBytes: UInt64
    let sampledAt: TimeInterval
    let startTicks: UInt64
}

enum ResourceSampler {
    static let nanosecondsPerTick: Double = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return Double(info.numer) / Double(info.denom)
    }()

    static func read(pid: pid_t, at time: TimeInterval) -> ProcessResourceSnapshot? {
        var info = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
            }
        }
        guard result == 0 else { return nil }
        return ProcessResourceSnapshot(cpuTicks: info.ri_user_time &+ info.ri_system_time,
                                       memoryBytes: info.ri_phys_footprint, sampledAt: time,
                                       startTicks: info.ri_proc_start_abstime)
    }

    static func usage(current: ProcessResourceSnapshot, previous: ProcessResourceSnapshot?) -> ResourceUsage {
        guard let previous, current.startTicks == previous.startTicks,
              current.cpuTicks >= previous.cpuTicks else {
            return ResourceUsage(cpuPercent: nil, memoryBytes: current.memoryBytes)
        }
        let elapsed = current.sampledAt - previous.sampledAt
        guard elapsed > 0 else { return ResourceUsage(cpuPercent: nil, memoryBytes: current.memoryBytes) }
        let nanoseconds = Double(current.cpuTicks - previous.cpuTicks) * nanosecondsPerTick
        let cpu = nanoseconds / (elapsed * 1_000_000_000) * 100
        return ResourceUsage(cpuPercent: cpu.isFinite ? max(0, cpu) : nil,
                             memoryBytes: current.memoryBytes)
    }
}
