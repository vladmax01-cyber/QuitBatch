import SwiftUI

struct DrivesView: View {
    @ObservedObject var manager: DriveManager
    let confirmBeforeQuitting: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Drives").font(.headline)
                    Text("Eject external drives and disk images")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { manager.refresh() } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(manager.refreshing || manager.workingDriveID != nil)
                .accessibilityLabel("Refresh drives")
            }
            .padding(.horizontal, 20)
            .padding(.top, 15)
            .padding(.bottom, 10)

            ScrollView {
                VStack(spacing: 10) {
                    if let message = manager.message {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 10))
                    }
                    if manager.drives.isEmpty {
                        VStack(spacing: 7) {
                            Image(systemName: "externaldrive")
                                .font(.system(size: 26, weight: .light))
                                .foregroundStyle(.secondary)
                            Text(manager.refreshing ? "Checking drives…" : "No ejectable drives mounted")
                                .font(.subheadline)
                            if !manager.refreshing {
                                Text("Connect a drive or open a disk image to see it here.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 35)
                    }
                    ForEach(manager.drives) { drive in
                        DriveCard(manager: manager, drive: drive,
                                  confirmBeforeQuitting: confirmBeforeQuitting)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
        .task { manager.refresh() }
    }
}

private struct DriveCard: View {
    @ObservedObject var manager: DriveManager
    let drive: EjectableDrive
    let confirmBeforeQuitting: Bool
    @State private var confirmingForce = false

    private var failed: Bool { manager.failedDriveID == drive.id }
    private var busy: Bool { manager.workingDriveID == drive.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 10) {
                Image(systemName: drive.isDiskImage ? "opticaldiscdrive" : "externaldrive")
                    .font(.system(size: 19, weight: .regular))
                    .frame(width: 30, height: 30)
                    .foregroundStyle(.tint)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 2) {
                    Text(drive.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Text(drive.isDiskImage ? "Mounted disk image" : "External drive")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 5)
                Button {
                    manager.eject(drive)
                } label: {
                    if busy { ProgressView().controlSize(.small) }
                    else { Label("Eject", systemImage: "eject").labelStyle(.iconOnly) }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(manager.workingDriveID != nil)
                .accessibilityLabel("Eject \(drive.name)")
            }

            if failed {
                Divider()
                if manager.blockers.isEmpty {
                    Text("No open files were visible to QuitBatch. Another process or a pending write may still be using this drive.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Using this drive")
                        .font(.caption.weight(.semibold))
                    ForEach(manager.blockers) { blocker in
                        let app = manager.runningApp(for: blocker)
                        HStack(alignment: .top, spacing: 7) {
                            Toggle(blocker.name, isOn: Binding(
                                get: { manager.selectedBlockerPIDs.contains(blocker.id) },
                                set: { selected in
                                    if selected { manager.selectedBlockerPIDs.insert(blocker.id) }
                                    else { manager.selectedBlockerPIDs.remove(blocker.id) }
                                }
                            ))
                            .labelsHidden()
                            .disabled(app == nil || manager.workingDriveID != nil)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(app?.localizedName ?? blocker.name).font(.caption.weight(.medium))
                                if let file = blocker.file {
                                    Text(file).font(.caption2).foregroundStyle(.secondary)
                                        .lineLimit(1).truncationMode(.middle)
                                        .help(file)
                                } else if app == nil {
                                    Text("Close this process manually")
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
                HStack(spacing: 8) {
                    Button("Retry") { manager.eject(drive) }
                        .buttonStyle(.bordered)
                    if !manager.selectedBlockerPIDs.isEmpty {
                        Button("Close Selected & Retry") {
                            manager.closeSelectedAndRetry(drive, confirm: confirmBeforeQuitting)
                        }
                            .buttonStyle(.bordered)
                    }
                    Spacer(minLength: 0)
                    Button("Force Eject") { confirmingForce = true }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.red)
                }
                .font(.caption)
                .disabled(manager.workingDriveID != nil)
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 11))
        .alert("Force eject \(drive.name)?", isPresented: $confirmingForce) {
            Button("Force Eject", role: .destructive) { manager.eject(drive, force: true) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Files may still be in use. Force ejecting during a write can damage data on this drive.")
        }
    }
}
