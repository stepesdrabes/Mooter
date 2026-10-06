import AppKit
import CoreAudio
import ServiceManagement

/// An app that has opened an audio stream, with its helper processes (browser
/// renderers, WebKit, Electron) folded in, so one slider covers the whole app.
struct AudioApp: Identifiable, Equatable {
    let id: String  // bundle identifier
    let name: String
    let icon: NSImage
    var processes: [AudioObjectID]
    var isPlaying: Bool

    static func == (a: Self, b: Self) -> Bool {
        a.id == b.id && a.processes == b.processes && a.isPlaying == b.isPlaying
    }
}

@Observable
final class Mixer {
    private(set) var apps: [AudioApp] = []
    private(set) var outputName = ""
    private(set) var permission = AudioPermission.status
    private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled

    /// Only apps the user has changed are stored; everything else plays at 100%.
    private var volumes = UserDefaults.standard.dictionary(forKey: "volumes") as? [String: Double] ?? [:]
    private var muted = Set(UserDefaults.standard.stringArray(forKey: "muted") ?? [])

    @ObservationIgnored private var outputUID = ""
    @ObservationIgnored private var taps: [String: VolumeTap] = [:]

    init() {
        // Both fire whether or not the popover is open, so saved volumes apply as
        // soon as an app opens a stream, and taps follow the output device.
        listen(to: kAudioHardwarePropertyProcessObjectList)
        listen(to: kAudioHardwarePropertyDefaultOutputDevice)
        if permission == .unknown { requestPermission() }
        refresh()
    }

    func volume(of app: AudioApp) -> Double { volumes[app.id] ?? 1 }
    func isMuted(_ app: AudioApp) -> Bool { muted.contains(app.id) }

    func setVolume(_ volume: Double, for app: AudioApp) {
        // Snap to 100% at the top, so the tap can be dropped altogether.
        volumes[app.id] = volume > 0.99 ? nil : max(volume, 0)
        if volume > 0 { muted.remove(app.id) }
        save(app)
    }

    func toggleMute(_ app: AudioApp) {
        if muted.remove(app.id) == nil { muted.insert(app.id) }
        save(app)
    }

    func requestPermission() {
        guard permission == .unknown else {
            NSWorkspace.shared.open(AudioPermission.settingsURL)
            return
        }
        AudioPermission.request { [weak self] in self?.refresh() }
    }

    func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        try? launchAtLogin ? service.unregister() : service.register()
        launchAtLogin = service.status == .enabled
    }

    func refresh() {
        let system = AudioHardwareSystem.shared
        let output = try? system.defaultOutputDevice
        outputUID = (try? output?.uid) ?? ""
        outputName = (try? output?.name) ?? "No output device"
        permission = AudioPermission.status

        var found: [String: AudioApp] = [:]
        var listed: Set<String> = []
        for process in (try? system.processes) ?? [] {
            guard let pid = try? process.pid, let owner = Self.owner(of: pid),
                  owner.processIdentifier != getpid(), let id = owner.bundleIdentifier else { continue }
            let playing = (try? process.isRunningOutput) ?? false
            if found[id] == nil {
                let name = (owner.localizedName ?? id).trimmingCharacters(in: .controlCharacters)
                found[id] = AudioApp(id: id, name: name, icon: owner.icon ?? NSImage(), processes: [], isPlaying: false)
            }
            found[id]?.processes.append(process.id)
            if playing { found[id]?.isPlaying = true }
            // Regular apps always show; agents only while they play; system daemons never.
            let isSystem = owner.bundleURL?.path.hasPrefix("/System/Library/") ?? true
            if !isSystem, owner.activationPolicy == .regular || playing { listed.insert(id) }
        }

        let shown = found.values
            .filter { listed.contains($0.id) || volumes[$0.id] != nil || muted.contains($0.id) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        if shown != apps { apps = shown }

        for app in found.values { updateTap(for: app) }
        for id in taps.keys where found[id] == nil { taps[id] = nil }
    }

    // MARK: - Private

    private func save(_ app: AudioApp) {
        UserDefaults.standard.set(volumes, forKey: "volumes")
        UserDefaults.standard.set(Array(muted), forKey: "muted")
        updateTap(for: app)
    }

    /// An app at 100% plays untouched. Anything else is routed through a tap.
    private func updateTap(for app: AudioApp) {
        let gain = Float(isMuted(app) ? 0 : volume(of: app))
        guard gain < 1, permission == .authorized, !outputUID.isEmpty else {
            taps[app.id] = nil
            return
        }
        if let tap = taps[app.id], Set(tap.processes) == Set(app.processes), tap.outputUID == outputUID {
            tap.volume = gain
            return
        }
        // A new helper process or output device: build the replacement before
        // dropping the old tap, so there's no burst at full volume in between.
        let tap = VolumeTap(processes: app.processes, outputUID: outputUID, volume: gain)
        do {
            try tap.start()
            taps[app.id] = tap
        } catch {
            taps[app.id] = nil
            NSLog("Mooter: can't tap \(app.id): \(error.localizedDescription)")
        }
    }

    private func listen(to selector: AudioObjectPropertySelector) {
        var address = AudioObjectPropertyAddress(
            mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    /// Helpers are attributed to the app responsible for them, via the same
    /// private call Activity Monitor uses.
    private static func owner(of pid: pid_t) -> NSRunningApplication? {
        let responsible = responsiblePID?(pid) ?? -1
        return NSRunningApplication(processIdentifier: responsible > 0 ? responsible : pid)
    }

    private static let responsiblePID = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_get_pid_responsible_for_pid")
        .map { unsafeBitCast($0, to: (@convention(c) (pid_t) -> pid_t).self) }
}
