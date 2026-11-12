import AVFoundation

/// Owns one capture session for the camera (preview + recording) and the microphone.
/// The camera and the mic are written to separate files so the editor can treat them independently.
final class CameraRecorder: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "framecast.camera")
    private var cameraInput: AVCaptureDeviceInput?
    private var micInput: AVCaptureDeviceInput?
    private let videoOutput = AVCaptureVideoDataOutput()
    private let audioOutput = AVCaptureAudioDataOutput()

    private var videoWriter: AVAssetWriter?
    private var videoWriterInput: AVAssetWriterInput?
    private var audioWriter: AVAssetWriter?
    private var audioWriterInput: AVAssetWriterInput?
    private var videoURL: URL?
    private var audioURL: URL?
    private var writing = false
    var clock = PauseClock()

    /// Host-clock times of the first camera frame / mic sample written.
    private(set) var firstVideoPTS: CMTime?
    private(set) var firstAudioPTS: CMTime?

    /// Shows the given camera in the preview (nil turns the camera off).
    func setCamera(_ device: AVCaptureDevice?) {
        queue.async {
            self.session.beginConfiguration()
            if let old = self.cameraInput { self.session.removeInput(old); self.cameraInput = nil }
            if let device, let input = try? AVCaptureDeviceInput(device: device), self.session.canAddInput(input) {
                self.session.addInput(input)
                self.cameraInput = input
                if self.session.canSetSessionPreset(.hd1920x1080) { self.session.sessionPreset = .hd1920x1080 }
                else if self.session.canSetSessionPreset(.hd1280x720) { self.session.sessionPreset = .hd1280x720 }
                else { self.session.sessionPreset = .high }
            }
            self.session.commitConfiguration()
            if self.cameraInput != nil || self.writing {
                if !self.session.isRunning { self.session.startRunning() }
            } else if self.session.isRunning {
                self.session.stopRunning()
            }
        }
    }

    /// Starts writing camera.mov and/or mic.m4a. The mic is only attached while recording,
    /// so the microphone indicator stays off the rest of the time.
    func startRecording(mic: AVCaptureDevice?, cameraURL: URL, micURL: URL) async {
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            queue.async {
                self.session.beginConfiguration()
                if let mic, let input = try? AVCaptureDeviceInput(device: mic), self.session.canAddInput(input) {
                    self.session.addInput(input)
                    self.micInput = input
                    if self.session.canAddOutput(self.audioOutput) { self.session.addOutput(self.audioOutput) }
                    self.audioOutput.setSampleBufferDelegate(self, queue: self.queue)
                }
                if self.cameraInput != nil {
                    self.videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange]
                    self.videoOutput.alwaysDiscardsLateVideoFrames = false
                    if self.session.canAddOutput(self.videoOutput) { self.session.addOutput(self.videoOutput) }
                    self.videoOutput.setSampleBufferDelegate(self, queue: self.queue)
                }
                self.session.commitConfiguration()
                self.videoURL = self.cameraInput != nil ? cameraURL : nil
                self.audioURL = self.micInput != nil ? micURL : nil
                self.firstVideoPTS = nil
                self.firstAudioPTS = nil
                self.writing = true
                if (self.cameraInput != nil || self.micInput != nil) && !self.session.isRunning {
                    self.session.startRunning()
                }
                done.resume()
            }
        }
    }

    /// Returns which files were actually written.
    func stopRecording() async -> (camera: Bool, mic: Bool) {
        await withCheckedContinuation { (done: CheckedContinuation<(camera: Bool, mic: Bool), Never>) in
            queue.async {
                self.writing = false
                let group = DispatchGroup()
                var camera = false, mic = false
                if let w = self.videoWriter, w.status == .writing {
                    self.videoWriterInput?.markAsFinished()
                    group.enter()
                    w.finishWriting { camera = w.status == .completed; group.leave() }
                }
                if let w = self.audioWriter, w.status == .writing {
                    self.audioWriterInput?.markAsFinished()
                    group.enter()
                    w.finishWriting { mic = w.status == .completed; group.leave() }
                }
                group.notify(queue: self.queue) {
                    self.videoWriter = nil; self.videoWriterInput = nil
                    self.audioWriter = nil; self.audioWriterInput = nil
                    self.session.beginConfiguration()
                    if let m = self.micInput { self.session.removeInput(m); self.micInput = nil }
                    self.session.removeOutput(self.audioOutput)
                    self.session.removeOutput(self.videoOutput)
                    self.session.commitConfiguration()
                    if self.cameraInput == nil, self.session.isRunning { self.session.stopRunning() }
                    done.resume(returning: (camera, mic))
                }
            }
        }
    }

    func shutdown() {
        queue.async { if self.session.isRunning { self.session.stopRunning() } }
    }

    // MARK: Sample buffers

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard writing, sampleBuffer.isValid else { return }
        // Right after the outputs are attached a frame can arrive stamped on a different
        // clock (near zero). Written first, it would push the real footage hours down the file.
        let raw = hostTime(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        let now = CMClockGetTime(CMClockGetHostTimeClock())
        guard raw.isNumeric, abs((now - raw).seconds) < 3 else { return }
        guard let sampleBuffer = clock.adjust(sampleBuffer) else { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        if output === videoOutput {
            if videoWriter == nil, let url = videoURL {
                guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mov) else { return }
                let settings = videoOutput.recommendedVideoSettingsForAssetWriter(writingTo: .mov)
                let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
                input.expectsMediaDataInRealTime = true
                writer.add(input)
                guard writer.startWriting() else { return }
                writer.startSession(atSourceTime: pts)
                videoWriter = writer
                videoWriterInput = input
                firstVideoPTS = hostTime(pts)
            }
            if let input = videoWriterInput, input.isReadyForMoreMediaData { input.append(sampleBuffer) }
        } else if output === audioOutput {
            if audioWriter == nil, let url = audioURL {
                guard let writer = try? AVAssetWriter(outputURL: url, fileType: .m4a) else { return }
                let settings: [String: Any] = [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: 48_000,
                    AVNumberOfChannelsKey: 1,
                    AVEncoderBitRateKey: 128_000,
                ]
                let input = AVAssetWriterInput(mediaType: .audio, outputSettings: settings)
                input.expectsMediaDataInRealTime = true
                writer.add(input)
                guard writer.startWriting() else { return }
                writer.startSession(atSourceTime: pts)
                audioWriter = writer
                audioWriterInput = input
                firstAudioPTS = hostTime(pts)
            }
            if let input = audioWriterInput, input.isReadyForMoreMediaData { input.append(sampleBuffer) }
        }
    }

    /// Capture timestamps are on the session clock; the screen recording uses the host clock.
    private func hostTime(_ pts: CMTime) -> CMTime {
        guard let clock = session.synchronizationClock else { return pts }
        return CMSyncConvertTime(pts, from: clock, to: CMClockGetHostTimeClock())
    }
}
