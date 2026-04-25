import CoreMedia
import CoreVideo
import Foundation
import VideoToolbox

final class VideoEncoder {

    struct EncodedFrame {
        let data: Data
        let ptsUs: Int64
        let isKeyframe: Bool
    }

    var onEncoded: ((EncodedFrame) -> Void)?
    var onBytes: ((Int) -> Void)?

    private let width: Int32
    private let height: Int32
    private let fps: Int
    private let gop: Int
    private var bitrate: Int
    private let label: String
    private var session: VTCompressionSession?

    init(width: Int, height: Int, fps: Int, gop: Int, bitrate: Int, label: String) {
        self.width = Int32(width)
        self.height = Int32(height)
        self.fps = fps
        self.gop = gop
        self.bitrate = bitrate
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
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_H264_Main_AutoLevel)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate, value: NSNumber(value: bitrate))
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: NSNumber(value: fps))
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxKeyFrameInterval, value: NSNumber(value: gop))
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration, value: NSNumber(value: 1.0))
        let dataLimit = NSArray(array: [NSNumber(value: bitrate / 8), NSNumber(value: 1.0)])
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_DataRateLimits, value: dataLimit)

        VTCompressionSessionPrepareToEncodeFrames(session)
    }

    func encode(pixelBuffer: CVPixelBuffer, pts: CMTime) {
        guard let session = session else { return }
        VTCompressionSessionEncodeFrame(
            session,
            imageBuffer: pixelBuffer,
            presentationTimeStamp: pts,
            duration: .invalid,
            frameProperties: nil,
            infoFlagsOut: nil,
            outputHandler: { [weak self] status, _, sampleBuffer in
                guard status == noErr, let sb = sampleBuffer else { return }
                self?.handleOutput(sb)
            }
        )
    }

    func setBitrate(_ bps: Int) {
        guard let session = session else { return }
        bitrate = bps
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate, value: NSNumber(value: bps))
        let dataLimit = NSArray(array: [NSNumber(value: bps / 8), NSNumber(value: 1.0)])
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_DataRateLimits, value: dataLimit)
    }

    func requestKeyframe() {
        guard let session = session else { return }
        let props: NSDictionary = [kVTEncodeFrameOptionKey_ForceKeyFrame as String: true]
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: NSNumber(value: fps))
        _ = props
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
