package br.com.wanmind.livegrid.camera

import android.content.Context
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.util.Log
import android.view.Surface
import br.com.wanmind.livegrid.encoder.EncoderPool
import br.com.wanmind.livegrid.encoder.HardwareEncoder
import br.com.wanmind.livegrid.stream.UdpPublisher
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

    fun startPreview(
        cameraId: String?,
        previewWidth: Int,
        previewHeight: Int,
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

        r.setup { inputSurface ->
            previewTarget = r.addTarget(target, previewWidth, previewHeight, GlRenderer.CROP_FULL)
            camera = OpenGateCamera(context).also { cam ->
                cam.open(
                    cameraId = resolved,
                    outputs = listOf(inputSurface),
                    onReady = { res ->
                        r.configureInputSize(res.width, res.height)
                        Log.i(TAG, "preview $resolved ${res.width}x${res.height}")
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
        horizontalProfile: HardwareEncoder.Profile,
        verticalProfile: HardwareEncoder.Profile,
        horizontalPublisher: UdpPublisher? = null,
        verticalPublisher: UdpPublisher? = null,
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
    fun requestKeyframes() = encoderPool.requestKeyframes()
    fun horizontalBitrate(): Int = encoderPool.horizontalBitrate()
    fun verticalBitrate(): Int = encoderPool.verticalBitrate()
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
