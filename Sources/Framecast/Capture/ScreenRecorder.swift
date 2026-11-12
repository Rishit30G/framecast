import AVFoundation
import ScreenCaptureKit

/// Records a ScreenCaptureKit stream (plus optional system audio) into a movie file.
final class ScreenRecorder: NSObject, SCStreamOutput, SCStreamDelegate {
    private var stream: SCStream?
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private let queue = DispatchQueue(label: "framecast.screen")
    private var sessionStarted = false
    private var stopped = false
    private var lastPTS = CMTime.zero

    /// Host-clock time of the first frame written.
    private(set) var firstPTS: CMTime?
    var onError: ((Error) -> Void)?
    var clock = PauseClock()

    func start(filter: SCContentFilter, pixelSize: CGSize, sourceRect: CGRect?,
               systemAudio: Bool, url: URL) async throws {
        func even(_ v: CGFloat) -> Int { max(2, Int((v / 2).rounded()) * 2) }
        let width = even(pixelSize.width), height = even(pixelSize.height)

        let config = SCStreamConfiguration()
        config.width = width
        config.height = height
        config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = true
        config.queueDepth = 6
        config.scalesToFit = true
        if let sourceRect { config.sourceRect = sourceRect }
        // Without this the frames arrive in the display's own (wider) colour space and then
        // get labelled as standard video, which washes the colours out.
        if !ColorMode.legacy { config.colorSpaceName = CGColorSpace.sRGB }
        if systemAudio {
            config.capturesAudio = true
            config.excludesCurrentProcessAudio = true
            config.sampleRate = 48_000
            config.channelCount = 2
        }

        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        // HEVC: H.264 hardware encoding tops out below 5K displays.
        let bitrate = min(60_000_000, max(8_000_000, width * height * 5))
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitrate,
                AVVideoExpectedSourceFrameRateKey: 60,
            ],
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: ColorMode.transfer,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
            ],
        ])
        videoInput.expectsMediaDataInRealTime = true
        writer.add(videoInput)
        self.videoInput = videoInput

        if systemAudio {
            let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 192_000,
            ])
            audioInput.expectsMediaDataInRealTime = true
            writer.add(audioInput)
            self.audioInput = audioInput
        }
        guard writer.startWriting() else { throw writer.error ?? RecorderError.cannotWrite }
        self.writer = writer

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        if systemAudio { try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue) }
        try await stream.startCapture()
        self.stream = stream
    }

    func stop() async {
        try? await stream?.stopCapture()
        stream = nil
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            queue.async {
                self.stopped = true
                guard let writer = self.writer, writer.status == .writing, self.sessionStarted else {
                    self.writer?.cancelWriting()
                    done.resume()
                    return
                }
                // Hold the last frame until "now" so a static screen keeps its full length.
                writer.endSession(atSourceTime: CMTimeMaximum(self.clock.endTime, self.lastPTS))
                self.videoInput?.markAsFinished()
                self.audioInput?.markAsFinished()
                writer.finishWriting { done.resume() }
            }
        }
    }

    // MARK: SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard !stopped, sampleBuffer.isValid, let writer, writer.status == .writing else { return }
        // Frames that arrive while paused are dropped; the rest slide earlier to close the gap.
        guard let sampleBuffer = clock.adjust(sampleBuffer) else { return }
        switch type {
        case .screen:
            guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                    as? [[SCStreamFrameInfo: Any]],
                  let raw = attachments.first?[.status] as? Int,
                  SCFrameStatus(rawValue: raw) == .complete,
                  let videoInput else { return }
            let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            if !sessionStarted {
                writer.startSession(atSourceTime: pts)
                sessionStarted = true
                firstPTS = pts
            }
            if videoInput.isReadyForMoreMediaData, videoInput.append(sampleBuffer) { lastPTS = pts }
        case .audio:
            guard sessionStarted, let audioInput, audioInput.isReadyForMoreMediaData else { return }
            audioInput.append(sampleBuffer)
        default:
            break
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        onError?(error)
    }
}

enum RecorderError: LocalizedError {
    case cannotWrite, noSource, noPermission
    var errorDescription: String? {
        switch self {
        case .cannotWrite: return "Couldn't start writing the recording file."
        case .noSource: return "Nothing is selected to record."
        case .noPermission: return "Framecast needs Screen Recording permission. Turn it on in System Settings › Privacy & Security › Screen & System Audio Recording, then reopen the app."
        }
    }
}
