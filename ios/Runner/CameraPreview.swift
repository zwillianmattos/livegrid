import AVFoundation
import CoreImage
import CoreVideo
import Flutter
import Foundation

final class CameraPreview: NSObject, FlutterTexture, AVCaptureVideoDataOutputSampleBufferDelegate {

    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "livegrid.camera.queue")
    private let bufferLock = NSLock()
    private var latestBuffer: CVPixelBuffer?
    private weak var registry: FlutterTextureRegistry?
    private(set) var textureId: Int64 = -1

    private var horizontalEncoder: VideoEncoder?
    private var verticalEncoder: VideoEncoder?
    private var verticalPool: CVPixelBufferPool?
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private var verticalCropCenterX: CGFloat = 0.5

    func setVerticalCropCenter(_ value: CGFloat) {
        let clamped = max(0, min(1, value))
        queue.async { [weak self] in
            self?.verticalCropCenterX = clamped
        }
    }

    private var frameIndex: Int64 = 0
    private let fps: Int32 = 30

    init(registry: FlutterTextureRegistry) {
        super.init()
        self.registry = registry
        textureId = registry.register(self)
    }

    func setEncoders(horizontal: VideoEncoder?, vertical: VideoEncoder?) {
        queue.sync {
            horizontalEncoder = horizontal
            verticalEncoder = vertical
            if vertical != nil {
                verticalPool = makePool(width: VERTICAL_WIDTH, height: VERTICAL_HEIGHT)
            } else {
                verticalPool = nil
            }
        }
    }

    private(set) var captureWidth: Int?
    private(set) var captureHeight: Int?

    func start(cameraId: String?, captureWidth: Int? = nil, captureHeight: Int? = nil) throws {
        let preset = presetFor(width: captureWidth, height: captureHeight)
        self.captureWidth = captureWidth
        self.captureHeight = captureHeight
        queue.sync {
            session.beginConfiguration()
            session.inputs.forEach { session.removeInput($0) }
            session.outputs.forEach { session.removeOutput($0) }
            session.sessionPreset = preset
        }

        guard let device = resolveDevice(cameraId: cameraId) else {
            session.commitConfiguration()
            throw NSError(
                domain: "livegrid.camera",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "nenhuma câmera disponível"]
            )
        }

        let input = try AVCaptureDeviceInput(device: device)

        queue.sync {
            if session.canAddInput(input) { session.addInput(input) }

            let output = AVCaptureVideoDataOutput()
            output.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            output.alwaysDiscardsLateVideoFrames = true
            output.setSampleBufferDelegate(self, queue: queue)
            if session.canAddOutput(output) { session.addOutput(output) }

            if let connection = output.connection(with: .video) {
                if connection.isVideoOrientationSupported {
                    connection.videoOrientation = .landscapeRight
                }
                if device.position == .front, connection.isVideoMirroringSupported {
                    connection.isVideoMirrored = true
                }
            }

            session.commitConfiguration()
        }

        if !session.isRunning {
            session.startRunning()
        }
    }

    func stop() {
        if session.isRunning {
            session.stopRunning()
        }
    }

    func release() {
        stop()
        setEncoders(horizontal: nil, vertical: nil)
        if let reg = registry, textureId >= 0 {
            reg.unregisterTexture(textureId)
        }
        textureId = -1
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        bufferLock.lock()
        latestBuffer = pixelBuffer
        bufferLock.unlock()
        registry?.textureFrameAvailable(textureId)

        frameIndex += 1
        let pts = CMTime(value: frameIndex, timescale: fps)

        if let enc = horizontalEncoder {
            enc.encode(pixelBuffer: pixelBuffer, pts: pts)
        }

        if let enc = verticalEncoder, let pool = verticalPool,
           let cropped = makeVerticalCrop(source: pixelBuffer, pool: pool) {
            enc.encode(pixelBuffer: cropped, pts: pts)
        }
    }

    func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
        bufferLock.lock()
        let buf = latestBuffer
        bufferLock.unlock()
        guard let buf = buf else { return nil }
        return Unmanaged.passRetained(buf)
    }

    private func makeVerticalCrop(source: CVPixelBuffer, pool: CVPixelBufferPool) -> CVPixelBuffer? {
        var dest: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &dest)
        guard status == kCVReturnSuccess, let dst = dest else { return nil }

        let sw = CGFloat(CVPixelBufferGetWidth(source))
        let sh = CGFloat(CVPixelBufferGetHeight(source))
        let targetAspect: CGFloat = CGFloat(VERTICAL_WIDTH) / CGFloat(VERTICAL_HEIGHT)
        let cropWidth = sh * targetAspect
        let cropHeight = sh
        let maxLeft = max(0, sw - cropWidth)
        let desiredLeft = verticalCropCenterX * sw - cropWidth / 2.0
        let cropX = min(max(0, desiredLeft), maxLeft)
        let cropY: CGFloat = 0

        var ci = CIImage(cvPixelBuffer: source)
        ci = ci.cropped(to: CGRect(x: cropX, y: cropY, width: cropWidth, height: cropHeight))
            .transformed(by: CGAffineTransform(translationX: -cropX, y: -cropY))
        let scale = CGFloat(VERTICAL_HEIGHT) / cropHeight
        ci = ci.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        ciContext.render(ci, to: dst)
        return dst
    }

    private func makePool(width: Int, height: Int) -> CVPixelBufferPool? {
        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
        ]
        var pool: CVPixelBufferPool?
        CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, attrs as CFDictionary, &pool)
        return pool
    }

    static func listCameras() -> [[String: Any]] {
        let types: [AVCaptureDevice.DeviceType] = [
            .builtInWideAngleCamera,
            .builtInUltraWideCamera,
            .builtInTelephotoCamera,
            .builtInDualCamera,
            .builtInDualWideCamera,
            .builtInTripleCamera,
            .builtInTrueDepthCamera,
        ]
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: types,
            mediaType: .video,
            position: .unspecified
        )
        return session.devices.map { device in
            let lens: String
            switch device.position {
            case .back: lens = "back"
            case .front: lens = "front"
            case .unspecified: lens = "external"
            @unknown default: lens = "unknown"
            }
            let dims = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
            return [
                "id": device.uniqueID,
                "lens": lens,
                "label": device.localizedName,
                "maxWidth": Int(dims.width),
                "maxHeight": Int(dims.height),
            ]
        }
    }

    private func presetFor(width: Int?, height: Int?) -> AVCaptureSession.Preset {
        guard let h = height else { return .hd1920x1080 }
        if h >= 2160 { return .hd4K3840x2160 }
        if h >= 1080 { return .hd1920x1080 }
        return .hd1280x720
    }

    private func resolveDevice(cameraId: String?) -> AVCaptureDevice? {
        if let id = cameraId, !id.isEmpty, let device = AVCaptureDevice(uniqueID: id) {
            return device
        }
        return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
            ?? AVCaptureDevice.default(for: .video)
    }

    private let VERTICAL_WIDTH = 1080
    private let VERTICAL_HEIGHT = 1920
}
