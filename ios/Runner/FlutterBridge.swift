import AVFoundation
import Darwin
import Flutter
import Foundation
import Photos
import UIKit

final class FlutterBridge: NSObject, FlutterStreamHandler {

    private let control: FlutterMethodChannel
    private let stats: FlutterEventChannel
    private let textures: FlutterTextureRegistry
    private var eventSink: FlutterEventSink?
    private var statsTimer: Timer?

    private var preview: CameraPreview?
    private var activeCameraId: String?
    private var isLive = false

    private var horizontalEncoder: VideoEncoder?
    private var verticalEncoder: VideoEncoder?
    private var horizontalPublisher: TcpPublisher?
    private var verticalPublisher: TcpPublisher?
    private var horizontalRecorder: FileRecorder?
    private var verticalRecorder: FileRecorder?
    private var captureMode: String = "live"

    private var currentFps: Int = 30
    private var hBytesWindow: Int = 0
    private var vBytesWindow: Int = 0
    private let byteLock = NSLock()
    private var lastSampleNanos: UInt64 = 0

    init(messenger: FlutterBinaryMessenger, textures: FlutterTextureRegistry) {
        self.control = FlutterMethodChannel(name: "livegrid/control", binaryMessenger: messenger)
        self.stats = FlutterEventChannel(name: "livegrid/stats", binaryMessenger: messenger)
        self.textures = textures
        super.init()
        control.setMethodCallHandler { [weak self] call, result in
            self?.handle(call, result: result)
        }
        stats.setStreamHandler(self)
    }

    func detach() {
        control.setMethodCallHandler(nil)
        stats.setStreamHandler(nil)
        statsTimer?.invalidate()
        statsTimer = nil
        eventSink = nil
        stopAllOutputs()
        preview?.release()
        preview = nil
    }

