package br.com.wanmind.livegrid.camera

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.SurfaceTexture
import android.hardware.camera2.CameraCaptureSession
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraDevice
import android.hardware.camera2.CameraManager
import android.hardware.camera2.CameraMetadata
import android.hardware.camera2.CaptureRequest
import android.os.Handler
import android.os.HandlerThread
import android.util.Log
import android.util.Range
import android.util.Size
import android.view.Surface

class OpenGateCamera(private val context: Context) {

    data class OpenResult(
        val width: Int,
        val height: Int,
        val sensorOrientation: Int,
        val hasFlash: Boolean,
        val exposureMin: Int,
        val exposureMax: Int,
        val exposureStepEv: Double,
    )

    private val manager: CameraManager =
        context.getSystemService(Context.CAMERA_SERVICE) as CameraManager

    private val thread = HandlerThread("livegrid-cam").apply { start() }
    private val handler = Handler(thread.looper)

    private var device: CameraDevice? = null
    private var session: CameraCaptureSession? = null
    private var requestBuilder: CaptureRequest.Builder? = null
    private var availableFpsRanges: Array<Range<Int>> = emptyArray()

    @SuppressLint("MissingPermission")
    fun open(
        cameraId: String,
        outputs: List<Surface>,
        targetWidth: Int? = null,
        targetHeight: Int? = null,
        onSizeChosen: (Int, Int) -> Unit = { _, _ -> },
        onReady: (OpenResult) -> Unit,
        onError: (String) -> Unit,
    ) {
        try {
            val chars = manager.getCameraCharacteristics(cameraId)
            val configMap = chars.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
                ?: return onError("no SCALER_STREAM_CONFIGURATION_MAP")

            val sizes = configMap.getOutputSizes(SurfaceTexture::class.java) ?: emptyArray()
            val usable = sizes.filter { supportsFps(configMap, it, MIN_CAPTURE_FPS) }
            val best = pickSize(usable.ifEmpty { sizes.toList() }, targetHeight) ?: return onError("no size")
            availableFpsRanges =
                chars.get(CameraCharacteristics.CONTROL_AE_AVAILABLE_TARGET_FPS_RANGES) ?: emptyArray()
            val sensorOrientation = chars.get(CameraCharacteristics.SENSOR_ORIENTATION) ?: 0
            val hasFlash = chars.get(CameraCharacteristics.FLASH_INFO_AVAILABLE) ?: false
            val expRange = chars.get(CameraCharacteristics.CONTROL_AE_COMPENSATION_RANGE)
            val expStep = chars.get(CameraCharacteristics.CONTROL_AE_COMPENSATION_STEP)
            val exposureMin = expRange?.lower ?: 0
            val exposureMax = expRange?.upper ?: 0
            val exposureStepEv = expStep?.toDouble() ?: 0.0
            Log.i(TAG, "cam=$cameraId size=${best.width}x${best.height} target=${targetWidth}x${targetHeight} sensor=$sensorOrientation flash=$hasFlash ev=[$exposureMin,$exposureMax]*$exposureStepEv")
            onSizeChosen(best.width, best.height)

            manager.openCamera(cameraId, object : CameraDevice.StateCallback() {
                override fun onOpened(camera: CameraDevice) {
                    device = camera
                    createSession(
                        camera,
                        outputs,
                        best,
                        sensorOrientation,
                        hasFlash,
                        exposureMin,
                        exposureMax,
                        exposureStepEv,
                        onReady,
                        onError,
                    )
                }

                override fun onDisconnected(camera: CameraDevice) {
                    camera.close()
                    device = null
                }

                override fun onError(camera: CameraDevice, error: Int) {
                    camera.close()
                    device = null
                    onError("camera onError $error")
                }
            }, handler)
        } catch (t: Throwable) {
            onError("open throw: ${t.message}")
        }
    }

    private fun createSession(
        camera: CameraDevice,
        outputs: List<Surface>,
        size: Size,
        sensorOrientation: Int,
        hasFlash: Boolean,
        exposureMin: Int,
        exposureMax: Int,
        exposureStepEv: Double,
        onReady: (OpenResult) -> Unit,
        onError: (String) -> Unit,
    ) {
        val cb = object : CameraCaptureSession.StateCallback() {
            override fun onConfigured(s: CameraCaptureSession) {
                session = s
                val builder = camera.createCaptureRequest(CameraDevice.TEMPLATE_RECORD).apply {
                    outputs.forEach(::addTarget)
                    set(CaptureRequest.CONTROL_MODE, CameraMetadata.CONTROL_MODE_AUTO)
                    set(CaptureRequest.CONTROL_AF_MODE, CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_VIDEO)
                    set(CaptureRequest.CONTROL_AE_MODE, CaptureRequest.CONTROL_AE_MODE_ON)
                    set(
                        CaptureRequest.CONTROL_VIDEO_STABILIZATION_MODE,
                        CaptureRequest.CONTROL_VIDEO_STABILIZATION_MODE_OFF,
                    )
                    set(
                        CaptureRequest.LENS_OPTICAL_STABILIZATION_MODE,
                        CaptureRequest.LENS_OPTICAL_STABILIZATION_MODE_OFF,
                    )
                }
                requestBuilder = builder
                try {
                    s.setRepeatingRequest(builder.build(), null, handler)
                    onReady(
                        OpenResult(
                            size.width,
                            size.height,
                            sensorOrientation,
                            hasFlash,
                            exposureMin,
                            exposureMax,
                            exposureStepEv,
                        ),
                    )
                } catch (t: Throwable) {
                    onError("setRepeatingRequest: ${t.message}")
                }
            }

            override fun onConfigureFailed(s: CameraCaptureSession) {
                onError("session onConfigureFailed")
            }
        }

        @Suppress("DEPRECATION")
        camera.createCaptureSession(outputs, cb, handler)
    }

