import AVFoundation
import AudioToolbox

/// Cleans up a voice recording: removes background noise with Apple's voice-isolation
/// effect, cuts low rumble, and evens out the level. Runs offline, faster than real time.
enum VoiceCleaner {
    enum CleanError: LocalizedError {
        case unreadable, failed
        var errorDescription: String? {
            switch self {
            case .unreadable: return "The voice recording couldn't be read."
            case .failed: return "Voice clean-up couldn't be completed."
            }
        }
    }

    static func clean(input: URL, output: URL) throws {
        let file = try AVAudioFile(forReading: input)
        let format = file.processingFormat
        guard file.length > 0 else { throw CleanError.unreadable }

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)
        var chain: [AVAudioNode] = [player]
        var latency = 0.0

        // 'vois' is Apple's sound-isolation audio unit (the engine behind Voice Isolation).
        var description = AudioComponentDescription(componentType: kAudioUnitType_Effect, componentSubType: 0x766f_6973,
                                                    componentManufacturer: kAudioUnitManufacturer_Apple,
                                                    componentFlags: 0, componentFlagsMask: 0)
        if AudioComponentFindNext(nil, &description) != nil {
            let isolation = AVAudioUnitEffect(audioComponentDescription: description)
            engine.attach(isolation)
            chain.append(isolation)
        }

        let eq = AVAudioUnitEQ(numberOfBands: 2)
        eq.bands[0].filterType = .highPass
        eq.bands[0].frequency = 85
        eq.bands[0].bypass = false
        eq.bands[1].filterType = .parametric      // a touch of presence so speech is clearer
        eq.bands[1].frequency = 3500
        eq.bands[1].bandwidth = 1.2
        eq.bands[1].gain = 2
        eq.bands[1].bypass = false
        engine.attach(eq)
        chain.append(eq)

        for (a, b) in zip(chain, chain.dropFirst()) { engine.connect(a, to: b, format: format) }
        engine.connect(eq, to: engine.mainMixerNode, format: format)

        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096)
        try engine.start()
        // Only known once the engine is running.
        for node in chain.dropFirst() { latency += max(node.latency, (node as? AVAudioUnit)?.auAudioUnit.latency ?? 0) }
        if ProcessInfo.processInfo.environment["FC_DEBUG"] != nil { print("effect latency: \(latency)s") }
        player.scheduleFile(file, at: nil)
        player.play()

        // Pass 1: render to an uncompressed temp file, remembering the loudest sample.
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("framecast-clean-\(UUID().uuidString).caf")
        defer { try? FileManager.default.removeItem(at: temp) }
        var peak: Float = 0
        do {
            let scratch = try AVAudioFile(forWriting: temp, settings: format.settings)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: 4096) else { throw CleanError.failed }
            // Effects delay the sound slightly; skip that much so the voice stays in sync.
            var skip = AVAudioFramePosition((latency * format.sampleRate).rounded())
            var written: AVAudioFramePosition = 0
            let wanted = file.length
            var idle = 0
            while written < wanted {
                let status = try engine.renderOffline(4096, to: buffer)
                guard status == .success, buffer.frameLength > 0 else {
                    idle += 1
                    if idle > 200 { break }
                    continue
                }
                var first: AVAudioFrameCount = 0
                if skip > 0 {
                    first = AVAudioFrameCount(min(skip, AVAudioFramePosition(buffer.frameLength)))
                    skip -= AVAudioFramePosition(first)
                    if first == buffer.frameLength { continue }
                }
                let count = AVAudioFrameCount(min(AVAudioFramePosition(buffer.frameLength - first), wanted - written))
                guard let slice = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: count),
                      let src = buffer.floatChannelData, let dst = slice.floatChannelData else { throw CleanError.failed }
                slice.frameLength = count
                for channel in 0..<Int(buffer.format.channelCount) {
                    for i in 0..<Int(count) {
                        let v = src[channel][Int(first) + i]
                        dst[channel][i] = v
                        peak = max(peak, abs(v))
                    }
                }
                try scratch.write(from: slice)
                written += AVAudioFramePosition(count)
            }
        }
        player.stop()
        engine.stop()

        // Pass 2: bring the loudest moment up to just under full scale (at most +12 dB), encode.
        let gain = peak > 0.0001 ? min(0.89 / peak, 4) : 1
        try? FileManager.default.removeItem(at: output)
        let scratch = try AVAudioFile(forReading: temp)
        let out = try AVAudioFile(forWriting: output, settings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVEncoderBitRateKey: 128_000,
        ])
        guard let buffer = AVAudioPCMBuffer(pcmFormat: scratch.processingFormat, frameCapacity: 8192) else { throw CleanError.failed }
        while scratch.framePosition < scratch.length {
            try scratch.read(into: buffer)
            if buffer.frameLength == 0 { break }
            if let data = buffer.floatChannelData {
                for channel in 0..<Int(buffer.format.channelCount) {
                    for i in 0..<Int(buffer.frameLength) { data[channel][i] *= gain }
                }
            }
            try out.write(from: buffer)
        }
    }
}
