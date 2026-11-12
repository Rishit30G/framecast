import CoreMedia

/// Shared by every recorder so a pause removes the same stretch of time from all of them.
final class PauseClock {
    private let lock = NSLock()
    private var offset = CMTime.zero
    private var pausedAt: CMTime?
    /// Host-clock seconds of each pause, for placing clicks afterwards.
    private var pauses: [(start: Double, end: Double?)] = []

    private var now: CMTime { CMClockGetTime(CMClockGetHostTimeClock()) }

    var isPaused: Bool { lock.lock(); defer { lock.unlock() }; return pausedAt != nil }

    func pause() {
        lock.lock(); defer { lock.unlock() }
        guard pausedAt == nil else { return }
        pausedAt = now
        pauses.append((now.seconds, nil))
    }

    func resume() {
        lock.lock(); defer { lock.unlock() }
        guard let start = pausedAt else { return }
        offset = offset + (now - start)
        pausedAt = nil
        if !pauses.isEmpty { pauses[pauses.count - 1].end = now.seconds }
    }

    /// Where the recording's timeline currently ends, on the host clock minus all pauses.
    var endTime: CMTime {
        lock.lock(); defer { lock.unlock() }
        return (pausedAt ?? now) - offset
    }

    /// The sample moved earlier by the total paused time, or nil while paused.
    func adjust(_ sample: CMSampleBuffer) -> CMSampleBuffer? {
        lock.lock()
        let paused = pausedAt != nil
        let shift = offset
        lock.unlock()
        if paused { return nil }
        if shift == .zero { return sample }

        var count: CMItemCount = 0
        CMSampleBufferGetSampleTimingInfoArray(sample, entryCount: 0, arrayToFill: nil, entriesNeededOut: &count)
        guard count > 0 else { return sample }
        var timing = [CMSampleTimingInfo](repeating: CMSampleTimingInfo(), count: count)
        CMSampleBufferGetSampleTimingInfoArray(sample, entryCount: count, arrayToFill: &timing, entriesNeededOut: &count)
        for i in 0..<count {
            timing[i].presentationTimeStamp = timing[i].presentationTimeStamp - shift
            if timing[i].decodeTimeStamp.isValid { timing[i].decodeTimeStamp = timing[i].decodeTimeStamp - shift }
        }
        var out: CMSampleBuffer?
        CMSampleBufferCreateCopyWithNewTiming(allocator: nil, sampleBuffer: sample, sampleTimingEntryCount: count,
                                              sampleTimingArray: &timing, sampleBufferOut: &out)
        return out
    }

    /// Converts a host-clock moment into recording time, or nil if it fell inside a pause.
    func recordedSeconds(host: Double, start: Double) -> Double? {
        lock.lock(); defer { lock.unlock() }
        var removed = 0.0
        for pause in pauses {
            let end = pause.end ?? .greatestFiniteMagnitude
            if host >= pause.start && host <= end { return nil }
            if host > end { removed += end - pause.start }
        }
        return host - start - removed
    }
}
