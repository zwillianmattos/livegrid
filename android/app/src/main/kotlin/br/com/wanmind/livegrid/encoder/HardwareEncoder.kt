package br.com.wanmind.livegrid.encoder

import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.media.MediaMuxer
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.HandlerThread
import android.util.Log
import android.view.Surface
import java.io.File
import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.util.ArrayDeque
import java.util.concurrent.atomic.AtomicBoolean

class HardwareEncoder(
    private val profile: Profile,
    private val outputFile: File?,
    val bitrateMeter: BitrateMeter = BitrateMeter(),
    private val onFrame: ((ByteArray, Long, Int) -> Unit)? = null,
    private val audioFormat: MediaFormat? = null,
) {

    data class Profile(
        val width: Int,
        val height: Int,
        val fps: Int,
        val bitrateBps: Int,
        val gop: Int,
        val label: String,
    )

    private class PendingAudioSample(val data: ByteArray, val ptsUs: Long, val flags: Int)

    private var codec: MediaCodec? = null
    private var inputSurface: Surface? = null
    private var fos: FileOutputStream? = null
    private var muxer: MediaMuxer? = null
    private val muxerLock = Any()

    private var videoTrack: Int = -1
    private var audioTrack: Int = -1
    private var muxerStarted = false
    private var lastAudioPtsUs = Long.MIN_VALUE
    private var firstVideoPtsUs = -1L

    private val pendingAudioSamples = ArrayDeque<PendingAudioSample>()
    private val isMp4 = outputFile?.name?.endsWith(".mp4", ignoreCase = true) == true
    private val isRecording = isMp4
    private val thread = HandlerThread("enc-${profile.label}").apply { start() }
    private val handler = Handler(thread.looper)
    private val running = AtomicBoolean(false)
    private var currentBitrate = profile.bitrateBps
    private var currentFps = profile.fps

    fun start(): Surface {
        val c = MediaCodec.createEncoderByType(MIME)
        codec = c
        val caps = try {
            c.codecInfo.getCapabilitiesForType(MIME)
        } catch (_: Throwable) {
            null
        }
        val attempts = profileAttempts(caps)
        var lastError: Throwable? = null
        var configured: String? = null
        c.setCallback(callback, handler)
        for ((name, avcProfile) in attempts) {
            try {
                c.configure(buildFormat(caps, avcProfile), null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
                configured = name
                break
            } catch (t: Throwable) {
                lastError = t
                Log.w(TAG, "configure ${profile.label} $name falhou: ${t.message}")
                try {
                    c.reset()
                    c.setCallback(callback, handler)
                } catch (_: Throwable) {
                }
            }
        }
        if (configured == null) throw IllegalStateException("encoder ${profile.label} não configurou", lastError)

        val surface = c.createInputSurface()
        inputSurface = surface
        if (outputFile != null) {
            if (isMp4) {
                val m = MediaMuxer(outputFile.absolutePath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
                if (audioFormat != null) {
                    audioTrack = try {
                        m.addTrack(audioFormat)
                    } catch (t: Throwable) {
                        Log.w(TAG, "addTrack áudio ${profile.label} falhou: ${t.message}; gravando mudo")
                        -1
                    }
                }
                muxer = m
            } else {
                fos = FileOutputStream(outputFile)
            }
        }
        c.start()
        running.set(true)
        Log.i(
            TAG,
            "encoder ${profile.label} ${profile.width}x${profile.height}@${profile.fps} bps=${profile.bitrateBps} gop=${profile.gop} profile=$configured audioTrack=$audioTrack -> ${outputFile?.absolutePath ?: "nofile"}",
        )
        return surface
    }

    private fun profileAttempts(caps: MediaCodecInfo.CodecCapabilities?): List<Pair<String, Int?>> {
        val supported = caps?.profileLevels?.map { it.profile }?.toSet().orEmpty()
        val list = mutableListOf<Pair<String, Int?>>()
        // Gravação em arquivo: High dá ~10-15% mais qualidade pelo mesmo bitrate.
        // Live fica em Main por compatibilidade com o decoder do OBS.
        if (isRecording && MediaCodecInfo.CodecProfileLevel.AVCProfileHigh in supported) {
            list += "High" to MediaCodecInfo.CodecProfileLevel.AVCProfileHigh
        }
        list += "Main" to MediaCodecInfo.CodecProfileLevel.AVCProfileMain
        list += "Baseline" to MediaCodecInfo.CodecProfileLevel.AVCProfileBaseline
        list += "default" to null
        return list
    }

    private fun buildFormat(caps: MediaCodecInfo.CodecCapabilities?, avcProfile: Int?): MediaFormat =
        MediaFormat.createVideoFormat(MIME, profile.width, profile.height).apply {
            setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface)
            setInteger(MediaFormat.KEY_BIT_RATE, profile.bitrateBps)
            setInteger(MediaFormat.KEY_FRAME_RATE, profile.fps)
            setFloat(MediaFormat.KEY_I_FRAME_INTERVAL, profile.gop.toFloat() / profile.fps)
            setInteger(MediaFormat.KEY_BITRATE_MODE, bitrateMode(caps))
            // Sem KEY_LEVEL: o encoder escolhe o level certo pra resolução/fps.
            // Fixar 4.1 quebrava configure em 1080p60 e em encoders Exynos.
            if (avcProfile != null) setInteger(MediaFormat.KEY_PROFILE, avcProfile)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                setInteger(MediaFormat.KEY_COLOR_STANDARD, MediaFormat.COLOR_STANDARD_BT709)
                setInteger(MediaFormat.KEY_COLOR_RANGE, MediaFormat.COLOR_RANGE_LIMITED)
                setInteger(MediaFormat.KEY_COLOR_TRANSFER, MediaFormat.COLOR_TRANSFER_SDR_VIDEO)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                setInteger(MediaFormat.KEY_MAX_B_FRAMES, 0)
            }
            if (!isRecording && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
                setInteger(MediaFormat.KEY_LATENCY, 1)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                setInteger(MediaFormat.KEY_PRIORITY, 0)
            }
        }

    private fun bitrateMode(caps: MediaCodecInfo.CodecCapabilities?): Int {
        val enc = caps?.encoderCapabilities
        val vbr = MediaCodecInfo.EncoderCapabilities.BITRATE_MODE_VBR
        val cbr = MediaCodecInfo.EncoderCapabilities.BITRATE_MODE_CBR
        // Live: CBR pela previsibilidade no LAN. Arquivo: VBR gasta bits onde há movimento.
        if (isRecording && enc?.isBitrateModeSupported(vbr) == true) return vbr
        if (enc == null || enc.isBitrateModeSupported(cbr)) return cbr
        return vbr
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

        synchronized(muxerLock) {
            try {
                if (muxerStarted) muxer?.stop()
            } catch (t: Throwable) {
                Log.w(TAG, "muxer stop ${profile.label}: ${t.message}")
            }
            try {
                muxer?.release()
            } catch (_: Throwable) {
            }
            muxer = null
            muxerStarted = false
            videoTrack = -1
            audioTrack = -1
            pendingAudioSamples.clear()
        }
        thread.quitSafely()
    }

    private val callback = object : MediaCodec.Callback() {
        override fun onInputBufferAvailable(codec: MediaCodec, index: Int) {
        }

        override fun onOutputBufferAvailable(codec: MediaCodec, index: Int, info: MediaCodec.BufferInfo) {
            try {
                val buffer = codec.getOutputBuffer(index) ?: return
                if (info.size > 0) {
                    val isCodecConfig = info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0
                    if (isMp4) {
                        if (!isCodecConfig) {
                            synchronized(muxerLock) {
                                if (muxerStarted && videoTrack >= 0) {
                                    val view = buffer.duplicate()
                                    view.position(info.offset)
                                    view.limit(info.offset + info.size)
                                    muxer?.writeSampleData(videoTrack, view, info)
                                    if (firstVideoPtsUs < 0) {
                                        firstVideoPtsUs = info.presentationTimeUs
                                        flushPendingAudioLocked()
                                    }
                                }
                            }
                        }
                    } else if (fos != null) {
                        val chunk = ByteArray(info.size)
                        buffer.position(info.offset)
                        buffer.get(chunk, 0, info.size)
                        fos?.write(chunk)
                    }
                    bitrateMeter.record(info.size)
                    if (onFrame != null) {
                        val chunk = ByteArray(info.size)
                        buffer.position(info.offset)
                        buffer.get(chunk, 0, info.size)
                        onFrame.invoke(chunk, info.presentationTimeUs, info.flags)
                    }
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
            Log.i(TAG, "format video ${profile.label}: $format")
            if (!isMp4) return
            synchronized(muxerLock) {
                val m = muxer ?: return
                if (muxerStarted) return
                try {
                    videoTrack = m.addTrack(format)
                    m.start()
                    muxerStarted = true
                    Log.i(TAG, "muxer ${profile.label} on: video=$videoTrack audio=$audioTrack")
                } catch (t: Throwable) {
                    Log.e(TAG, "muxer start ${profile.label} falhou", t)
                }
            }
        }
    }

    private fun flushPendingAudioLocked() {
        val first = pendingAudioSamples.peekFirst()
        if (first != null && kotlin.math.abs(first.ptsUs - firstVideoPtsUs) > CLOCK_MISMATCH_US) {
            Log.e(TAG, "áudio/vídeo em relógios diferentes (${profile.label}): audio=${first.ptsUs} video=$firstVideoPtsUs")
        }
        while (pendingAudioSamples.isNotEmpty()) {
            val s = pendingAudioSamples.pollFirst() ?: break
            writeAudioLocked(s.data, s.ptsUs, s.flags)
        }
    }

    private fun startsBeforeVideo(ptsUs: Long): Boolean =
        ptsUs < firstVideoPtsUs && firstVideoPtsUs - ptsUs < CLOCK_MISMATCH_US

    private fun writeAudioLocked(data: ByteArray, ptsUs: Long, flags: Int) {
        val m = muxer ?: return
        if (audioTrack < 0) return
        // Áudio anterior ao 1º frame faria o arquivo abrir com tela preta/congelada.
        if (startsBeforeVideo(ptsUs)) return
        // MPEG4Writer rejeita PTS não-crescente na mesma trilha.
        if (ptsUs <= lastAudioPtsUs) return
        lastAudioPtsUs = ptsUs
        val info = MediaCodec.BufferInfo().apply { set(0, data.size, ptsUs, flags) }
        try {
            m.writeSampleData(audioTrack, ByteBuffer.wrap(data), info)
        } catch (t: Throwable) {
            Log.w(TAG, "writeAudio ${profile.label}: ${t.message}")
        }
    }

    fun writeAudioSample(data: ByteArray, presentationTimeUs: Long, flags: Int) {
        if (!isMp4 || audioTrack < 0) return
        synchronized(muxerLock) {
            if (muxer == null) return
            if (!muxerStarted || firstVideoPtsUs < 0) {
                pendingAudioSamples.addLast(PendingAudioSample(data, presentationTimeUs, flags))
                while (pendingAudioSamples.size > MAX_PENDING_AUDIO) pendingAudioSamples.pollFirst()
                return
            }
            writeAudioLocked(data, presentationTimeUs, flags)
        }
    }

    companion object {
        private const val TAG = "HardwareEncoder"
        private const val MIME = MediaFormat.MIMETYPE_VIDEO_AVC
        private const val MAX_PENDING_AUDIO = 128
        private const val CLOCK_MISMATCH_US = 5_000_000L
    }
}
