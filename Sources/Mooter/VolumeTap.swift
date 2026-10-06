import CoreAudio

/// Re-routes one app's audio through a private process tap and plays it back on
/// the output device at our own volume. While the tap is being read, macOS mutes
/// the app's original output, so only our copy is heard.
nonisolated final class VolumeTap {
    let processes: [AudioObjectID]
    let outputUID: String

    /// Read on the real-time audio thread. A single aligned Float needs no lock.
    private let gain = UnsafeMutablePointer<Float>.allocate(capacity: 1)
    private var tap: AudioHardwareTap?
    private var device: AudioHardwareAggregateDevice?
    private var ioProc: AudioDeviceIOProcID?

    var volume: Float {
        get { gain.pointee }
        set { gain.pointee = newValue }
    }

    init(processes: [AudioObjectID], outputUID: String, volume: Float) {
        self.processes = processes
        self.outputUID = outputUID
        gain.initialize(to: volume)
    }

    deinit {
        let system = AudioHardwareSystem.shared
        if let device {
            if let ioProc {
                try? device.stop(IOProcID: ioProc)
                AudioDeviceDestroyIOProcID(device.id, ioProc)
            }
            try? system.destroyAggregateDevice(device)
        }
        if let tap { try? system.destroyProcessTap(tap) }
        gain.deallocate()
    }

    func start() throws {
        let system = AudioHardwareSystem.shared
        let description = CATapDescription(stereoMixdownOfProcesses: processes)
        description.uuid = UUID()
        description.isPrivate = true
        description.muteBehavior = .mutedWhenTapped
        tap = try system.makeProcessTap(description: description)

        // The output device drives the clock; the tap is resampled to match it.
        device = try system.makeAggregateDevice(description: [
            kAudioAggregateDeviceNameKey: "Mooter",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapUIDKey: description.uuid.uuidString,
                kAudioSubTapDriftCompensationKey: true,
            ]],
        ])
        guard tap != nil, let device else { throw AudioHardwareError(kAudioHardwareIllegalOperationError) }

        let status = AudioDeviceCreateIOProcIDWithBlock(&ioProc, device.id, nil, Self.render(gain: gain))
        guard status == noErr else { throw AudioHardwareError(status) }
        try device.start(IOProcID: ioProc)
    }

    /// Copies the tap's stereo stream onto the output's first two channels at the
    /// current gain. Runs on the real-time thread: no locks, no allocations.
    private static func render(gain: UnsafeMutablePointer<Float>) -> AudioDeviceIOBlock {
        var current = gain.pointee
        return { _, input, _, output, _ in
            let inputs = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
            let outputs = UnsafeMutableAudioBufferListPointer(output)

            // The tap is a single stream, listed after any inputs the output device has.
            let tap = inputs.last
            let source = tap?.mData?.assumingMemoryBound(to: Float.self)
            let sourceChannels = Int(tap?.mNumberChannels ?? 0)
            let sourceFrames = sourceChannels > 0 ? Int(tap!.mDataByteSize) / (sourceChannels * 4) : 0
            let mono = outputs.count == 1 && outputs[0].mNumberChannels == 1

            let target = gain.pointee
            var firstChannel = 0
            for buffer in outputs {
                let channels = Int(buffer.mNumberChannels)
                guard channels > 0, let out = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                let frames = Int(buffer.mDataByteSize) / (channels * 4)
                for frame in 0..<frames {
                    // Ramp to the new gain across the buffer, so moving the slider doesn't click.
                    let level = current + (target - current) * Float(frame + 1) / Float(frames)
                    for channel in 0..<channels {
                        var sample: Float = 0
                        if let source, frame < sourceFrames {
                            let left = source[frame * sourceChannels]
                            let right = source[frame * sourceChannels + sourceChannels - 1]
                            switch firstChannel + channel {
                            case 0: sample = mono ? (left + right) / 2 : left
                            case 1: sample = right
                            default: break
                            }
                        }
                        out[frame * channels + channel] = sample * level
                    }
                }
                firstChannel += channels
            }
            current = target
        }
    }
}
