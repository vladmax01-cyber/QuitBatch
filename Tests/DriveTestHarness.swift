import Foundation

@main
struct DriveTestHarness {
    static func main() {
        let drives = DiskUtility.mountedDrives()
        let expected = CommandLine.arguments.dropFirst().first ?? ""
        guard let drive = drives.first(where: { $0.name == expected }) else {
            fputs("Drive not found: \(expected). Found: \(drives.map(\.name))\n", stderr)
            exit(1)
        }
        guard drive.id.range(of: #"^disk[0-9]+$"#, options: .regularExpression) != nil,
              !drive.mountPoints.isEmpty else { exit(2) }
        print("Found \(drive.name) on \(drive.id), image: \(drive.isDiskImage)")
        if CommandLine.arguments.contains("--blockers") {
            let blockers = DiskUtility.blockers(for: drive)
            print("Blockers: \(blockers.map { "\($0.id):\($0.name)" }.joined(separator: ", "))")
            guard !blockers.isEmpty else { exit(3) }
        }
        if CommandLine.arguments.contains("--expect-busy") {
            let result = DiskUtility.eject(drive, force: false)
            guard !result.succeeded else {
                fputs("Eject unexpectedly succeeded while test process held the volume\n", stderr)
                exit(5)
            }
            print("Busy drive rejected normal eject")
        }
        if CommandLine.arguments.contains("--eject") {
            let result = DiskUtility.eject(drive, force: false)
            guard result.succeeded else {
                fputs(result.output, stderr)
                exit(4)
            }
            print("Ejected test image")
        }
        if CommandLine.arguments.contains("--force-eject") {
            let result = DiskUtility.eject(drive, force: true)
            guard result.succeeded else {
                fputs(result.output, stderr)
                exit(6)
            }
            print("Force ejected busy test image")
        }
    }
}
