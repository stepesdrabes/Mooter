import Foundation

/// The "System Audio Recording" permission process taps need. Without it a tap
/// delivers silence. There's no public API to check or request it, so this goes
/// through TCC directly, as every audio-tapping app does.
nonisolated enum AudioPermission {
    enum Status { case unknown, denied, authorized }

    static var status: Status {
        guard let preflight else { return .authorized }
        return switch preflight(service, nil) {
        case 0: .authorized
        case 1: .denied
        default: .unknown
        }
    }

    static func request(then completion: @escaping @MainActor () -> Void) {
        tccRequest?(service, nil) { _ in
            Task { @MainActor in completion() }
        }
    }

    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!

    private typealias Preflight = @convention(c) (CFString, CFDictionary?) -> Int
    private typealias Request = @convention(c) (CFString, CFDictionary?, @convention(block) @escaping (Bool) -> Void) -> Void

    private static var service: CFString { "kTCCServiceAudioCapture" as CFString }
    nonisolated(unsafe) private static let tcc = dlopen("/System/Library/PrivateFrameworks/TCC.framework/TCC", RTLD_NOW)
    private static let preflight = dlsym(tcc, "TCCAccessPreflight").map { unsafeBitCast($0, to: Preflight.self) }
    private static let tccRequest = dlsym(tcc, "TCCAccessRequest").map { unsafeBitCast($0, to: Request.self) }
}
