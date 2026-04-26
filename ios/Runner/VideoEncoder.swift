import CoreMedia
import CoreVideo
import Foundation
import VideoToolbox

final class VideoEncoder {

    enum ProfileLevel {
        case baseline
        case main

        var key: CFString {
            switch self {
            case .baseline: return kVTProfileLevel_H264_Baseline_AutoLevel
            case .main: return kVTProfileLevel_H264_Main_AutoLevel
            }
        }
    }

    struct EncodedFrame {
        let data: Data
        let ptsUs: Int64
        let isKeyframe: Bool
    }

    var onEncoded: ((EncodedFrame) -> Void)?
    var onBytes: ((Int) -> Void)?

    private let width: Int32
    private let height: Int32
    private var fps: Int
    private let gop: Int
    private var bitrate: Int
    private let profileLevel: ProfileLevel
    private let label: String
    private var session: VTCompressionSession?
    private var forceKeyframeNext = false
    private let keyframeLock = NSLock()

    init(
        width: Int,
        height: Int,
        fps: Int,
        gop: Int,
        bitrate: Int,
        label: String,
        profileLevel: ProfileLevel = .main
    ) {
        self.width = Int32(width)
        self.height = Int32(height)
        self.fps = fps
        self.gop = gop
        self.bitrate = bitrate
        self.profileLevel = profileLevel
        self.label = label
    }

    func start() throws {
        var s: VTCompressionSession?
        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: width,
            height: height,
            codecType: kCMVideoCodecType_H264,
            encoderSpecification: nil,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: nil,
            refcon: nil,
            compressionSessionOut: &s
        )
        guard status == noErr, let session = s else {
            throw NSError(domain: "livegrid.encoder", code: Int(status), userInfo: nil)
        }
        self.session = session

        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ProfileLevel, value: profileLevel.key)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate, value: NSNumber(value: bitrate))
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: NSNumber(value: fps))
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxKeyFrameInterval, value: NSNumber(value: gop))
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration, value: NSNumber(value: 1.0))

        VTCompressionSessionPrepareToEncodeFrames(session)
    }

    func encode(pixelBuffer: CVPixelBuffer, pts: CMTime) {
        guard let session = session else { return }

        keyframeLock.lock()
        let force = forceKeyframeNext
        forceKeyframeNext = false
        keyframeLock.unlock()

        let props: CFDictionary? = force
            ? [kVTEncodeFrameOptionKey_ForceKeyFrame: kCFBooleanTrue!] as CFDictionary
            : nil

        let label = self.label
        let submitStatus = VTCompressionSessionEncodeFrame(
            session,
            imageBuffer: pixelBuffer,
            presentationTimeStamp: pts,
            duration: .invalid,
            frameProperties: props,
            infoFlagsOut: nil,
            outputHandler: { [weak self] status, _, sampleBuffer in
                if status != noErr {
                    NSLog("encoder[\(label)] output status=\(status)")
                    return
                }
                guard let sb = sampleBuffer else { return }
                self?.handleOutput(sb)
            }
        )
        if submitStatus != noErr {
            NSLog("encoder[\(label)] submit status=\(submitStatus)")
        }
    }

    func setBitrate(_ bps: Int) {
        guard let session = session else { return }
        bitrate = bps
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate, value: NSNumber(value: bps))
    }

    func setFrameRate(_ newFps: Int) {
        guard let session = session, newFps > 0, newFps != fps else { return }
        fps = newFps
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: NSNumber(value: newFps))
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxKeyFrameInterval, value: NSNumber(value: newFps))
    }

    func requestKeyframe() {
        keyframeLock.lock()
        forceKeyframeNext = true
        keyframeLock.unlock()
    }

    func stop() {
        guard let session = session else { return }
        VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid)
        VTCompressionSessionInvalidate(session)
        self.session = nil
    }

    private func handleOutput(_ sampleBuffer: CMSampleBuffer) {
        let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[CFString: Any]]
        let notSync = attachments?.first?[kCMSampleAttachmentKey_NotSync] as? Bool ?? false
        let isKeyframe = !notSync

        var annexB = Data()
        if isKeyframe, let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer) {
            var count: Int = 0
            CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
                formatDesc,
                parameterSetIndex: 0,
                parameterSetPointerOut: nil,
                parameterSetSizeOut: nil,
                parameterSetCountOut: &count,
                nalUnitHeaderLengthOut: nil
            )
            for i in 0..<count {
                var ptr: UnsafePointer<UInt8>?
                var size: Int = 0
                if CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
                    formatDesc,
                    parameterSetIndex: i,
                    parameterSetPointerOut: &ptr,
                    parameterSetSizeOut: &size,
                    parameterSetCountOut: nil,
                    nalUnitHeaderLengthOut: nil
                ) == noErr, let p = ptr {
                    annexB.append(contentsOf: [0x00, 0x00, 0x00, 0x01])
                    annexB.append(p, count: size)
                }
            }
        }

        guard let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
        var totalLength = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        if CMBlockBufferGetDataPointer(
            dataBuffer,
            atOffset: 0,
            lengthAtOffsetOut: nil,
            totalLengthOut: &totalLength,
            dataPointerOut: &dataPointer
        ) == noErr, let base = dataPointer {
            var offset = 0
            while offset + 4 <= totalLength {
                var nalLenBE: UInt32 = 0
                memcpy(&nalLenBE, base.advanced(by: offset), 4)
                let nalLen = Int(CFSwapInt32BigToHost(nalLenBE))
                offset += 4
                if nalLen <= 0 || offset + nalLen > totalLength { break }
                annexB.append(contentsOf: [0x00, 0x00, 0x00, 0x01])
                base.advanced(by: offset).withMemoryRebound(to: UInt8.self, capacity: nalLen) { ptr in
                    annexB.append(ptr, count: nalLen)
                }
                offset += nalLen
            }
        }

        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let ptsUs = Int64((pts.seconds * 1_000_000).rounded())
        onBytes?(annexB.count)
        onEncoded?(EncodedFrame(data: annexB, ptsUs: ptsUs, isKeyframe: isKeyframe))
    }
}
