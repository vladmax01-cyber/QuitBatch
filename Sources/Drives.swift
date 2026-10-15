import AppKit
import Combine
import Foundation

struct EjectableDrive: Identifiable, Equatable {
    let id: String
    let name: String
    let mountPoints: [String]
    let isDiskImage: Bool
}

struct DriveBlocker: Identifiable, Equatable {
    let id: pid_t
    let name: String
    let file: String?
    let appPID: pid_t?
}

enum DiskUtility {
    struct Result {
        let status: Int32
        let output: String
        var succeeded: Bool { status == 0 }
    }

    static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval = 15) -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do { try process.run() }
        catch { return Result(status: -1, output: error.localizedDescription) }
        let deadline = DispatchTime.now() + timeout
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: deadline) {
            if process.isRunning { process.terminate() }
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return Result(status: process.terminationStatus,
                      output: String(data: data, encoding: .utf8) ?? "")
    }

    private static func plist(_ arguments: [String]) -> [String: Any]? {
        let result = run("/usr/sbin/diskutil", arguments)
        guard result.succeeded, let data = result.output.data(using: .utf8) else { return nil }
        return (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
    }

    private static func mountedVolumes(in item: [String: Any]) -> [(name: String, path: String)] {
        var result: [(String, String)] = []
        if let path = item["MountPoint"] as? String, !path.isEmpty {
            result.append((item["VolumeName"] as? String ?? URL(fileURLWithPath: path).lastPathComponent, path))
        }
        for key in ["Partitions", "APFSVolumes"] {
            for child in item[key] as? [[String: Any]] ?? [] {
                result += mountedVolumes(in: child)
            }
        }
        return result
    }

    private static func wholeDisk(_ identifier: String) -> String? {
        let pattern = #"^disk[0-9]+"#
        guard let range = identifier.range(of: pattern, options: .regularExpression) else { return nil }
        return String(identifier[range])
    }

    static func mountedDrives() -> [EjectableDrive] {
        guard let list = plist(["list", "-plist"]),
              let entries = list["AllDisksAndPartitions"] as? [[String: Any]] else { return [] }
        var drives: [String: EjectableDrive] = [:]
        for entry in entries {
            for volume in mountedVolumes(in: entry) where volume.path.hasPrefix("/Volumes/") {
                guard let info = plist(["info", "-plist", volume.path]),
                      info["Internal"] as? Bool == false,
                      info["Ejectable"] as? Bool == true else { continue }
                let stores = info["APFSPhysicalStores"] as? [[String: Any]] ?? []
                if stores.count > 1 { continue }
                let storeID = (stores.first?["DeviceIdentifier"] as? String)
                    ?? (stores.first?["APFSPhysicalStore"] as? String)
                let parentID = info["ParentWholeDisk"] as? String
                guard let id = wholeDisk(storeID ?? parentID ?? ""),
                      let deviceInfo = plist(["info", "-plist", id]),
                      deviceInfo["Internal"] as? Bool == false,
                      deviceInfo["Ejectable"] as? Bool == true else { continue }
                let image = deviceInfo["VirtualOrPhysical"] as? String == "Virtual"
                if let old = drives[id] {
                    drives[id] = EjectableDrive(id: id, name: old.name,
                                                mountPoints: old.mountPoints + [volume.path], isDiskImage: image)
                } else {
                    drives[id] = EjectableDrive(id: id, name: volume.name,
                                                mountPoints: [volume.path], isDiskImage: image)
                }
            }
        }
        return drives.values.sorted { lhs, rhs in
            if lhs.isDiskImage != rhs.isDiskImage { return !lhs.isDiskImage }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    static func eject(_ drive: EjectableDrive, force: Bool) -> Result {
        guard drive.id.range(of: #"^disk[0-9]+$"#, options: .regularExpression) != nil else {
            return Result(status: -1, output: "Invalid disk identifier.")
        }
        let current = mountedDrives()
        guard let match = current.first(where: { $0.id == drive.id }),
              !Set(match.mountPoints).isDisjoint(with: drive.mountPoints) else {
            return Result(status: -1, output: "This drive is no longer mounted.")
        }
        return run("/usr/sbin/diskutil", force ? ["eject", "force", drive.id] : ["eject", drive.id],
                   timeout: 30)
    }

    private static func owningAppPID(for pid: pid_t, knownApps: Set<pid_t>) -> pid_t? {
        guard !knownApps.isEmpty else { return nil }
        var current = pid
        var visited: Set<pid_t> = []
        for _ in 0..<6 {
            if knownApps.contains(current) { return current }
            guard current > 1, visited.insert(current).inserted else { break }
            let parent = run("/bin/ps", ["-p", String(current), "-o", "ppid="], timeout: 2)
            guard parent.succeeded,
                  let next = pid_t(parent.output.trimmingCharacters(in: .whitespacesAndNewlines)),
                  next != current else { break }
            current = next
        }
        return nil
    }

    static func blockers(for drive: EjectableDrive, knownAppPIDs: Set<pid_t> = []) -> [DriveBlocker] {
        var byPID: [pid_t: DriveBlocker] = [:]
        for mount in drive.mountPoints {
            let result = run("/usr/sbin/lsof", ["-nP", "-Fpcn", "+f", "--", mount], timeout: 9)
            var pid: pid_t?
            var command = "Process"
            for line in result.output.split(separator: "\n") {
                guard let prefix = line.first else { continue }
                let value = String(line.dropFirst())
                switch prefix {
                case "p": pid = pid_t(value); command = "Process"
                case "c": command = value
                case "n":
                    if let pid, byPID[pid] == nil {
                        byPID[pid] = DriveBlocker(id: pid, name: command,
                                                  file: value.hasPrefix(mount) ? value : nil,
                                                  appPID: owningAppPID(for: pid, knownApps: knownAppPIDs))
                    }
                default: break
                }
            }
        }
        return byPID.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

@MainActor
final class DriveManager: ObservableObject {
    @Published private(set) var drives: [EjectableDrive] = []
    @Published private(set) var blockers: [DriveBlocker] = []
    @Published var selectedBlockerPIDs: Set<pid_t> = []
    @Published private(set) var failedDriveID: String?
    @Published private(set) var workingDriveID: String?
    @Published private(set) var refreshing = false
    @Published var message: String?
    private var observers: [NSObjectProtocol] = []

    init() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            })
        }
    }

    deinit {
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }

    func refresh() {
        guard !refreshing, workingDriveID == nil else { return }
        refreshing = true
        Task {
            let found = await Task.detached(priority: .utility) { DiskUtility.mountedDrives() }.value
            drives = found
            if let failedDriveID, !found.contains(where: { $0.id == failedDriveID }) {
                self.failedDriveID = nil
                blockers = []
                selectedBlockerPIDs = []
            }
            refreshing = false
        }
    }

    func eject(_ drive: EjectableDrive, force: Bool = false) {
        guard workingDriveID == nil else { return }
        workingDriveID = drive.id
        message = nil
        Task {
            let result = await Task.detached(priority: .utility) { DiskUtility.eject(drive, force: force) }.value
            if result.succeeded {
                failedDriveID = nil
                blockers = []
                selectedBlockerPIDs = []
                message = "Ejected \(drive.name)."
            } else {
                failedDriveID = drive.id
                message = "Couldn’t eject \(drive.name). Close open files and try again."
                let known = Set(NSWorkspace.shared.runningApplications.map(\.processIdentifier))
                blockers = await Task.detached(priority: .utility) {
                    DiskUtility.blockers(for: drive, knownAppPIDs: known)
                }.value
                selectedBlockerPIDs = []
            }
            workingDriveID = nil
            refresh()
        }
    }

    func runningApp(for blocker: DriveBlocker) -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first {
            $0.processIdentifier == (blocker.appPID ?? blocker.id) && !$0.isTerminated && !AppPolicy.isProtected($0)
        }
    }

    func closeSelectedAndRetry(_ drive: EjectableDrive, confirm: Bool) {
        guard workingDriveID == nil else { return }
        let apps = blockers.filter { selectedBlockerPIDs.contains($0.id) }.compactMap(runningApp(for:))
        guard !apps.isEmpty else { return }
        if confirm {
            let alert = NSAlert()
            alert.messageText = "Quit \(apps.count) app\(apps.count == 1 ? "" : "s") and retry?"
            alert.informativeText = "Apps with unsaved work may ask you to confirm before closing."
            alert.addButton(withTitle: "Quit Apps")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        workingDriveID = drive.id
        Task {
            for app in apps { _ = app.terminate() }
            let deadline = ProcessInfo.processInfo.systemUptime + 5
            while apps.contains(where: { !$0.isTerminated }) && ProcessInfo.processInfo.systemUptime < deadline {
                try? await Task.sleep(for: .milliseconds(150))
            }
            workingDriveID = nil
            eject(drive)
        }
    }
}