    fun setTorch(enabled: Boolean) {
        val builder = requestBuilder ?: return
        val s = session ?: return
        try {
            builder.set(
                CaptureRequest.FLASH_MODE,
                if (enabled) CaptureRequest.FLASH_MODE_TORCH else CaptureRequest.FLASH_MODE_OFF,
            )
            s.setRepeatingRequest(builder.build(), null, handler)
        } catch (t: Throwable) {
            Log.w(TAG, "setTorch: ${t.message}")
        }
    }

    fun setExposureCompensation(value: Int) {
        val builder = requestBuilder ?: return
        val s = session ?: return
        try {
            builder.set(CaptureRequest.CONTROL_AE_EXPOSURE_COMPENSATION, value)
            s.setRepeatingRequest(builder.build(), null, handler)
        } catch (t: Throwable) {
            Log.w(TAG, "setExposureCompensation: ${t.message}")
        }
    }

    fun setTargetFps(fps: Int) {
        val builder = requestBuilder ?: return
        val s = session ?: return
        val range = pickFpsRange(fps) ?: run {
            Log.w(TAG, "setTargetFps: $fps fora de ${availableFpsRanges.joinToString()}")
            return
        }
        try {
            builder.set(CaptureRequest.CONTROL_AE_TARGET_FPS_RANGE, range)
            s.setRepeatingRequest(builder.build(), null, handler)
        } catch (t: Throwable) {
            Log.w(TAG, "setTargetFps: ${t.message}")
        }
    }

    fun stop() {
        try {
            session?.close()
            device?.close()
        } catch (t: Throwable) {
            Log.w(TAG, "stop: ${t.message}")
        }
        session = null
        device = null
        requestBuilder = null
    }

    fun release() {
        stop()
        thread.quitSafely()
    }

    private fun pickFpsRange(fps: Int): Range<Int>? {
        if (availableFpsRanges.isEmpty()) return Range(fps, fps)
        availableFpsRanges.firstOrNull { it.lower == fps && it.upper == fps }?.let { return it }
        return availableFpsRanges
            .filter { it.upper == fps }
            .maxByOrNull { it.lower }
    }

    private fun supportsFps(
        map: android.hardware.camera2.params.StreamConfigurationMap,
        size: Size,
        fps: Int,
    ): Boolean {
        val minDurationNs = try {
            map.getOutputMinFrameDuration(SurfaceTexture::class.java, size)
        } catch (_: Throwable) {
            0L
        }
        return minDurationNs <= 0L || minDurationNs <= 1_000_000_000L / fps
    }

    /**
     * Open gate: sempre 4:3 (área total do sensor). Os crops 16:9 e 9:16 saem
     * do GlRenderer. O tier do Dart (altura 16:9 pedida) vira a altura mínima
     * de sensor que entrega o vertical 9:16 sem upscale: alturaSensor * 9/16
     * >= alturaPedida. Tier >= 2160 ("Qualidade") usa o maior 4:3 disponível.
     */
    private fun pickSize(sizes: List<Size>, targetH: Int?): Size? {
        val valid = sizes.filter { it.width > 0 && it.height > 0 }
        if (valid.isEmpty()) return null
        val fourByThree = valid.filter { is4x3(it.width, it.height) }
            .sortedBy { it.width.toLong() * it.height }
        val largest = fourByThree.lastOrNull() ?: return valid.maxByOrNull { it.width.toLong() * it.height }
        if (targetH == null || targetH >= FULL_SENSOR_TIER_HEIGHT) return largest
        val minSensorHeight = targetH * 16 / 9
        return fourByThree.firstOrNull { it.height >= minSensorHeight } ?: largest
    }

    private fun is4x3(w: Int, h: Int): Boolean {
        val ratio = w.toFloat() / h.toFloat()
        return kotlin.math.abs(ratio - 4f / 3f) < 0.02f
    }

    companion object {
        private const val TAG = "OpenGateCamera"
        private const val MIN_CAPTURE_FPS = 30
        private const val FULL_SENSOR_TIER_HEIGHT = 2160
    }
}
