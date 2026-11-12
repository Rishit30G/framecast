import AVFoundation

/// The project's media laid out on one timeline.
struct BuiltComposition {
    let composition: AVMutableComposition
    let screenTrackID: CMPersistentTrackID
    let cameraTrackID: CMPersistentTrackID?
    /// Pixel size of the screen recording.
    var sourceSize: CGSize = .zero
    var systemTracks: [CMPersistentTrackID] = []
    var micTracks: [CMPersistentTrackID] = []
    var musicTracks: [CMPersistentTrackID] = []
    var voiceTracks: [CMPersistentTrackID] = []
    /// One track per music / sound-effect clip.
    var clipTracks: [UUID: CMPersistentTrackID] = [:]
    let duration: CMTime
}

enum CompositionBuilder {
    static func time(_ seconds: Double) -> CMTime { CMTime(seconds: seconds, preferredTimescale: 60_000) }

    /// `edited: false` lays the media out untouched, on the raw recording's timeline.
    static func build(_ ref: ProjectRef, edited: Bool = true) async throws -> BuiltComposition {
        let project = ref.project
        let composition = AVMutableComposition()

        let screenAsset = AVURLAsset(url: ref.url(project.screenFile))
        var total = try await screenAsset.load(.duration)
        let sourceTotal = total
        guard let screenVideo = try await screenAsset.loadTracks(withMediaType: .video).first,
              let screenTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw NSError(domain: "Framecast", code: 2, userInfo: [NSLocalizedDescriptionKey: "The screen recording is missing or unreadable."]) }
        try screenTrack.insertTimeRange(CMTimeRange(start: .zero, duration: total), of: screenVideo, at: .zero)

        /// Places `source` on a new track so that its first sample lands at `offset` seconds.
        func add(_ source: AVAssetTrack, length: CMTime, type: AVMediaType, offset: Double) -> CMPersistentTrackID? {
            var from = CMTime.zero
            var at = time(offset)
            if offset < 0 { from = time(-offset); at = .zero }
            let available = CMTimeMinimum(length - from, total - at)
            guard available > .zero,
                  let track = composition.addMutableTrack(withMediaType: type, preferredTrackID: kCMPersistentTrackID_Invalid)
            else { return nil }
            do {
                try track.insertTimeRange(CMTimeRange(start: from, duration: available), of: source, at: at)
                return track.trackID
            } catch {
                composition.removeTrack(track)
                return nil
            }
        }

        func addAudio(file url: URL, offset: Double) async -> CMPersistentTrackID? {
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            let asset = AVURLAsset(url: url)
            guard let track = try? await asset.loadTracks(withMediaType: .audio).first,
                  let length = try? await asset.load(.duration) else { return nil }
            return add(track, length: length, type: .audio, offset: offset)
        }

