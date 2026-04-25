package br.com.wanmind.livegrid

import android.content.Context
import android.content.Intent
import android.graphics.ImageFormat
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.util.Log
import android.util.Size
import androidx.annotation.RequiresApi
import br.com.wanmind.livegrid.camera.CapturePipeline
import br.com.wanmind.livegrid.encoder.HardwareEncoder
import br.com.wanmind.livegrid.service.LiveGridForegroundService
import br.com.wanmind.livegrid.stream.UdpPublisher
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry
import java.io.File

class FlutterBridge(
    private val context: Context,
    flutterEngine: FlutterEngine,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    private val control = MethodChannel(
        flutterEngine.dartExecutor.binaryMessenger,
        "livegrid/control",
    )

    private val stats = EventChannel(
        flutterEngine.dartExecutor.binaryMessenger,
        "livegrid/stats",
    )

    private val textureRegistry: TextureRegistry = flutterEngine.renderer
    private val recordingsDir: File = resolveRecordingsDir()
    private val pipeline = CapturePipeline(context, textureRegistry, recordingsDir)

    private var eventSink: EventChannel.EventSink? = null
    private val handler = Handler(Looper.getMainLooper())
    private var statsRunning = false
    private var live = false
    private var lastThermalLogged = -1

    private var activeCameraId: String? = null

    init {
        control.setMethodCallHandler(this)
        stats.setStreamHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "init" -> handleInit(result)
            "listCameras" -> result.success(listCameras())
            "startCapture" -> handleStart(call, result)
            "stop" -> {
                live = false
                pipeline.stopRecording()
                stopForegroundService()
                result.success(null)
            }
            "switchResolution" -> result.success(null)
            "setBitrate" -> {
                call.argument<Int>("horizontalBps")?.let { pipeline.setHorizontalBitrate(it) }
                call.argument<Int>("verticalBps")?.let { pipeline.setVerticalBitrate(it) }
                result.success(null)
            }
            "requestKeyframe" -> {
                pipeline.requestKeyframes()
                result.success(null)
            }
            "setVerticalCrop" -> {
                val x = (call.argument<Any>("centerX") as? Number)?.toFloat()
                if (x != null) pipeline.setVerticalCropCenter(x)
                result.success(null)
            }
            "wifiBand" -> result.success(currentWifiBand())
            else -> result.notImplemented()
        }
    }

    private fun handleInit(result: MethodChannel.Result) {
        val textureId = pipeline.prepareTexture()
        val cameraId = defaultBackCameraId() ?: run {
            Log.w(TAG, "nenhuma câmera traseira encontrada")
            result.success(textureId)
            return
        }
        activeCameraId = cameraId
        pipeline.startPreview(
            cameraId = cameraId,
            previewWidth = PREVIEW_WIDTH,
            previewHeight = PREVIEW_HEIGHT,
            onError = { msg -> Log.w(TAG, "preview error: $msg") },
        )
        result.success(textureId)
    }

    private fun handleStart(call: MethodCall, result: MethodChannel.Result) {
        val profile = call.argument<Map<String, Any>>("profile")
        val network = call.argument<Map<String, Any?>>("network")
        val cameraId = profile?.get("cameraId") as? String
        val captureMap = profile?.get("capture") as? Map<*, *>
        val captureW = (captureMap?.get("width") as? Number)?.toInt()
        val captureH = (captureMap?.get("height") as? Number)?.toInt()

        val cameraChanged = !cameraId.isNullOrBlank() && cameraId != activeCameraId
        val captureChanged = (captureW != null && captureW != pipeline.captureWidth) ||
            (captureH != null && captureH != pipeline.captureHeight)

        if (cameraChanged || captureChanged) {
            pipeline.stopAll()
            if (!cameraId.isNullOrBlank()) activeCameraId = cameraId
            pipeline.startPreview(
                cameraId = activeCameraId,
                previewWidth = PREVIEW_WIDTH,
                previewHeight = PREVIEW_HEIGHT,
                captureWidth = captureW,
                captureHeight = captureH,
                onError = { msg -> Log.w(TAG, "preview error: $msg") },
            )
        }

        val hProfile = extractProfile(profile?.get("horizontal") as? Map<*, *>, "H")
            ?: return result.error("bad_profile", "horizontal inválido", null)
        val vProfile = extractProfile(profile?.get("vertical") as? Map<*, *>, "V")
            ?: return result.error("bad_profile", "vertical inválido", null)

        val cropCenterX = (profile?.get("verticalCropCenterX") as? Number)?.toFloat() ?: 0.5f
        pipeline.setVerticalCropCenter(cropCenterX)

        val obsHost = (network?.get("obsHost") as? String)?.trim().orEmpty()
        val hPort = (network?.get("horizontalPort") as? Number)?.toInt() ?: 9000
        val vPort = (network?.get("verticalPort") as? Number)?.toInt() ?: 9001
        val hPub = if (obsHost.isNotEmpty()) UdpPublisher(obsHost, hPort, "H") else null
        val vPub = if (obsHost.isNotEmpty()) UdpPublisher(obsHost, vPort, "V") else null

        val recordToDisk = (profile?.get("recordToDisk") as? Boolean) ?: false
        startForegroundService()
        val output = pipeline.startRecording(
            horizontalProfile = hProfile,
            verticalProfile = vProfile,
            horizontalPublisher = hPub,
            verticalPublisher = vPub,
            recordToDisk = recordToDisk,
        ) { msg ->
            handler.post {
                live = false
                stopForegroundService()
            }
            result.error("start_failed", msg, null)
        }
        if (output != null) {
            live = true
            Log.i(TAG, "recording files=${output.horizontalFile} udp=${obsHost}:$hPort/$vPort")
            result.success(
                mapOf(
                    "horizontalFile" to output.horizontalFile?.absolutePath,
                    "verticalFile" to output.verticalFile?.absolutePath,
                    "horizontalUrl" to if (obsHost.isNotEmpty()) "udp://$obsHost:$hPort" else null,
                    "verticalUrl" to if (obsHost.isNotEmpty()) "udp://$obsHost:$vPort" else null,
                )
            )
        }
    }

    private fun extractProfile(raw: Map<*, *>?, label: String): HardwareEncoder.Profile? {
        raw ?: return null
        val w = (raw["width"] as? Number)?.toInt() ?: return null
        val h = (raw["height"] as? Number)?.toInt() ?: return null
        val fps = (raw["fps"] as? Number)?.toInt() ?: 30
        val bps = (raw["bitrateBps"] as? Number)?.toInt() ?: 6_000_000
        val gop = (raw["gop"] as? Number)?.toInt() ?: fps
        return HardwareEncoder.Profile(w, h, fps, bps, gop, label)
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        if (!statsRunning) {
            statsRunning = true
            handler.post(statsTicker)
        }
    }

    override fun onCancel(arguments: Any?) {
        statsRunning = false
        eventSink = null
        handler.removeCallbacks(statsTicker)
    }

    private val statsTicker = object : Runnable {
        override fun run() {
            if (!statsRunning) return
            val hBps = if (live) pipeline.horizontalBitrate() else 0
            val vBps = if (live) pipeline.verticalBitrate() else 0
            val hSnap = if (live) pipeline.horizontalPublisherSnapshot() else null
            val vSnap = if (live) pipeline.verticalPublisherSnapshot() else null
            val thermal = currentThermalStatus()
            if (thermal != lastThermalLogged) {
                Log.i(TAG, "thermalStatus: $lastThermalLogged -> $thermal")
                lastThermalLogged = thermal
            }
            val payload = mapOf<String, Any>(
                "bitrateA" to hBps,
                "bitrateB" to vBps,
                "fps" to if (live) 30.0 else 0.0,
                "droppedFrames" to 0,
                "thermalStatus" to thermal,
                "srtRtt" to 0.0,
                "srtLoss" to 0.0,
                "txDatagramsA" to (hSnap?.datagrams ?: 0L),
                "txBytesA" to (hSnap?.bytes ?: 0L),
                "txErrorsA" to (hSnap?.errors ?: 0L),
                "txDatagramsB" to (vSnap?.datagrams ?: 0L),
                "txBytesB" to (vSnap?.bytes ?: 0L),
                "txErrorsB" to (vSnap?.errors ?: 0L),
                "timestampMs" to System.currentTimeMillis(),
            )
            eventSink?.success(payload)
            handler.postDelayed(this, STATS_INTERVAL_MS)
        }
    }

    private fun startForegroundService() {
        val intent = Intent(context, LiveGridForegroundService::class.java)
        context.startForegroundService(intent)
    }

    private fun stopForegroundService() {
        val intent = Intent(context, LiveGridForegroundService::class.java)
        context.stopService(intent)
    }

    private fun currentThermalStatus(): Int {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) readThermalStatusQ() else 0
    }

    @RequiresApi(Build.VERSION_CODES.Q)
    private fun readThermalStatusQ(): Int {
        val pm = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
        return pm?.currentThermalStatus ?: 0
    }

    private fun defaultBackCameraId(): String? {
        val manager = context.getSystemService(Context.CAMERA_SERVICE) as? CameraManager
            ?: return null
        return manager.cameraIdList.firstOrNull { id ->
            val chars = manager.getCameraCharacteristics(id)
            chars.get(CameraCharacteristics.LENS_FACING) == CameraCharacteristics.LENS_FACING_BACK
        } ?: manager.cameraIdList.firstOrNull()
    }

    private fun listCameras(): List<Map<String, Any?>> {
        val manager = context.getSystemService(Context.CAMERA_SERVICE) as? CameraManager
            ?: return emptyList()
        return manager.cameraIdList.mapNotNull { id ->
            try {
                val chars = manager.getCameraCharacteristics(id)
                val facing = chars.get(CameraCharacteristics.LENS_FACING)
                val lens = when (facing) {
                    CameraCharacteristics.LENS_FACING_BACK -> "back"
                    CameraCharacteristics.LENS_FACING_FRONT -> "front"
                    CameraCharacteristics.LENS_FACING_EXTERNAL -> "external"
                    else -> "unknown"
                }
                val map = chars.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
                val largest: Size? = map?.getOutputSizes(ImageFormat.YUV_420_888)
                    ?.maxByOrNull { it.width.toLong() * it.height }
                val focalLengths = chars.get(CameraCharacteristics.LENS_INFO_AVAILABLE_FOCAL_LENGTHS)
                val focalLabel = focalLengths?.firstOrNull()?.let { "${"%.1f".format(it)}mm" } ?: ""
                mapOf(
                    "id" to id,
                    "lens" to lens,
                    "label" to focalLabel,
                    "maxWidth" to (largest?.width ?: 0),
                    "maxHeight" to (largest?.height ?: 0),
                )
            } catch (_: Throwable) {
                null
            }
        }
    }

    private fun currentWifiBand(): String {
        val wifi = context.applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
        val info = wifi?.connectionInfo ?: return "unknown"
        val freq = info.frequency
        return when {
            freq in 2400..2500 -> "2.4"
            freq in 4900..5900 -> "5"
            else -> "unknown"
        }
    }

    private fun resolveRecordingsDir(): File {
        val ext = context.getExternalFilesDir(null)
        val dir = if (ext != null) File(ext, "recordings") else File(context.filesDir, "recordings")
        if (!dir.exists()) dir.mkdirs()
        return dir
    }

    fun detach() {
        onCancel(null)
        pipeline.releaseTexture()
        stopForegroundService()
        control.setMethodCallHandler(null)
        stats.setStreamHandler(null)
    }

    companion object {
        private const val TAG = "FlutterBridge"
        private const val STATS_INTERVAL_MS = 500L
        private const val PREVIEW_WIDTH = 1920
        private const val PREVIEW_HEIGHT = 1080
    }
}
