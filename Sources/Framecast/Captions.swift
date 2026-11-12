import AVFoundation
import Speech

enum CaptionError: LocalizedError {
    case notAuthorized, unavailable, noAudio, noSpeech
    var errorDescription: String? {
        switch self {
        case .notAuthorized: return "Speech recognition is off. Turn it on in System Settings › Privacy & Security › Speech Recognition."
        case .unavailable: return "Speech recognition isn't available for your language on this Mac right now."
        case .noAudio: return "This recording has no audio to caption."
        case .noSpeech: return "No speech was found in the recording."
        }
    }
}

enum CaptionGenerator {
    private struct Word { var text: String; var start: Double; var end: Double }

    /// Transcribes the spoken audio of a project (mic, else voiceovers, else system audio) on this Mac.
    static func generate(for ref: ProjectRef) async throws -> [CaptionSegment] {
        let audioURL = try await speechAudio(for: ref)
        defer { try? FileManager.default.removeItem(at: audioURL) }
        return try await captions(fromAudio: audioURL)
    }

    static func captions(fromAudio url: URL) async throws -> [CaptionSegment] {
        var words: [Word] = []
        var firstError: Error?
        // The newer engine needs neither Siri/Dictation nor a permission prompt, and
        // downloads its language model by itself. Fall back to the older one if it can't run.
        if #available(macOS 26, *) {
            do { words = try await transcribeModern(url) } catch { firstError = error }
        }
        if words.isEmpty {
            do { words = try await transcribeLegacy(url) } catch { throw firstError ?? error }
        }
        guard !words.isEmpty else { throw CaptionError.noSpeech }
        return group(words)
    }

    @available(macOS 26, *)
    private static func transcribeModern(_ url: URL) async throws -> [Word] {
        guard SpeechTranscriber.isAvailable else { throw CaptionError.unavailable }
        var locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale.current)
        if locale == nil { locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "en-US")) }
        guard let locale else { throw CaptionError.unavailable }

        let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [],
                                            attributeOptions: [.audioTimeRange])
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
        let file = try AVAudioFile(forReading: url)
        let analyzer = SpeechAnalyzer(modules: [transcriber])

        async let collected: [Word] = {
            var words: [Word] = []
            for try await result in transcriber.results {
                for run in result.text.runs {
                    guard let range = run.audioTimeRange else { continue }
                    let text = String(result.text[run.range].characters).trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { continue }
                    words.append(Word(text: text, start: range.start.seconds, end: range.end.seconds))
                }
            }
            return words
        }()

        if let last = try await analyzer.analyzeSequence(from: file) {
            try await analyzer.finalizeAndFinish(through: last)
        } else {
            await analyzer.cancelAndFinishNow()
        }
        return try await collected.sorted { $0.start < $1.start }
    }

    private static func transcribeLegacy(_ audioURL: URL) async throws -> [Word] {
        let status = await withCheckedContinuation { (c: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) }
        }
        guard status == .authorized else { throw CaptionError.notAuthorized }
        guard let recognizer = SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US")),
              recognizer.isAvailable else { throw CaptionError.unavailable }

        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }

        return try await withCheckedThrowingContinuation { continuation in
            var collected: [Word] = []
            var resumed = false
            // Long files come back as several finalised chunks; keep each one as it lands.
            func absorb(_ result: SFSpeechRecognitionResult) {
                let lastEnd = collected.last?.end ?? -1
                for s in result.bestTranscription.segments where s.timestamp >= lastEnd - 0.05 && s.duration > 0 {
                    collected.append(Word(text: s.substring, start: s.timestamp, end: s.timestamp + s.duration))
                }
            }
            recognizer.recognitionTask(with: request) { result, error in
                guard !resumed else { return }
                if let result, result.isFinal || result.speechRecognitionMetadata != nil { absorb(result) }
                if let result, result.isFinal {
                    resumed = true
                    continuation.resume(returning: collected)
                } else if let error {
                    resumed = true
                    if collected.isEmpty { continuation.resume(throwing: error) }
                    else { continuation.resume(returning: collected) }
                }
            }
        }
    }

    /// Breaks a word stream into short, readable caption lines.
    private static func group(_ words: [Word]) -> [CaptionSegment] {
        var segments: [CaptionSegment] = []
        var line: [Word] = []
        func flush() {
            guard let first = line.first, let last = line.last else { return }
            segments.append(CaptionSegment(start: first.start, end: max(last.end, first.start + 0.4),
                                           text: line.map(\.text).joined(separator: " ")))
            line = []
        }
        for (i, word) in words.enumerated() {
            line.append(word)
            let chars = line.reduce(0) { $0 + $1.text.count + 1 }
            let next = i + 1 < words.count ? words[i + 1] : nil
            let gap = (next?.start ?? word.end) - word.end
            let sentenceEnd = word.text.last.map { ".?!".contains($0) } ?? false
            // Don't strand the last short word of a sentence on the next line.
            let nextClosesSentence = next.map { ".?!".contains($0.text.last ?? " ") && $0.text.count <= 10 } ?? false
            let full = chars >= 38 && !(nextClosesSentence && chars < 50)
            if full || gap > 0.7 || (sentenceEnd && line.count >= 3) || word.end - line[0].start > 5 { flush() }
        }
        flush()
        // Keep each caption up until the next one starts when the pause is short.
        for i in segments.indices.dropLast() where segments[i + 1].start - segments[i].end < 0.5 {
            segments[i].end = segments[i + 1].start
        }
        return segments
    }

    /// Mixes the voice tracks into one temporary audio file whose timeline matches the project.
    private static func speechAudio(for ref: ProjectRef) async throws -> URL {
        // Uncut, so caption times line up with the raw recording.
        let built = try await CompositionBuilder.build(ref, edited: false)
        var keep = built.micTracks
        if keep.isEmpty { keep = built.voiceTracks }
        if keep.isEmpty { keep = built.systemTracks }
        guard !keep.isEmpty else { throw CaptionError.noAudio }
        for track in built.composition.tracks where !keep.contains(track.trackID) {
            built.composition.removeTrack(track)
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("framecast-speech-\(UUID().uuidString).m4a")
        guard let session = AVAssetExportSession(asset: built.composition, presetName: AVAssetExportPresetAppleM4A)
        else { throw CaptionError.noAudio }
        session.outputURL = url
        session.outputFileType = .m4a
        await session.export()
        guard session.status == .completed else { throw session.error ?? CaptionError.noAudio }
        return url
    }

    static func srt(_ captions: [CaptionSegment]) -> String {
        func stamp(_ t: Double) -> String {
            let ms = Int((t * 1000).rounded())
            return String(format: "%02d:%02d:%02d,%03d", ms / 3_600_000, ms / 60_000 % 60, ms / 1000 % 60, ms % 1000)
        }
        return captions.enumerated().map { i, c in
            "\(i + 1)\n\(stamp(c.start)) --> \(stamp(c.end))\n\(c.text)\n"
        }.joined(separator: "\n")
    }
}