    private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "init":
            handleInit(result: result)
        case "listCameras":
            result(CameraPreview.listCameras())
        case "startCapture":
            handleStart(call, result: result)
        case "stop":
            isLive = false
            stopAllOutputs()
            result(nil)
        case "switchResolution":
            if let args = call.arguments as? [String: Any],
               let w = args["width"] as? Int,
               let h = args["height"] as? Int,
               let p = preview {
                if w == p.captureWidth && h == p.captureHeight {
                    result(nil)
                    return
                }
                do {
                    try p.start(cameraId: activeCameraId, captureWidth: w, captureHeight: h)
                    horizontalEncoder?.requestKeyframe()
                    verticalEncoder?.requestKeyframe()
                    NSLog("switchResolution applied \(w)x\(h)")
                } catch {
                    NSLog("switchResolution failed: \(error.localizedDescription)")
                    result(FlutterError(code: "switch_resolution", message: error.localizedDescription, details: nil))
                    return
                }
            }
            result(nil)
        case "setBitrate":
            if let args = call.arguments as? [String: Any] {
                if let h = args["horizontalBps"] as? Int { horizontalEncoder?.setBitrate(h) }
                if let v = args["verticalBps"] as? Int { verticalEncoder?.setBitrate(v) }
            }
            result(nil)
        case "setFrameRate":
            if let args = call.arguments as? [String: Any], let f = args["fps"] as? Int {
                currentFps = f
                horizontalEncoder?.setFrameRate(f)
                verticalEncoder?.setFrameRate(f)
            }
            result(nil)
        case "requestKeyframe":
            horizontalEncoder?.requestKeyframe()
            verticalEncoder?.requestKeyframe()
            result(nil)
        case "setVerticalCrop":
            if let args = call.arguments as? [String: Any],
               let x = args["centerX"] as? Double {
                preview?.setVerticalCropCenter(CGFloat(x))
            }
            result(nil)
        case "wifiBand":
            result("unknown")
        case "deviceIp":
            result(Self.localWifiIp())
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func handleInit(result: @escaping FlutterResult) {
        let p = preview ?? CameraPreview(registry: textures)
        preview = p
        let cameraId = defaultBackCameraId()
        activeCameraId = cameraId
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async {
                if granted {
                    do {
                        try p.start(cameraId: cameraId)
                    } catch {
                        NSLog("preview start failed: \(error.localizedDescription)")
                    }
                } else {
                    NSLog("camera permission denied")
                }
                result(NSNumber(value: p.textureId))
            }
        }
    }

    private func handleStart(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let profile = args["profile"] as? [String: Any] else {
            result(FlutterError(code: "bad_profile", message: "profile ausente", details: nil))
            return
        }
        let network = args["network"] as? [String: Any]

        let captureMap = profile["capture"] as? [String: Any]
        let captureW = captureMap?["width"] as? Int
        let captureH = captureMap?["height"] as? Int

        let cameraId = profile["cameraId"] as? String
        let cameraChanged = (cameraId.map { !$0.isEmpty && $0 != activeCameraId }) ?? false
        let captureChanged = (captureW != nil && captureW != preview?.captureWidth) ||
            (captureH != nil && captureH != preview?.captureHeight)

        if (cameraChanged || captureChanged), let p = preview {
            if let id = cameraId, !id.isEmpty { activeCameraId = id }
            do {
                try p.start(cameraId: activeCameraId, captureWidth: captureW, captureHeight: captureH)
            } catch {
                NSLog("restart camera failed: \(error.localizedDescription)")
            }
        }

        guard let hMap = profile["horizontal"] as? [String: Any],
              let vMap = profile["vertical"] as? [String: Any] else {
            result(FlutterError(code: "bad_profile", message: "perfis ausentes", details: nil))
            return
        }

        let mode = (profile["mode"] as? String) ?? "live"
        captureMode = mode
        let isRecording = mode == "recording"

        let cropCenterX = (profile["verticalCropCenterX"] as? Double) ?? 0.5
        preview?.setVerticalCropCenter(CGFloat(cropCenterX))
        let hW = (hMap["width"] as? Int) ?? 1920
        let hH = (hMap["height"] as? Int) ?? 1080
        let hFps = (hMap["fps"] as? Int) ?? 30
        let hBps = (hMap["bitrateBps"] as? Int) ?? 6_000_000
        let hGop = (hMap["gop"] as? Int) ?? hFps
        let vFps = (vMap["fps"] as? Int) ?? 30
        let vBps = (vMap["bitrateBps"] as? Int) ?? 5_000_000
        let vGop = (vMap["gop"] as? Int) ?? vFps
        currentFps = hFps

        let sourceH = captureH ?? 1080
        var vCropW = (sourceH * 9) / 16
        if vCropW % 2 != 0 { vCropW -= 1 }
        let vCropH = sourceH

        if isRecording {
            handleStartRecording(
                hW: hW, hH: hH, hFps: hFps, hBps: hBps,
                vCropW: vCropW, vCropH: vCropH, vFps: vFps, vBps: vBps,
                result: result
            )
        } else {
            handleStartLive(
                hW: hW, hH: hH, hFps: hFps, hBps: hBps, hGop: hGop,
                network: network,
                result: result
            )
        }
    }

    private func handleStartLive(
        hW: Int, hH: Int, hFps: Int, hBps: Int, hGop: Int,
        network: [String: Any]?,
        result: @escaping FlutterResult
    ) {
        let obsHost = ((network?["obsHost"] as? String) ?? "").trimmingCharacters(in: .whitespaces)
        let hPort = (network?["horizontalPort"] as? Int) ?? 9000

        let hPub = TcpPublisher(port: hPort, label: "H")
        hPub.open()
        horizontalPublisher = hPub

        let hEnc = VideoEncoder(
            width: hW, height: hH, fps: hFps, gop: hGop, bitrate: hBps,
            label: "H", profileLevel: .baseline
        )
        hEnc.onEncoded = { [weak self] f in
            self?.horizontalPublisher?.publish(annexB: f.data, ptsUs: f.ptsUs, isKeyframe: f.isKeyframe)
        }
        hEnc.onBytes = { [weak self] n in
            self?.byteLock.lock(); self?.hBytesWindow += n; self?.byteLock.unlock()
        }

        do {
            try hEnc.start()
        } catch {
            hPub.close()
            horizontalPublisher = nil
            result(FlutterError(code: "encoder", message: error.localizedDescription, details: nil))
            return
        }
        horizontalEncoder = hEnc
        preview?.setEncoders(horizontal: hEnc, vertical: nil)

        isLive = true
        let displayHost: String
        if !obsHost.isEmpty {
            displayHost = obsHost
        } else if let ip = Self.localWifiIp() {
            displayHost = ip
        } else {
            displayHost = "<IP_DO_IPHONE>"
        }
        result(["horizontalUrl": "tcp://\(displayHost):\(hPort)"])
    }

    private func handleStartRecording(
        hW: Int, hH: Int, hFps: Int, hBps: Int,
        vCropW: Int, vCropH: Int, vFps: Int, vBps: Int,
        result: @escaping FlutterResult
    ) {
        let dir = Self.recordingsDirectory()
        let stamp = Self.timestampString()
        let hUrl = dir.appendingPathComponent("livegrid_\(stamp)_horizontal.mp4")
        let vUrl = dir.appendingPathComponent("livegrid_\(stamp)_vertical.mp4")

        do {
            let hRec = try FileRecorder(url: hUrl, width: hW, height: hH, fps: hFps, bitrate: hBps)
            let vRec = try FileRecorder(url: vUrl, width: vCropW, height: vCropH, fps: vFps, bitrate: vBps)
            horizontalRecorder = hRec
            verticalRecorder = vRec
        } catch {
            horizontalRecorder = nil
            verticalRecorder = nil
            result(FlutterError(code: "recorder", message: error.localizedDescription, details: nil))
            return
        }
        preview?.setRecorders(
            horizontal: horizontalRecorder,
            vertical: verticalRecorder,
            verticalCropWidth: vCropW,
            verticalCropHeight: vCropH
        )
        isLive = true
        result([
            "horizontalFile": hUrl.path,
            "verticalFile": vUrl.path,
        ])
    }

    private static func recordingsDirectory() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("recordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func timestampString() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd_HHmmss"
        return f.string(from: Date())
    }

    private func stopAllOutputs() {
        preview?.setEncoders(horizontal: nil, vertical: nil)
        preview?.setRecorders(horizontal: nil, vertical: nil)
        horizontalEncoder?.stop()
        verticalEncoder?.stop()
        horizontalEncoder = nil
        verticalEncoder = nil
        horizontalPublisher?.close()
        verticalPublisher?.close()
        horizontalPublisher = nil
        verticalPublisher = nil
        let hRec = horizontalRecorder
        let vRec = verticalRecorder
        horizontalRecorder = nil
        verticalRecorder = nil
        hRec?.finish { url in
            if let url = url { Self.saveToPhotoLibrary(url: url) }
            _ = hRec
        }
        vRec?.finish { url in
            if let url = url { Self.saveToPhotoLibrary(url: url) }
            _ = vRec
        }
    }

    private static func saveToPhotoLibrary(url: URL) {
        let perform: () -> Void = {
            PHPhotoLibrary.shared().performChanges({
                let req = PHAssetCreationRequest.forAsset()
                let opts = PHAssetResourceCreationOptions()
                opts.shouldMoveFile = false
                req.addResource(with: .video, fileURL: url, options: opts)
            }) { success, error in
                if success {
                    NSLog("Photo library saved \(url.lastPathComponent)")
                } else {
                    NSLog("Photo library save failed for \(url.lastPathComponent): \(error?.localizedDescription ?? "?")")
                }
            }
        }
        let granted: (PHAuthorizationStatus) -> Bool = { status in
            if status == .authorized { return true }
            if #available(iOS 14, *), status == .limited { return true }
            return false
        }
        let status: PHAuthorizationStatus
        if #available(iOS 14, *) {
            status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        } else {
            status = PHPhotoLibrary.authorizationStatus()
        }
        if granted(status) {
            perform()
            return
        }
        if status == .notDetermined {
            let handler: (PHAuthorizationStatus) -> Void = { newStatus in
                if granted(newStatus) {
                    perform()
                } else {
                    NSLog("Photo library permission denied for \(url.lastPathComponent)")
                }
            }
            if #available(iOS 14, *) {
                PHPhotoLibrary.requestAuthorization(for: .addOnly, handler: handler)
            } else {
                PHPhotoLibrary.requestAuthorization(handler)
            }
        } else {
            NSLog("Photo library permission denied for \(url.lastPathComponent)")
        }
    }

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        eventSink = events
        statsTimer?.invalidate()
        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.emitStats()
        }
        RunLoop.main.add(t, forMode: .common)
        statsTimer = t
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        statsTimer?.invalidate()
        statsTimer = nil
        eventSink = nil
        return nil
    }

    private func emitStats() {
        guard let sink = eventSink else { return }
        let now = DispatchTime.now().uptimeNanoseconds
        let dt: Double
        if lastSampleNanos == 0 {
            dt = 0.5
        } else {
            dt = Double(now - lastSampleNanos) / 1_000_000_000.0
        }
        lastSampleNanos = now

        byteLock.lock()
        let h = hBytesWindow
        let v = vBytesWindow
        hBytesWindow = 0
        vBytesWindow = 0
        byteLock.unlock()

        let hBps = dt > 0 ? Int(Double(h * 8) / dt) : 0
        let vBps = dt > 0 ? Int(Double(v * 8) / dt) : 0

        let hSnap = horizontalPublisher?.snapshot()
        let vSnap = verticalPublisher?.snapshot()

        let payload: [String: Any] = [
            "bitrateA": isLive ? hBps : 0,
            "bitrateB": isLive ? vBps : 0,
            "fps": isLive ? Double(currentFps) : 0.0,
            "droppedFrames": 0,
            "thermalStatus": currentThermalStatus(),
            "srtRtt": 0.0,
            "srtLoss": 0.0,
            "txDatagramsA": hSnap?.datagrams ?? 0,
            "txBytesA": hSnap?.bytes ?? 0,
            "txErrorsA": hSnap?.errors ?? 0,
            "txDatagramsB": vSnap?.datagrams ?? 0,
            "txBytesB": vSnap?.bytes ?? 0,
            "txErrorsB": vSnap?.errors ?? 0,
            "timestampMs": Int(Date().timeIntervalSince1970 * 1000),
        ]
        sink(payload)
    }

    private func currentThermalStatus() -> Int {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return 0
        case .fair: return 2
        case .serious: return 3
        case .critical: return 4
        @unknown default: return 0
        }
    }

    private func defaultBackCameraId() -> String? {
        return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)?.uniqueID
            ?? AVCaptureDevice.default(for: .video)?.uniqueID
    }

    private static func localWifiIp() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        let preferred = ["en0", "en1"]
        var fallback: String?
        var node: UnsafeMutablePointer<ifaddrs>? = first
        while let cur = node {
            defer { node = cur.pointee.ifa_next }
            guard let saPtr = cur.pointee.ifa_addr else { continue }
            let family = saPtr.pointee.sa_family
            guard family == sa_family_t(AF_INET) else { continue }

            let flags = Int32(cur.pointee.ifa_flags)
            guard (flags & IFF_UP) != 0, (flags & IFF_LOOPBACK) == 0 else { continue }

            let name = String(cString: cur.pointee.ifa_name)
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                saPtr,
                socklen_t(saPtr.pointee.sa_len),
                &host,
                socklen_t(host.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            guard result == 0 else { continue }
            let ip = String(cString: host)
            if preferred.contains(name) { return ip }
            if fallback == nil { fallback = ip }
        }
        return fallback
    }
}
