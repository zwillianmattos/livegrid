import AVFoundation
import CoreVideo
import Flutter
import Foundation

final class CameraPreview: NSObject, FlutterTexture, AVCaptureVideoDataOutputSampleBufferDelegate,
    AVCaptureAudioDataOutputSampleBufferDelegate {

    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "livegrid.camera.queue")
    private let sessionQueue = DispatchQueue(label: "livegrid.camera.session")
    private let bufferLock = NSLock()
    private var latestBuffer: CVPixelBuffer?
    private weak var registry: FlutterTextureRegistry?
    private(set) var textureId: Int64 = -1

    private var horizontalEncoder: VideoEncoder?
    private var verticalEncoder: VideoEncoder?
    private var horizontalRecorder: FileRecorder?
    private var verticalRecorder: FileRecorder?
    private var verticalPool: CVPixelBufferPool?
    private var verticalCropWidth: Int = 0
    private var verticalCropHeight: Int = 0
    private var verticalCropCenterX: CGFloat = 0.5

    private let audioQueue = DispatchQueue(label: "livegrid.audio.queue")
    private let audioLock = NSLock()
    private var audioRecorders: [FileRecorder] = []
    private var audioAttached = false
    private var lastAudioLevel: Float = 0
    private var lastAudioChannels: Int = 0
    private var routeObserver: NSObjectProtocol?

    func setVerticalCropCenter(_ value: CGFloat) {
        let clamped = max(0, min(1, value))
        queue.async { [weak self] in
            self?.verticalCropCenterX = clamped
        }
    }

    init(registry: FlutterTextureRegistry) {
        super.init()
        self.registry = registry
        textureId = registry.register(self)
        session.automaticallyConfiguresApplicationAudioSession = true
        routeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: nil
        ) { note in
            let reason = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt) ?? 0
            let input = AVAudioSession.sharedInstance().currentRoute.inputs.first
            NSLog("audio route changed reason=\(reason) input=\(input?.portType.rawValue ?? "none") name=\(input?.portName ?? "")")
        }
    }

    deinit {
        if let o = routeObserver { NotificationCenter.default.removeObserver(o) }
    }

    func setEncoders(
        horizontal: VideoEncoder?,
        vertical: VideoEncoder?,
        verticalCropWidth: Int = 0,
        verticalCropHeight: Int = 0
    ) {
        queue.sync {
            horizontalEncoder = horizontal
            verticalEncoder = vertical
            self.verticalCropWidth = verticalCropWidth
            self.verticalCropHeight = verticalCropHeight
            updateVerticalPool()
        }
    }

    func setRecorders(
        horizontal: FileRecorder?,
        vertical: FileRecorder?,
        verticalCropWidth: Int = 0,
        verticalCropHeight: Int = 0
    ) {
        queue.sync {
            horizontalRecorder = horizontal
            verticalRecorder = vertical
            audioLock.lock()
            audioRecorders = [horizontal, vertical].compactMap { $0 }
            audioLock.unlock()
            if vertical != nil {
                self.verticalCropWidth = verticalCropWidth
                self.verticalCropHeight = verticalCropHeight
            }
            updateVerticalPool()
        }
    }

    private func updateVerticalPool() {
        let needsCrop = (verticalEncoder != nil || verticalRecorder != nil)
            && verticalCropWidth > 0 && verticalCropHeight > 0
        if needsCrop {
            if verticalPool == nil {
                verticalPool = makeNV12Pool(width: verticalCropWidth, height: verticalCropHeight)
            }
        } else {
            verticalPool = nil
        }
    }

    private(set) var captureWidth: Int?
    private(set) var captureHeight: Int?

    func start(cameraId: String?, captureWidth: Int? = nil, captureHeight: Int? = nil) throws {
        self.captureWidth = captureWidth
        self.captureHeight = captureHeight
        try sessionQueue.sync {
            try configure(cameraId: cameraId, captureWidth: captureWidth, captureHeight: captureHeight)
        }
        startRunningAsync()
    }

    // startRunning blocks for hundreds of ms; init replies with the textureId
    // and lets frames arrive whenever the session is up.
    func startInBackground(cameraId: String?) {
        captureWidth = nil
        captureHeight = nil
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            do {
                try self.configure(cameraId: cameraId, captureWidth: nil, captureHeight: nil)
                if !self.session.isRunning { self.session.startRunning() }
            } catch {
                NSLog("preview start failed: \(error.localizedDescription)")
            }
        }
    }

    private func startRunningAsync() {
        sessionQueue.async { [weak self] in
            guard let self = self, !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }

    private func configure(cameraId: String?, captureWidth: Int?, captureHeight: Int?) throws {
        let preset = presetFor(width: captureWidth, height: captureHeight)
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
                kCVPixelBufferPixelFormatTypeKey as String:
                    kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
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
                if connection.isVideoStabilizationSupported {
                    connection.preferredVideoStabilizationMode = .off
                }
            }

            attachAudioLocked()
            session.commitConfiguration()
        }
    }

    func ensureAudio() {
        sessionQueue.sync {
            queue.sync {
                guard !audioAttached, AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else { return }
                session.beginConfiguration()
                attachAudioLocked()
                session.commitConfiguration()
            }
        }
    }

    var audioChannelCount: Int {
        audioLock.lock()
        let attached = audioAttached
        let last = lastAudioChannels
        audioLock.unlock()
        guard attached else { return 0 }
        if last > 0 { return min(last, 2) }
        return max(1, min(AVAudioSession.sharedInstance().inputNumberOfChannels, 2))
    }

    var audioLevel: Float {
        audioLock.lock()
        defer { audioLock.unlock() }
        return audioAttached ? lastAudioLevel : 0
    }

    func audioRoute() -> (type: String, name: String) {
        audioLock.lock()
        let attached = audioAttached
        audioLock.unlock()
        guard attached, let input = AVAudioSession.sharedInstance().currentRoute.inputs.first else {
            return ("none", "")
        }
        let type: String
        switch input.portType {
        case .builtInMic: type = "builtin"
        case .usbAudio: type = "usb"
        case .headsetMic, .lineIn: type = "wired"
        case .bluetoothHFP, .bluetoothLE, .bluetoothA2DP: type = "bluetooth"
        default: type = "wired"
        }
        return (type, input.portName)
    }

    private func attachAudioLocked() {
        audioLock.lock()
        audioAttached = false
        lastAudioLevel = 0
        lastAudioChannels = 0
        audioLock.unlock()
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
              let mic = AVCaptureDevice.default(for: .audio) else { return }
        do {
            let micInput = try AVCaptureDeviceInput(device: mic)
            guard session.canAddInput(micInput) else {
                NSLog("audio input rejected by session; recording mute")
                return
            }
            let output = AVCaptureAudioDataOutput()
            guard session.canAddOutput(output) else {
                NSLog("audio output rejected by session; recording mute")
                return
            }
            session.addInput(micInput)
            output.setSampleBufferDelegate(self, queue: audioQueue)
            session.addOutput(output)
            audioLock.lock()
            audioAttached = true
            audioLock.unlock()
        } catch {
            NSLog("audio input failed: \(error.localizedDescription); recording mute")
        }
    }

    func stop() {
        sessionQueue.sync {
            if session.isRunning {
                session.stopRunning()
            }
        }
    }

    func release() {
        stop()
        setEncoders(horizontal: nil, vertical: nil)
        setRecorders(horizontal: nil, vertical: nil)
        if let o = routeObserver {
            NotificationCenter.default.removeObserver(o)
            routeObserver = nil
        }
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
        if output is AVCaptureAudioDataOutput {
            handleAudio(sampleBuffer)
            return
        }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        bufferLock.lock()
        latestBuffer = pixelBuffer
        bufferLock.unlock()
        registry?.textureFrameAvailable(textureId)

        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        horizontalEncoder?.encode(pixelBuffer: pixelBuffer, pts: pts)
        horizontalRecorder?.append(pixelBuffer: pixelBuffer, pts: pts)

        let needsCrop = verticalEncoder != nil || verticalRecorder != nil
        if needsCrop, let pool = verticalPool,
           let cropped = makeVerticalCrop(source: pixelBuffer, pool: pool) {
            verticalEncoder?.encode(pixelBuffer: cropped, pts: pts)
            verticalRecorder?.append(pixelBuffer: cropped, pts: pts)
        }
    }

    private func handleAudio(_ sampleBuffer: CMSampleBuffer) {
        let (level, channels) = Self.measure(sampleBuffer)
        audioLock.lock()
        lastAudioLevel = level
        if channels > 0 { lastAudioChannels = channels }
        let recorders = audioRecorders
        audioLock.unlock()
        for r in recorders { r.appendAudio(sampleBuffer) }
    }

    private static func measure(_ sampleBuffer: CMSampleBuffer) -> (Float, Int) {
        guard let fmt = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(fmt)?.pointee,
              asbd.mFormatID == kAudioFormatLinearPCM else { return (0, 0) }
        let channels = Int(asbd.mChannelsPerFrame)
        var sizeNeeded = 0
        var status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: &sizeNeeded,
            bufferListOut: nil,
            bufferListSize: 0,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: 0,
            blockBufferOut: nil
        )
        guard status == noErr, sizeNeeded > 0 else { return (0, channels) }
        let raw = UnsafeMutableRawPointer.allocate(
            byteCount: sizeNeeded, alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { raw.deallocate() }
        let ablPtr = raw.bindMemory(to: AudioBufferList.self, capacity: 1)
        var blockBuffer: CMBlockBuffer?
        status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: ablPtr,
            bufferListSize: sizeNeeded,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &blockBuffer
        )
        guard status == noErr else { return (0, channels) }
        let isFloat = (asbd.mFormatFlags & kAudioFormatFlagIsFloat) != 0
        var sum: Double = 0
        var count = 0
        for buffer in UnsafeMutableAudioBufferListPointer(ablPtr) {
            guard let data = buffer.mData else { continue }
            let bytes = Int(buffer.mDataByteSize)
            if isFloat && asbd.mBitsPerChannel == 32 {
                let p = data.assumingMemoryBound(to: Float.self)
                let n = bytes / 4
                for i in 0..<n { let v = Double(p[i]); sum += v * v }
                count += n
            } else if asbd.mBitsPerChannel == 16 {
                let p = data.assumingMemoryBound(to: Int16.self)
                let n = bytes / 2
                for i in 0..<n { let v = Double(p[i]) / 32768.0; sum += v * v }
                count += n
            } else if asbd.mBitsPerChannel == 32 {
                let p = data.assumingMemoryBound(to: Int32.self)
                let n = bytes / 4
                for i in 0..<n { let v = Double(p[i]) / 2147483648.0; sum += v * v }
                count += n
            }
        }
        guard count > 0 else { return (0, channels) }
        return (Float(min(1.0, (sum / Double(count)).squareRoot())), channels)
    }

    func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
        bufferLock.lock()
        let buf = latestBuffer
        bufferLock.unlock()
        guard let buf = buf else { return nil }
        return Unmanaged.passRetained(buf)
    }

    private func makeVerticalCrop(source: CVPixelBuffer, pool: CVPixelBufferPool) -> CVPixelBuffer? {
        let cropW = verticalCropWidth
        let cropH = verticalCropHeight
        guard cropW > 0, cropH > 0 else { return nil }

        var dest: CVPixelBuffer?
        let poolStatus = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &dest)
        guard poolStatus == kCVReturnSuccess, let dst = dest else {
            NSLog("vertical pool exhausted status=\(poolStatus)")
            return nil
        }

        let srcW = CVPixelBufferGetWidth(source)
        let srcH = CVPixelBufferGetHeight(source)
        var effectiveCropW = min(cropW, srcW)
        var effectiveCropH = min(cropH, srcH)
        if effectiveCropW % 2 != 0 { effectiveCropW -= 1 }
        if effectiveCropH % 2 != 0 { effectiveCropH -= 1 }
        guard effectiveCropW > 0, effectiveCropH > 0 else { return nil }

        let maxLeft = srcW - effectiveCropW
        var desiredLeft = Int((verticalCropCenterX * CGFloat(srcW)).rounded()) - effectiveCropW / 2
        if desiredLeft % 2 != 0 { desiredLeft -= 1 }
        let cropX = min(max(0, desiredLeft), maxLeft - (maxLeft % 2))
        let cropY = ((srcH - effectiveCropH) / 2) & ~1

        CVPixelBufferLockBaseAddress(source, .readOnly)
        CVPixelBufferLockBaseAddress(dst, [])
        defer {
            CVPixelBufferUnlockBaseAddress(dst, [])
            CVPixelBufferUnlockBaseAddress(source, .readOnly)
        }

        guard let srcY = CVPixelBufferGetBaseAddressOfPlane(source, 0),
              let srcUV = CVPixelBufferGetBaseAddressOfPlane(source, 1),
              let dstY = CVPixelBufferGetBaseAddressOfPlane(dst, 0),
              let dstUV = CVPixelBufferGetBaseAddressOfPlane(dst, 1) else { return nil }

        let srcYStride = CVPixelBufferGetBytesPerRowOfPlane(source, 0)
        let srcUVStride = CVPixelBufferGetBytesPerRowOfPlane(source, 1)
        let dstYStride = CVPixelBufferGetBytesPerRowOfPlane(dst, 0)
        let dstUVStride = CVPixelBufferGetBytesPerRowOfPlane(dst, 1)

        for row in 0..<effectiveCropH {
            memcpy(
                dstY.advanced(by: row * dstYStride),
                srcY.advanced(by: (cropY + row) * srcYStride + cropX),
                effectiveCropW
            )
        }

        let chromaRows = effectiveCropH / 2
        let chromaCopyBytes = effectiveCropW
        let chromaSrcXBytes = cropX
        let chromaSrcYRow = cropY / 2
        for row in 0..<chromaRows {
            memcpy(
                dstUV.advanced(by: row * dstUVStride),
                srcUV.advanced(by: (chromaSrcYRow + row) * srcUVStride + chromaSrcXBytes),
                chromaCopyBytes
            )
        }

        CVBufferSetAttachment(dst, kCVImageBufferYCbCrMatrixKey, kCVImageBufferYCbCrMatrix_ITU_R_709_2, .shouldPropagate)
        CVBufferSetAttachment(dst, kCVImageBufferColorPrimariesKey, kCVImageBufferColorPrimaries_ITU_R_709_2, .shouldPropagate)
        CVBufferSetAttachment(dst, kCVImageBufferTransferFunctionKey, kCVImageBufferTransferFunction_ITU_R_709_2, .shouldPropagate)
        return dst
    }

    private func makeNV12Pool(width: Int, height: Int) -> CVPixelBufferPool? {
        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String:
                kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
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
            var maxW: Int32 = 0
            var maxH: Int32 = 0
            for fmt in device.formats {
                let d = CMVideoFormatDescriptionGetDimensions(fmt.formatDescription)
                if Int(d.width) * Int(d.height) > Int(maxW) * Int(maxH) {
                    maxW = d.width
                    maxH = d.height
                }
            }
            if maxW == 0 {
                let d = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
                maxW = d.width
                maxH = d.height
            }
            return [
                "id": device.uniqueID,
                "lens": lens,
                "label": device.localizedName,
                "maxWidth": Int(maxW),
                "maxHeight": Int(maxH),
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

}
