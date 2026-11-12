import AVFoundation

enum ExportResolution: String, CaseIterable, Identifiable {
    case p2160 = "4K", p1080 = "1080p", p720 = "720p"
    /// The recording's own pixel size (capped at 4K).
    case original = "Original"
    var id: String { rawValue }
    var shortSide: CGFloat {
        switch self {
        case .p2160: return 2160
        case .p1080: return 1080
        case .p720: return 720
        case .original: return 2160
        }
    }
    /// Target video bitrate at 60 fps.
    var bitrate: Int {
        switch self {
        case .p2160: return 45_000_000
        case .p1080: return 14_000_000
        case .p720: return 7_000_000
        case .original: return 30_000_000
        }
    }
}

extension ExportResolution {
    func shortSide(for project: Project) -> CGFloat {
        self == .original ? min(max(project.sourceShortSide, 360), 2160) : shortSide
    }
}

final class Exporter {
    private var cancelled = false
    private var reader: AVAssetReader?
    private let lock = NSLock()

    func cancel() {
        lock.lock(); cancelled = true; lock.unlock()
        reader?.cancelReading()
    }

    private var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }

    /// Renders the project to an MP4. `progress` is called with 0...1 on an arbitrary queue.
    func export(ref: ProjectRef, to url: URL, resolution: ExportResolution, fps: Int32,
                progress: @escaping (Double) -> Void) async throws {
        var project = ref.project
        let built = try await CompositionBuilder.build(ref)
        if project.sourceSize == nil { project.sourceSize = built.sourceSize }
        let size = project.canvasSize(shortSide: resolution.shortSide(for: project))
        let range = CMTimeRange(start: .zero, duration: built.duration)

        try? FileManager.default.removeItem(at: url)
        let reader = try AVAssetReader(asset: built.composition)
        reader.timeRange = range
        self.reader = reader

        let videoTracks = built.composition.tracks(withMediaType: .video)
        let videoOut = AVAssetReaderVideoCompositionOutput(videoTracks: videoTracks, videoSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ])
        videoOut.videoComposition = CompositionBuilder.videoComposition(built, project: project, folder: ref.folder, renderSize: size, fps: fps)
        videoOut.alwaysCopiesSampleData = false
        reader.add(videoOut)

        let audioTracks = built.composition.tracks(withMediaType: .audio)
        var audioOut: AVAssetReaderAudioMixOutput?
        if !audioTracks.isEmpty {
            let out = AVAssetReaderAudioMixOutput(audioTracks: audioTracks, audioSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 2,
            ])
            out.audioMix = CompositionBuilder.audioMix(built, audio: project.audio, clips: project.audioClips ?? [])
            out.alwaysCopiesSampleData = false
            out.audioTimePitchAlgorithm = .timeDomain     // keeps voices natural in sped-up clips
            reader.add(out)
            audioOut = out
        }

        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        writer.shouldOptimizeForNetworkUse = true
        // Scale the bitrate to the real frame size (matters for Original and odd shapes).
        let reference = resolution.shortSide * resolution.shortSide * 16 / 9
        let scaled = Int(Double(resolution.bitrate) * Double(size.width * size.height / reference))
        let full = min(max(scaled, 4_000_000), 60_000_000)
        let bitrate = fps > 30 ? full : full * 2 / 3
        let videoIn = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitrate,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoExpectedSourceFrameRateKey: Int(fps),
                AVVideoMaxKeyFrameIntervalKey: Int(fps) * 2,
            ],
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: ColorMode.transfer,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
            ],
        ])
        videoIn.expectsMediaDataInRealTime = false
        writer.add(videoIn)
        var audioIn: AVAssetWriterInput?
        if audioOut != nil {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 192_000,
            ])
            input.expectsMediaDataInRealTime = false
            writer.add(input)
            audioIn = input
        }

        guard reader.startReading() else { throw reader.error ?? ExportError.failed }
        guard writer.startWriting() else { throw writer.error ?? ExportError.failed }
        writer.startSession(atSourceTime: range.start)

        let total = max(range.duration.seconds, 0.01)
        async let video: Void = pump(from: videoOut, to: videoIn, reader: reader, label: "framecast.export.video") { pts in
            progress(min(max((pts.seconds - range.start.seconds) / total, 0), 1))
        }
        if let audioOut, let audioIn {
            async let audio: Void = pump(from: audioOut, to: audioIn, reader: reader, label: "framecast.export.audio") { _ in }
            _ = await (video, audio)
        } else {
            await video
        }

        if isCancelled || reader.status == .cancelled {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: url)
            throw CancellationError()
        }
        if reader.status == .failed {
            writer.cancelWriting()
            throw reader.error ?? ExportError.failed
        }
        writer.endSession(atSourceTime: range.end)
        await writer.finishWriting()
        if writer.status != .completed { throw writer.error ?? ExportError.failed }
        progress(1)
    }

    private func pump(from output: AVAssetReaderOutput, to input: AVAssetWriterInput, reader: AVAssetReader,
                      label: String, onSample: @escaping (CMTime) -> Void) async {
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            var finished = false
            input.requestMediaDataWhenReady(on: DispatchQueue(label: label)) {
                guard !finished else { return }
                while input.isReadyForMoreMediaData {
                    if !self.isCancelled, reader.status == .reading, let sample = output.copyNextSampleBuffer() {
                        onSample(CMSampleBufferGetPresentationTimeStamp(sample))
                        if input.append(sample) { continue }
                    }
                    finished = true
                    input.markAsFinished()
                    done.resume()
                    return
                }
            }
        }
    }
}

enum ExportError: LocalizedError {
    case failed
    var errorDescription: String? { "The export couldn't be completed." }
}