        var cameraID: CMPersistentTrackID?
        if let file = project.cameraFile {
            let asset = AVURLAsset(url: ref.url(file))
            if let track = try? await asset.loadTracks(withMediaType: .video).first,
               let length = try? await asset.load(.duration) {
                if project.cameraOffset < -600 {
                    // Recordings made before the stray-first-frame fix: the real footage starts
                    // at the second frame, hours into the file. Line it up with the screen.
                    if let cursor = track.makeSampleCursorAtFirstSampleInDecodeOrder(),
                       cursor.stepInPresentationOrder(byCount: 1) == 1 {
                        let from = cursor.presentationTimeStamp + time(0.2)
                        let available = CMTimeMinimum(length - from, total)
                        if available > .zero,
                           let target = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) {
                            do {
                                try target.insertTimeRange(CMTimeRange(start: from, duration: available), of: track, at: .zero)
                                cameraID = target.trackID
                            } catch {
                                composition.removeTrack(target)
                            }
                        }
                    }
                } else {
                    cameraID = add(track, length: length, type: .video, offset: project.cameraOffset)
                }
            }
        }

        var systemID: CMPersistentTrackID?
        if let systemAudio = try? await screenAsset.loadTracks(withMediaType: .audio).first {
            systemID = add(systemAudio, length: total, type: .audio, offset: 0)
        }
        var micID: CMPersistentTrackID?
        if let file = project.micFile {
            // The cleaned-up copy has exactly the same timing as the original.
            let clean = ref.url("mic-clean.m4a")
            let useClean = project.audio.voiceCleanup == true && FileManager.default.fileExists(atPath: clean.path)
            micID = await addAudio(file: useClean ? clean : ref.url(file), offset: project.micOffset)
        }

        // Cut out everything between the kept clips, last gap first so earlier times stay valid.
        if edited {
            var gaps: [CMTimeRange] = []
            var cursor = CMTime.zero
            for clip in project.timeline {
                let start = CMTimeMaximum(time(clip.start), cursor)
                if start > cursor { gaps.append(CMTimeRange(start: cursor, end: start)) }
                cursor = CMTimeMaximum(CMTimeMinimum(time(clip.end), sourceTotal), cursor)
            }
            if cursor < sourceTotal { gaps.append(CMTimeRange(start: cursor, end: sourceTotal)) }
            for gap in gaps.reversed() where gap.duration > .zero {
                composition.removeTimeRange(gap)
                total = total - gap.duration
            }
        }

        // Speed changes: stretch or squeeze each clip in place, last first so earlier times stay valid.
        if edited {
            var position = CMTime.zero
            var pieces: [(range: CMTimeRange, rate: Double)] = []
            for clip in project.timeline {
                let length = CMTimeMaximum(CMTimeMinimum(time(clip.end), sourceTotal) - time(clip.start), .zero)
                pieces.append((CMTimeRange(start: position, duration: length), clip.rate))
                position = position + length
            }
            for piece in pieces.reversed() where abs(piece.rate - 1) > 0.001 && piece.range.duration > .zero {
                let scaled = CMTimeMultiplyByFloat64(piece.range.duration, multiplier: 1 / piece.rate)
                composition.scaleTimeRange(piece.range, toDuration: scaled)
                total = total - piece.range.duration + scaled
            }
        }

        var built = BuiltComposition(composition: composition, screenTrackID: screenTrack.trackID,
                                     cameraTrackID: cameraID, duration: total)
        built.sourceSize = (try? await screenVideo.load(.naturalSize)) ?? .zero
        if let systemID { built.systemTracks.append(systemID) }
        if let micID { built.micTracks.append(micID) }
        // Music and voiceovers sit on top of the finished edit, so cuts never chop them up.
        if let path = project.audio.musicPath, let id = await addAudio(file: URL(fileURLWithPath: path), offset: 0) {
            built.musicTracks.append(id)
        }
        for clip in project.audioClips ?? [] {
            let asset = AVURLAsset(url: ref.url(clip.file))
            guard let source = try? await asset.loadTracks(withMediaType: .audio).first,
                  let length = try? await asset.load(.duration) else { continue }
            let from = time(max(clip.offset, 0))
            let at = time(max(clip.start, 0))
            let available = CMTimeMinimum(CMTimeMinimum(time(clip.duration), length - from), total - at)
            guard available > .zero,
                  let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
            else { continue }
            do {
                try track.insertTimeRange(CMTimeRange(start: from, duration: available), of: source, at: at)
                built.clipTracks[clip.id] = track.trackID
            } catch {
                composition.removeTrack(track)
            }
        }
        for clip in project.audio.voiceClips {
            if let id = await addAudio(file: ref.url(clip.file), offset: clip.start) { built.voiceTracks.append(id) }
        }
        return built
    }

    static func videoComposition(_ built: BuiltComposition, project: Project, folder: URL, renderSize: CGSize, fps: Int32) -> AVVideoComposition {
        let vc = AVMutableVideoComposition()
        vc.customVideoCompositorClass = FrameCompositor.self
        vc.frameDuration = CMTime(value: 1, timescale: fps)
        vc.renderSize = renderSize
        vc.colorPrimaries = AVVideoColorPrimaries_ITU_R_709_2
        vc.colorTransferFunction = ColorMode.transfer
        vc.colorYCbCrMatrix = AVVideoYCbCrMatrix_ITU_R_709_2
        let state = RenderState(project: project, folder: folder, screenTrackID: built.screenTrackID, cameraTrackID: built.cameraTrackID)
        vc.instructions = [RenderInstruction(timeRange: CMTimeRange(start: .zero, duration: built.duration), state: state)]
        return vc
    }

    static func audioMix(_ built: BuiltComposition, audio: AudioSettings, clips: [AudioClip] = [], muted: Bool = false) -> AVAudioMix {
        let mix = AVMutableAudioMix()
        var params: [AVMutableAudioMixInputParameters] = []
        func set(_ ids: [CMPersistentTrackID], _ volume: Double) {
            for id in ids {
                guard let track = built.composition.track(withTrackID: id) else { continue }
                let p = AVMutableAudioMixInputParameters(track: track)
                p.setVolume(muted ? 0 : Float(volume), at: .zero)
                params.append(p)
            }
        }
        set(built.systemTracks, audio.systemVolume)
        set(built.micTracks, audio.micVolume)
        set(built.musicTracks, audio.musicVolume)
        set(built.voiceTracks, audio.voiceVolume)
        for clip in clips {
            guard let id = built.clipTracks[clip.id], let track = built.composition.track(withTrackID: id) else { continue }
            let p = AVMutableAudioMixInputParameters(track: track)
            let volume = muted ? 0 : Float(clip.volume)
            let start = time(clip.start)
            let length = min(clip.duration, track.timeRange.duration.seconds)
            let fadeIn = min(max(clip.fadeIn, 0), length / 2), fadeOut = min(max(clip.fadeOut, 0), length / 2)
            p.setVolume(fadeIn > 0.01 ? 0 : volume, at: .zero)
            if fadeIn > 0.01 {
                p.setVolumeRamp(fromStartVolume: 0, toEndVolume: volume, timeRange: CMTimeRange(start: start, duration: time(fadeIn)))
            }
            if fadeOut > 0.01 {
                p.setVolumeRamp(fromStartVolume: volume, toEndVolume: 0,
                                timeRange: CMTimeRange(start: time(clip.start + length - fadeOut), duration: time(fadeOut)))
            }
            params.append(p)
        }
        mix.inputParameters = params
        return mix
    }
}
