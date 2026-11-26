import AVFoundation
import CoreMedia
import CoreVideo
import Foundation

final class FileRecorder {

    let url: URL
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let audioInput: AVAssetWriterInput?
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private let lock = NSLock()
    private var started = false
    private var stopped = false
    private var sessionStart: CMTime = .invalid
    private let audioChannels: Int
    private var audioDisabled = false
    private var refFormat: AVAudioFormat?
    private var refDescription: CMAudioFormatDescription?
    private var converter: AVAudioConverter?
    private var converterSource = AudioStreamBasicDescription()
    private var lastAudioEnd: CMTime = .invalid
    private var droppedAudio = 0

    init(url: URL, width: Int, height: Int, fps: Int, bitrate: Int, audioChannels: Int = 0) throws {
        self.url = url
        try? FileManager.default.removeItem(at: url)
        let w = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitrate,
                AVVideoExpectedSourceFrameRateKey: fps,
                AVVideoMaxKeyFrameIntervalKey: fps,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoAllowFrameReorderingKey: false,
            ],
        ]
        let i = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        i.expectsMediaDataInRealTime = true
        guard w.canAdd(i) else {
            throw NSError(
                domain: "livegrid.recorder",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "AVAssetWriter cannot add input"]
            )
        }
        w.add(i)
        let a = FileRecorder.makeAudioInput(writer: w, channels: audioChannels)
        self.audioInput = a
        self.audioChannels = a == nil ? 0 : min(audioChannels, 2)
        self.writer = w
        self.input = i
        self.adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: i,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String:
                    kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
            ]
        )
    }

    private static func makeAudioInput(writer: AVAssetWriter, channels: Int) -> AVAssetWriterInput? {
        guard channels > 0 else { return nil }
        let ch = min(channels, 2)
        var layout = AudioChannelLayout()
        layout.mChannelLayoutTag = ch == 2 ? kAudioChannelLayoutTag_Stereo : kAudioChannelLayoutTag_Mono
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: ch,
            AVEncoderBitRateKey: ch == 2 ? 192_000 : 128_000,
            AVChannelLayoutKey: Data(bytes: &layout, count: MemoryLayout<AudioChannelLayout>.size),
        ]
        let a = AVAssetWriterInput(mediaType: .audio, outputSettings: settings)
        a.expectsMediaDataInRealTime = true
        guard writer.canAdd(a) else {
            NSLog("FileRecorder cannot add audio input; recording mute")
            return nil
        }
        writer.add(a)
        return a
    }

    func append(pixelBuffer: CVPixelBuffer, pts: CMTime) {
        lock.lock()
        defer { lock.unlock() }
        if stopped { return }
        if !started {
            guard pts.isValid else { return }
            guard writer.startWriting() else {
                NSLog("FileRecorder startWriting failed status=\(writer.status.rawValue) err=\(writer.error?.localizedDescription ?? "?")")
                stopped = true
                return
            }
            writer.startSession(atSourceTime: pts)
            sessionStart = pts
            started = true
            NSLog("FileRecorder started at \(url.lastPathComponent) pts=\(pts.seconds) audio=\(audioInput != nil)")
        }
        if input.isReadyForMoreMediaData {
            if !adaptor.append(pixelBuffer, withPresentationTime: pts) {
                NSLog("FileRecorder append failed status=\(writer.status.rawValue) err=\(writer.error?.localizedDescription ?? "?")")
            }
        }
    }

    func appendAudio(_ sampleBuffer: CMSampleBuffer) {
        guard let audioInput = audioInput else { return }
        lock.lock()
        defer { lock.unlock() }
        guard started, !stopped, !audioDisabled, writer.status == .writing else { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard pts.isValid, CMTimeCompare(pts, sessionStart) >= 0 else { return }
        guard let fmt = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(fmt)?.pointee,
              asbd.mFormatID == kAudioFormatLinearPCM else { return }
        if refFormat == nil, !establishReference(fmt: fmt, asbd: asbd) {
            audioDisabled = true
            return
        }
        guard let ref = refFormat, let refDesc = refDescription else { return }
        let toAppend: CMSampleBuffer
        if FileRecorder.sameFormat(asbd, ref.streamDescription.pointee) {
            if lastAudioEnd.isValid, CMTimeCompare(pts, lastAudioEnd) < 0 {
                guard let shifted = FileRecorder.retimed(sampleBuffer, to: lastAudioEnd, sampleRate: asbd.mSampleRate) else { return }
                toAppend = shifted
            } else {
                toAppend = sampleBuffer
            }
        } else {
            guard let converted = convert(sampleBuffer, fmt: fmt, asbd: asbd, pts: pts, ref: ref, refDesc: refDesc) else {
                return
            }
            toAppend = converted
        }
        guard audioInput.isReadyForMoreMediaData else { return }
        if audioInput.append(toAppend) {
            let frames = CMSampleBufferGetNumSamples(toAppend)
            let start = CMSampleBufferGetPresentationTimeStamp(toAppend)
            lastAudioEnd = CMTimeAdd(start, CMTime(value: CMTimeValue(frames), timescale: CMTimeScale(ref.sampleRate)))
        } else {
            audioDisabled = true
            NSLog("FileRecorder audio append failed; audio disabled for \(url.lastPathComponent) status=\(writer.status.rawValue) err=\(writer.error?.localizedDescription ?? "?")")
        }
    }

    private func establishReference(fmt: CMAudioFormatDescription, asbd: AudioStreamBasicDescription) -> Bool {
        if Int(asbd.mChannelsPerFrame) == audioChannels {
            refFormat = AVAudioFormat(cmAudioFormatDescription: fmt)
            refDescription = fmt
            return true
        }
        let tag = audioChannels == 2 ? kAudioChannelLayoutTag_Stereo : kAudioChannelLayoutTag_Mono
        guard let layout = AVAudioChannelLayout(layoutTag: tag) else { return false }
        let f = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: asbd.mSampleRate,
            interleaved: true,
            channelLayout: layout
        )
        refFormat = f
        refDescription = f.formatDescription
        NSLog("FileRecorder audio input \(asbd.mChannelsPerFrame)ch @\(asbd.mSampleRate) converted to \(audioChannels)ch")
        return true
    }

    private func convert(
        _ sampleBuffer: CMSampleBuffer,
        fmt: CMAudioFormatDescription,
        asbd: AudioStreamBasicDescription,
        pts: CMTime,
        ref: AVAudioFormat,
        refDesc: CMAudioFormatDescription
    ) -> CMSampleBuffer? {
        if converter == nil || !FileRecorder.sameFormat(converterSource, asbd) {
            let src = AVAudioFormat(cmAudioFormatDescription: fmt)
            guard let c = AVAudioConverter(from: src, to: ref) else {
                logDrop("no converter for \(asbd.mChannelsPerFrame)ch @\(asbd.mSampleRate)")
                return nil
            }
            c.downmix = true
            converter = c
            converterSource = asbd
            NSLog("FileRecorder audio format changed to \(asbd.mChannelsPerFrame)ch @\(asbd.mSampleRate); converting")
        }
        guard let conv = converter else { return nil }
        let frames = CMSampleBufferGetNumSamples(sampleBuffer)
        guard frames > 0,
              let inBuf = AVAudioPCMBuffer(pcmFormat: conv.inputFormat, frameCapacity: AVAudioFrameCount(frames)) else {
            return nil
        }
        inBuf.frameLength = AVAudioFrameCount(frames)
        let copyStatus = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer, at: 0, frameCount: Int32(frames), into: inBuf.mutableAudioBufferList
        )
        guard copyStatus == noErr else {
            logDrop("PCM copy failed \(copyStatus)")
            return nil
        }
        let ratio = ref.sampleRate / conv.inputFormat.sampleRate
        let capacity = AVAudioFrameCount((Double(frames) * ratio).rounded(.up)) + 64
        guard let outBuf = AVAudioPCMBuffer(pcmFormat: ref, frameCapacity: capacity) else { return nil }
        var fed = false
        var error: NSError?
        let status = conv.convert(to: outBuf, error: &error) { _, inputStatus in
            if fed {
                inputStatus.pointee = .noDataNow
                return nil
            }
            fed = true
            inputStatus.pointee = .haveData
            return inBuf
        }
        guard status != .error else {
            logDrop("convert failed \(error?.localizedDescription ?? "?")")
            return nil
        }
        guard outBuf.frameLength > 0 else { return nil }

        // Resampler latency shifts output vs. input; overlapping audio PTS fails the append and kills the writer.
        var outPts = pts
        if lastAudioEnd.isValid,
           CMTimeGetSeconds(CMTimeSubtract(pts, lastAudioEnd)) < 0.1 {
            outPts = lastAudioEnd
        }
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: CMTimeScale(ref.sampleRate)),
            presentationTimeStamp: outPts,
            decodeTimeStamp: .invalid
        )
        var out: CMSampleBuffer?
        var st = CMSampleBufferCreate(
            allocator: kCFAllocatorDefault,
            dataBuffer: nil,
            dataReady: false,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: refDesc,
            sampleCount: CMItemCount(outBuf.frameLength),
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &out
        )
        guard st == noErr, let result = out else {
            logDrop("sample buffer create failed \(st)")
            return nil
        }
        st = CMSampleBufferSetDataBufferFromAudioBufferList(
            result,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: 0,
            bufferList: outBuf.audioBufferList
        )
        guard st == noErr else {
            logDrop("set data buffer failed \(st)")
            return nil
        }
        return result
    }

    private static func retimed(_ sampleBuffer: CMSampleBuffer, to pts: CMTime, sampleRate: Double) -> CMSampleBuffer? {
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: CMTimeScale(sampleRate)),
            presentationTimeStamp: pts,
            decodeTimeStamp: .invalid
        )
        var out: CMSampleBuffer?
        let st = CMSampleBufferCreateCopyWithNewTiming(
            allocator: kCFAllocatorDefault,
            sampleBuffer: sampleBuffer,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleBufferOut: &out
        )
        return st == noErr ? out : nil
    }

    private func logDrop(_ reason: String) {
        droppedAudio += 1
        if droppedAudio == 1 || droppedAudio % 100 == 0 {
            NSLog("FileRecorder dropping audio (\(droppedAudio)) \(url.lastPathComponent): \(reason)")
        }
    }

    private static func sameFormat(_ a: AudioStreamBasicDescription, _ b: AudioStreamBasicDescription) -> Bool {
        a.mSampleRate == b.mSampleRate
            && a.mFormatID == b.mFormatID
            && a.mFormatFlags == b.mFormatFlags
            && a.mBytesPerFrame == b.mBytesPerFrame
            && a.mChannelsPerFrame == b.mChannelsPerFrame
            && a.mBitsPerChannel == b.mBitsPerChannel
    }

    func finish(completion: @escaping (URL?) -> Void) {
        lock.lock()
        let wasStarted = started
        let already = stopped
        stopped = true
        lock.unlock()
        if already {
            completion(nil)
            return
        }
        if !wasStarted {
            try? FileManager.default.removeItem(at: url)
            completion(nil)
            return
        }
        input.markAsFinished()
        audioInput?.markAsFinished()
        let outURL = url
        let writerRef = writer
        writerRef.finishWriting {
            let status = writerRef.status
            if status == .completed {
                NSLog("FileRecorder finished \(outURL.lastPathComponent)")
                completion(outURL)
            } else {
                NSLog("FileRecorder finish failed status=\(status.rawValue) err=\(writerRef.error?.localizedDescription ?? "?")")
                completion(nil)
            }
        }
    }
}
