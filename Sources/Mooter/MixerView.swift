import SwiftUI

struct MixerView: View {
    let mixer: Mixer

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if mixer.permission != .authorized {
                permissionNote
            }

            if mixer.apps.isEmpty {
                Text("All quiet in the barn. Apps show up here once they play sound.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            } else {
                GroupLabel(text: "Apps")
                ScrollView {
                    VStack(spacing: 14) {
                        ForEach(mixer.apps) { AppRow(app: $0, mixer: mixer) }
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(maxHeight: 420)
                .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            VStack(spacing: 0) {
                Action(title: "Open at Login",
                       symbol: mixer.launchAtLogin ? "checkmark.circle.fill" : "circle") { mixer.toggleLaunchAtLogin() }
                Action(title: "Quit Mooter", symbol: "power") { NSApp.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 300)
        // "Playing" is polled, so only while the popover is open.
        .task {
            while !Task.isCancelled {
                mixer.refresh()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text("Mooter")
                    .font(.headline)
                Label(mixer.outputName, systemImage: "hifispeaker")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var permissionNote: some View {
        let denied = mixer.permission == .denied
        return VStack(alignment: .leading, spacing: 6) {
            Label("Mooter can't hear your apps yet", systemImage: "exclamationmark.triangle.fill")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.orange)
            Text(denied
                 ? "Turn on Mooter under System Audio Recording Only in Privacy & Security."
                 : "macOS asks before one app may adjust another's sound.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Action(title: denied ? "Open Privacy & Security…" : "Allow Access…", symbol: "lock.open") {
                mixer.requestPermission()
            }
        }
    }
}

private struct AppRow: View {
    let app: AudioApp
    let mixer: Mixer

    var body: some View {
        let muted = mixer.isMuted(app)
        let volume = muted ? 0 : mixer.volume(of: app)

        HStack(spacing: 10) {
            Image(nsImage: app.icon)
                .resizable()
                .frame(width: 28, height: 28)
                .saturation(muted ? 0 : 1)
                .opacity(muted ? 0.6 : 1)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(app.name)
                        .lineLimit(1)
                    if app.isPlaying && !muted {
                        Image(systemName: "waveform")
                            .font(.caption2)
                            .foregroundStyle(.tint)
                            .symbolEffect(.variableColor.iterative)
                            .help("Playing")
                    }
                    Spacer(minLength: 8)
                    Text(muted ? "Muted" : volume.formatted(.percent.precision(.fractionLength(0))))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .font(.callout)

                Slider(value: Binding(get: { volume }, set: { mixer.setVolume($0, for: app) }))
                    .controlSize(.mini)
            }

            Button { mixer.toggleMute(app) } label: {
                Image(systemName: muted ? "speaker.slash.fill" : "speaker.wave.3.fill", variableValue: volume)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 20, height: 20)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .foregroundStyle(muted ? .secondary : .primary)
            .help(muted ? "Unmute \(app.name)" : "Mute \(app.name)")
        }
        .contextMenu {
            Button("Reset to 100%") { mixer.setVolume(1, for: app) }
        }
    }
}

/// A small grey caption that introduces a group of rows.
private struct GroupLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.tertiary)
            .textCase(.uppercase)
    }
}

/// A footer command that highlights on hover, like a menu item.
private struct Action: View {
    let title: String
    let symbol: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .frame(width: 16)
                    .foregroundStyle(.secondary)
                Text(title)
                Spacer(minLength: 0)
            }
            .font(.callout)
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .background(hovering ? AnyShapeStyle(.selection) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 5))
        .onHover { hovering = $0 }
    }
}
