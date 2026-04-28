package br.com.wanmind.livegrid.encoder

import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.HandlerThread
import android.util.Log
import android.view.Surface
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.atomic.AtomicBoolean

class HardwareEncoder(
    private val profile: Profile,
    private val outputFile: File?,
    val bitrateMeter: BitrateMeter = BitrateMeter(),
    private val onFrame: ((ByteArray, Long, Int) -> Unit)? = null,
) {

    data class Profile(
        val width: Int,
        val height: Int,
        val fps: Int,
        val bitrateBps: Int,
        val gop: Int,
        val label: String,
    )

    private var codec: MediaCodec? = null
    private var inputSurface: Surface? = null
    private var fos: FileOutputStream? = null
    private val thread = HandlerThread("enc-${profile.label}").apply { start() }
    private val handler = Handler(thread.looper)
    private val running = AtomicBoolean(false)
    private var currentBitrate = profile.bitrateBps
    private var currentFps = profile.fps

    fun start(): Surface {
        val c = MediaCodec.createEncoderByType(MIME)
        codec = c
        val format = MediaFormat.createVideoFormat(MIME, profile.width, profile.height).apply {
            setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface)
            setInteger(MediaFormat.KEY_BIT_RATE, profile.bitrateBps)
            setInteger(MediaFormat.KEY_FRAME_RATE, profile.fps)
            setFloat(MediaFormat.KEY_I_FRAME_INTERVAL, profile.gop.toFloat() / profile.fps)
            setInteger(
                MediaFormat.KEY_BITRATE_MODE,
                MediaCodecInfo.EncoderCapabilities.BITRATE_MODE_CBR,
            )
            setInteger(
                MediaFormat.KEY_PROFILE,
                MediaCodecInfo.CodecProfileLevel.AVCProfileMain,
            )
            setInteger(
                MediaFormat.KEY_LEVEL,
                MediaCodecInfo.CodecProfileLevel.AVCLevel41,
            )
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                setInteger(MediaFormat.KEY_COLOR_STANDARD, MediaFormat.COLOR_STANDARD_BT709)
                setInteger(MediaFormat.KEY_COLOR_RANGE, MediaFormat.COLOR_RANGE_LIMITED)
                setInteger(MediaFormat.KEY_COLOR_TRANSFER, MediaFormat.COLOR_TRANSFER_SDR_VIDEO)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                setInteger(MediaFormat.KEY_MAX_B_FRAMES, 0)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
                setInteger(MediaFormat.KEY_LATENCY, 1)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                setInteger(MediaFormat.KEY_PRIORITY, 0)
            }
        }
        c.setCallback(callback, handler)
        try {
            c.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
        } catch (t: Throwable) {
            Log.w(TAG, "configure Main falhou (${t.message}); fallback Baseline")
            format.setInteger(
                MediaFormat.KEY_PROFILE,
                MediaCodecInfo.CodecProfileLevel.AVCProfileBaseline,
            )
            format.setInteger(
                MediaFormat.KEY_LEVEL,
                MediaCodecInfo.CodecProfileLevel.AVCLevel4,
            )
            c.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
        }
        val surface = c.createInputSurface()
        inputSurface = surface
        fos = outputFile?.let { FileOutputStream(it) }
        c.start()
        running.set(true)
        Log.i(
            TAG,
            "encoder ${profile.label} ${profile.width}x${profile.height}@${profile.fps} bps=${profile.bitrateBps} gop=${profile.gop} -> ${outputFile?.absolutePath ?: "nofile"}",
        )
        return surface
    }

    fun setBitrate(bps: Int) {
        if (!running.get()) return
        currentBitrate = bps
        val params = Bundle().apply { putInt(MediaCodec.PARAMETER_KEY_VIDEO_BITRATE, bps) }
        try {
            codec?.setParameters(params)
        } catch (t: Throwable) {
            Log.w(TAG, "setBitrate ${profile.label}: ${t.message}")
        }
    }

    fun requestSyncFrame() {
        if (!running.get()) return
        val params = Bundle().apply { putInt(MediaCodec.PARAMETER_KEY_REQUEST_SYNC_FRAME, 0) }
        try {
            codec?.setParameters(params)
        } catch (t: Throwable) {
            Log.w(TAG, "requestSyncFrame ${profile.label}: ${t.message}")
        }
    }

    fun setFrameRate(fps: Int) {
        if (fps <= 0 || fps == currentFps || !running.get()) return
        currentFps = fps
        val params = Bundle().apply { putInt(MediaFormat.KEY_FRAME_RATE, fps) }
        try {
            codec?.setParameters(params)
        } catch (t: Throwable) {
            Log.w(TAG, "setFrameRate ${profile.label}: ${t.message}")
        }
    }

    fun fps(): Int = currentFps

    fun stop() {
        if (!running.getAndSet(false)) return
        try {
            codec?.signalEndOfInputStream()
        } catch (_: Throwable) {
        }
        try {
            codec?.stop()
        } catch (_: Throwable) {
        }
        try {
            codec?.release()
        } catch (_: Throwable) {
        }
        codec = null
        try {
            inputSurface?.release()
        } catch (_: Throwable) {
        }
        inputSurface = null
        try {
            fos?.flush()
            fos?.close()
        } catch (_: Throwable) {
        }
        fos = null
        thread.quitSafely()
    }

    private val callback = object : MediaCodec.Callback() {
        override fun onInputBufferAvailable(codec: MediaCodec, index: Int) {
        }

        override fun onOutputBufferAvailable(
            codec: MediaCodec,
            index: Int,
            info: MediaCodec.BufferInfo,
        ) {
            try {
                val buffer = codec.getOutputBuffer(index) ?: return
                if (info.size > 0) {
                    val chunk = ByteArray(info.size)
                    buffer.position(info.offset)
                    buffer.get(chunk, 0, info.size)
                    fos?.write(chunk)
                    bitrateMeter.record(info.size)
                    onFrame?.invoke(chunk, info.presentationTimeUs, info.flags)
                }
                codec.releaseOutputBuffer(index, false)
                if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
                    running.set(false)
                }
            } catch (t: Throwable) {
                Log.w(TAG, "onOutputBuffer ${profile.label}: ${t.message}")
            }
        }

        override fun onError(codec: MediaCodec, e: MediaCodec.CodecException) {
            Log.e(TAG, "encoder error ${profile.label}", e)
        }

        override fun onOutputFormatChanged(codec: MediaCodec, format: MediaFormat) {
            Log.i(TAG, "format ${profile.label}: $format")
        }
    }

    companion object {
        private const val TAG = "HardwareEncoder"
        private const val MIME = "video/avc"
    }
}
