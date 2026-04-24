import AVFoundation
import Flutter
import Foundation
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
    private var horizontalPublisher: UdpPublisher?
    private var verticalPublisher: UdpPublisher?

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
        stopEncoders()
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
            stopEncoders()
            result(nil)
        case "switchResolution":
            result(nil)
        case "setBitrate":
            if let args = call.arguments as? [String: Any] {
                if let h = args["horizontalBps"] as? Int { horizontalEncoder?.setBitrate(h) }
                if let v = args["verticalBps"] as? Int { verticalEncoder?.setBitrate(v) }
            }
            result(nil)
        case "requestKeyframe":
            horizontalEncoder?.requestKeyframe()
            verticalEncoder?.requestKeyframe()
            result(nil)
        case "wifiBand":
            result("unknown")
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

        if let cameraId = profile["cameraId"] as? String,
           !cameraId.isEmpty,
           cameraId != activeCameraId,
           let p = preview {
            activeCameraId = cameraId
            do { try p.start(cameraId: cameraId) } catch {
                NSLog("switch camera failed: \(error.localizedDescription)")
            }
        }

        guard let hMap = profile["horizontal"] as? [String: Any],
              let vMap = profile["vertical"] as? [String: Any] else {
            result(FlutterError(code: "bad_profile", message: "perfis ausentes", details: nil))
            return
        }
        let hW = (hMap["width"] as? Int) ?? 1920
        let hH = (hMap["height"] as? Int) ?? 1080
        let hFps = (hMap["fps"] as? Int) ?? 30
        let hBps = (hMap["bitrateBps"] as? Int) ?? 6_000_000
        let hGop = (hMap["gop"] as? Int) ?? hFps
        let vW = (vMap["width"] as? Int) ?? 1080
        let vH = (vMap["height"] as? Int) ?? 1920
        let vFps = (vMap["fps"] as? Int) ?? 30
        let vBps = (vMap["bitrateBps"] as? Int) ?? 5_000_000
        let vGop = (vMap["gop"] as? Int) ?? vFps

        let obsHost = ((network?["obsHost"] as? String) ?? "").trimmingCharacters(in: .whitespaces)
        let hPort = (network?["horizontalPort"] as? Int) ?? 9000
        let vPort = (network?["verticalPort"] as? Int) ?? 9001

        let hPub = obsHost.isEmpty ? nil : UdpPublisher(host: obsHost, port: hPort, label: "H")
        let vPub = obsHost.isEmpty ? nil : UdpPublisher(host: obsHost, port: vPort, label: "V")
        hPub?.open()
        vPub?.open()
        horizontalPublisher = hPub
        verticalPublisher = vPub

        let hEnc = VideoEncoder(width: hW, height: hH, fps: hFps, gop: hGop, bitrate: hBps, label: "H")
        let vEnc = VideoEncoder(width: vW, height: vH, fps: vFps, gop: vGop, bitrate: vBps, label: "V")

        hEnc.onEncoded = { [weak self] f in
            self?.horizontalPublisher?.publish(annexB: f.data, ptsUs: f.ptsUs, isKeyframe: f.isKeyframe)
        }
        hEnc.onBytes = { [weak self] n in
            self?.byteLock.lock(); self?.hBytesWindow += n; self?.byteLock.unlock()
        }
        vEnc.onEncoded = { [weak self] f in
            self?.verticalPublisher?.publish(annexB: f.data, ptsUs: f.ptsUs, isKeyframe: f.isKeyframe)
        }
        vEnc.onBytes = { [weak self] n in
            self?.byteLock.lock(); self?.vBytesWindow += n; self?.byteLock.unlock()
        }

        do {
            try hEnc.start()
            try vEnc.start()
        } catch {
            hPub?.close(); vPub?.close()
            horizontalPublisher = nil; verticalPublisher = nil
            result(FlutterError(code: "encoder", message: error.localizedDescription, details: nil))
            return
        }
        horizontalEncoder = hEnc
        verticalEncoder = vEnc
        preview?.setEncoders(horizontal: hEnc, vertical: vEnc)

        isLive = true
        var payload: [String: Any] = [:]
        if !obsHost.isEmpty {
            payload["horizontalUrl"] = "udp://\(obsHost):\(hPort)"
            payload["verticalUrl"] = "udp://\(obsHost):\(vPort)"
        }
        result(payload)
    }

    private func stopEncoders() {
        preview?.setEncoders(horizontal: nil, vertical: nil)
        horizontalEncoder?.stop()
        verticalEncoder?.stop()
        horizontalEncoder = nil
        verticalEncoder = nil
        horizontalPublisher?.close()
        verticalPublisher?.close()
        horizontalPublisher = nil
        verticalPublisher = nil
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

        let payload: [String: Any] = [
            "bitrateA": isLive ? hBps : 0,
            "bitrateB": isLive ? vBps : 0,
            "fps": isLive ? 30.0 : 0.0,
            "droppedFrames": 0,
            "thermalStatus": currentThermalStatus(),
            "srtRtt": 0.0,
            "srtLoss": 0.0,
            "timestampMs": Int(Date().timeIntervalSince1970 * 1000),
        ]
        sink(payload)
    }

    private func currentThermalStatus() -> Int {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return 0
        case .fair: return 1
        case .serious: return 3
        case .critical: return 4
        @unknown default: return 0
        }
    }

    private func defaultBackCameraId() -> String? {
        return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)?.uniqueID
            ?? AVCaptureDevice.default(for: .video)?.uniqueID
    }
}
