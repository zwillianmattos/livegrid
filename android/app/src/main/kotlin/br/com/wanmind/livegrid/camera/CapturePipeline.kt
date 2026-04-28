package br.com.wanmind.livegrid.camera

import android.content.Context
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.util.Log
import android.view.Surface
import android.view.WindowManager
import br.com.wanmind.livegrid.encoder.EncoderPool
import br.com.wanmind.livegrid.encoder.HardwareEncoder
import br.com.wanmind.livegrid.stream.TcpPublisher
import io.flutter.view.TextureRegistry
import java.io.File
import java.util.concurrent.atomic.AtomicBoolean

class CapturePipeline(
    private val context: Context,
    private val textureRegistry: TextureRegistry,
    private val recordingsDir: File,
) {

    private var textureEntry: TextureRegistry.SurfaceTextureEntry? = null
    private var core: GlCore? = null
    private var renderer: GlRenderer? = null
    private var camera: OpenGateCamera? = null
    private var previewTarget: GlRenderer.Target? = null
    private var previewSurface: Surface? = null

    private val encoderPool = EncoderPool(recordingsDir)

    private val previewRunning = AtomicBoolean(false)

    val textureId: Long? get() = textureEntry?.id()

    fun prepareTexture(): Long {
        val entry = textureEntry ?: textureRegistry.createSurfaceTexture().also { textureEntry = it }
        return entry.id()
    }

    var captureWidth: Int? = null
        private set
    var captureHeight: Int? = null
        private set

    fun startPreview(
        cameraId: String?,
        previewWidth: Int,
        previewHeight: Int,
        captureWidth: Int? = null,
        captureHeight: Int? = null,
        onError: (String) -> Unit,
    ) {
        if (previewRunning.getAndSet(true)) return
        val entry = textureEntry ?: textureRegistry.createSurfaceTexture().also { textureEntry = it }
        val surfaceTexture = entry.surfaceTexture()
        surfaceTexture.setDefaultBufferSize(previewWidth, previewHeight)
        val target = Surface(surfaceTexture)
        previewSurface = target

        val c = GlCore()
        core = c
        val r = GlRenderer(c)
        renderer = r
        val resolved = resolveCameraId(cameraId)
        this.captureWidth = captureWidth
        this.captureHeight = captureHeight

        val displayRotation = queryDisplayRotationDegrees()
        r.setup { inputSurface ->
            previewTarget = r.addTarget(target, previewWidth, previewHeight, GlRenderer.CROP_FULL)
            camera = OpenGateCamera(context).also { cam ->
                cam.open(
                    cameraId = resolved,
                    outputs = listOf(inputSurface),
                    targetWidth = captureWidth,
                    targetHeight = captureHeight,
                    onSizeChosen = { w, h -> r.setInputBufferSize(w, h) },
                    onReady = { res ->
                        r.configureInputSize(
                            width = res.width,
                            height = res.height,
                            sensorOrientation = res.sensorOrientation,
                            displayRotation = displayRotation,
                        )
                        Log.i(
                            TAG,
                            "preview $resolved ${res.width}x${res.height} sensor=${res.sensorOrientation} display=$displayRotation",
                        )
                    },
                    onError = { msg ->
                        previewRunning.set(false)
                        onError(msg)
                    },
                )
            }
        }
    }

    fun startRecording(
        horizontalProfile: HardwareEncoder.Profile?,
        verticalProfile: HardwareEncoder.Profile?,
        horizontalPublisher: TcpPublisher? = null,
        verticalPublisher: TcpPublisher? = null,
        recordToDisk: Boolean = true,
        onError: (String) -> Unit,
    ): EncoderPool.Output? {
        val r = renderer ?: run {
            onError("pipeline não iniciado")
            return null
        }
        return try {
            encoderPool.start(
                horizontalProfile,
                verticalProfile,
                r,
                EncoderPool.Publishers(horizontalPublisher, verticalPublisher),
                recordToDisk,
            )
        } catch (t: Throwable) {
            onError("recording: ${t.message}")
            null
        }
    }

    fun stopRecording() {
        renderer?.let { encoderPool.stop(it) }
    }

    fun setHorizontalBitrate(bps: Int) = encoderPool.setHorizontalBitrate(bps)
    fun setVerticalBitrate(bps: Int) = encoderPool.setVerticalBitrate(bps)
    fun setFrameRate(fps: Int) = encoderPool.setFrameRate(fps)
    fun setVerticalCropCenter(value: Float) {
        renderer?.setVerticalCropCenter(value)
    }
    fun requestKeyframes() = encoderPool.requestKeyframes()
    fun horizontalBitrate(): Int = encoderPool.horizontalBitrate()
    fun verticalBitrate(): Int = encoderPool.verticalBitrate()
    fun currentFps(): Int = encoderPool.currentFps()
    fun horizontalPublisherSnapshot(): TcpPublisher.Snapshot? =
        encoderPool.horizontalPublisherSnapshot()
    fun verticalPublisherSnapshot(): TcpPublisher.Snapshot? =
        encoderPool.verticalPublisherSnapshot()
    val isRecording: Boolean get() = encoderPool.isRunning

    fun stopAll() {
        stopRecording()
        previewTarget?.let { renderer?.removeTarget(it) }
        previewTarget = null
        camera?.release()
        camera = null
        renderer?.release()
        renderer = null
        core?.release()
        core = null
        previewSurface?.release()
        previewSurface = null
        previewRunning.set(false)
    }

    fun releaseTexture() {
        stopAll()
        textureEntry?.release()
        textureEntry = null
    }

    @Suppress("DEPRECATION")
    private fun queryDisplayRotationDegrees(): Int {
        val wm = context.getSystemService(Context.WINDOW_SERVICE) as? WindowManager
        val rotation = wm?.defaultDisplay?.rotation ?: Surface.ROTATION_0
        return when (rotation) {
            Surface.ROTATION_0 -> 0
            Surface.ROTATION_90 -> 90
            Surface.ROTATION_180 -> 180
            Surface.ROTATION_270 -> 270
            else -> 0
        }
    }

    private fun resolveCameraId(requested: String?): String {
        val manager = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
        val available = manager.cameraIdList
        if (!requested.isNullOrBlank() && available.contains(requested)) return requested
        return available.firstOrNull { id ->
            val chars = manager.getCameraCharacteristics(id)
            chars.get(CameraCharacteristics.LENS_FACING) == CameraCharacteristics.LENS_FACING_BACK
        } ?: available.first()
    }

    companion object {
        private const val TAG = "CapturePipeline"
    }
}
