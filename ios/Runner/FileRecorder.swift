import AVFoundation
import CoreMedia
import CoreVideo
import Foundation

final class FileRecorder {

    let url: URL
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private let lock = NSLock()
    private var started = false
    private var stopped = false

    init(url: URL, width: Int, height: Int, fps: Int, bitrate: Int) throws {
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
            started = true
            NSLog("FileRecorder started at \(url.lastPathComponent) pts=\(pts.seconds)")
        }
        if input.isReadyForMoreMediaData {
            if !adaptor.append(pixelBuffer, withPresentationTime: pts) {
                NSLog("FileRecorder append failed status=\(writer.status.rawValue) err=\(writer.error?.localizedDescription ?? "?")")
            }
        }
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
