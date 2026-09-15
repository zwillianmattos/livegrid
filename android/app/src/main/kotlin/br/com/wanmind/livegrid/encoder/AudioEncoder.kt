package br.com.wanmind.livegrid.encoder

import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.media.MediaRecorder
import android.os.Handler
import android.os.HandlerThread
import android.util.Log
import java.util.ArrayDeque
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.min
import kotlin.math.sqrt

class AudioEncoder(
    private val onFormat: (MediaFormat) -> Unit,
    private val onSample: (ByteArray, Long, Int) -> Unit,
    private val onLevel: (Float) -> Unit = {},
) {

    private data class PcmChunk(val data: ByteArray, val len: Int, val ptsUs: Long)

    private var audioRecord: AudioRecord? = null
    private var codec: MediaCodec? = null
    private val thread = HandlerThread("audio-enc").apply { start() }
    private val handler = Handler(thread.looper)
    private val running = AtomicBoolean(false)
    private var captureThread: Thread? = null

    // MediaCodec está em modo assíncrono (setCallback): buffers de entrada só podem
    // ser obtidos via onInputBufferAvailable, nunca via dequeueInputBuffer manual.
    private val queueLock = Any()
    private val pendingInputIndices = ArrayDeque<Int>()
    private val pendingPcm = ArrayDeque<PcmChunk>()

    fun start(): Boolean {
        val minBuf = AudioRecord.getMinBufferSize(
            SAMPLE_RATE,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
        )
        if (minBuf <= 0) {
            Log.w(TAG, "getMinBufferSize inválido ($minBuf)")
            return false
        }
        val bufferSize = minBuf * 2
        val record = try {
            AudioRecord(
                MediaRecorder.AudioSource.CAMCORDER,
                SAMPLE_RATE,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
                bufferSize,
            )
        } catch (t: Throwable) {
            Log.w(TAG, "AudioRecord(CAMCORDER) falhou: ${t.message}; fallback MIC")
            try {
                AudioRecord(
                    MediaRecorder.AudioSource.MIC,
                    SAMPLE_RATE,
                    AudioFormat.CHANNEL_IN_MONO,
                    AudioFormat.ENCODING_PCM_16BIT,
                    bufferSize,
                )
            } catch (t2: Throwable) {
                Log.w(TAG, "AudioRecord(MIC) falhou: ${t2.message}")
                return false
            }
        }
        if (record.state != AudioRecord.STATE_INITIALIZED) {
            Log.w(TAG, "AudioRecord não inicializado (state=${record.state})")
            record.release()
            return false
        }

        val format = MediaFormat.createAudioFormat(MediaFormat.MIMETYPE_AUDIO_AAC, SAMPLE_RATE, 1).apply {
            setInteger(MediaFormat.KEY_AAC_PROFILE, MediaCodecInfo.CodecProfileLevel.AACObjectLC)
            setInteger(MediaFormat.KEY_BIT_RATE, BIT_RATE)
            setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, bufferSize)
        }
        val c = try {
            MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_AUDIO_AAC).apply {
                configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
                setCallback(callback, handler)
            }
        } catch (t: Throwable) {
            Log.w(TAG, "criação do encoder AAC falhou: ${t.message}")
            record.release()
            return false
        }

        audioRecord = record
        codec = c
        running.set(true)
        pendingInputIndices.clear()
        pendingPcm.clear()
        c.start()
        record.startRecording()

        captureThread = Thread({ captureLoop(bufferSize) }, "audio-capture").apply { start() }
        Log.i(TAG, "audio encoder on: ${SAMPLE_RATE}Hz mono AAC bps=$BIT_RATE buf=$bufferSize")
        return true
    }

    private fun captureLoop(bufferSize: Int) {
        val record = audioRecord ?: return
        var totalSamples = 0L
        while (running.get()) {
            val buf = ByteArray(bufferSize)
            val n = record.read(buf, 0, buf.size)
            if (n <= 0) continue
            onLevel(rms(buf, n))
            val ptsUs = totalSamples * 1_000_000L / SAMPLE_RATE
            totalSamples += n / 2
            enqueuePcm(buf, n, ptsUs)
        }
    }

    private fun enqueuePcm(data: ByteArray, len: Int, ptsUs: Long) {
        val readyIndex: Int?
        synchronized(queueLock) {
            readyIndex = pendingInputIndices.pollFirst()
            if (readyIndex == null) {
                pendingPcm.addLast(PcmChunk(data, len, ptsUs))
                while (pendingPcm.size > MAX_PENDING_CHUNKS) {
                    pendingPcm.pollFirst()
                }
            }
        }
        if (readyIndex != null) {
            feedBuffer(readyIndex, data, len, ptsUs)
        }
    }

    private fun feedBuffer(index: Int, data: ByteArray, len: Int, ptsUs: Long) {
        val c = codec ?: return
        try {
            val input = c.getInputBuffer(index) ?: return
            input.clear()
            input.put(data, 0, len)
            c.queueInputBuffer(index, 0, len, ptsUs, 0)
        } catch (t: Throwable) {
            Log.w(TAG, "feedBuffer: ${t.message}")
        }
    }

    private fun rms(data: ByteArray, len: Int): Float {
        if (len < 2) return 0f
        var sum = 0.0
        var count = 0
        var i = 0
        while (i + 1 < len) {
            val sample = ((data[i + 1].toInt() shl 8) or (data[i].toInt() and 0xFF)).toShort()
            sum += (sample * sample).toDouble()
            count++
            i += 2
        }
        if (count == 0) return 0f
        val rms = sqrt(sum / count)
        return min(1f, (rms / 32768.0).toFloat())
    }

    private val callback = object : MediaCodec.Callback() {
        override fun onInputBufferAvailable(codec: MediaCodec, index: Int) {
            val chunk: PcmChunk?
            synchronized(queueLock) {
                chunk = pendingPcm.pollFirst()
                if (chunk == null) {
                    pendingInputIndices.addLast(index)
                }
            }
            if (chunk != null) {
                feedBuffer(index, chunk.data, chunk.len, chunk.ptsUs)
            }
        }

        override fun onOutputBufferAvailable(
            codec: MediaCodec,
            index: Int,
            info: MediaCodec.BufferInfo,
        ) {
            try {
                val buffer = codec.getOutputBuffer(index)
                if (buffer != null && info.size > 0 &&
                    info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG == 0
                ) {
                    val chunk = ByteArray(info.size)
                    buffer.position(info.offset)
                    buffer.get(chunk, 0, info.size)
                    onSample(chunk, info.presentationTimeUs, info.flags)
                }
                codec.releaseOutputBuffer(index, false)
            } catch (t: Throwable) {
                Log.w(TAG, "onOutputBuffer: ${t.message}")
            }
        }

        override fun onError(codec: MediaCodec, e: MediaCodec.CodecException) {
            Log.e(TAG, "audio encoder error", e)
        }

        override fun onOutputFormatChanged(codec: MediaCodec, format: MediaFormat) {
            Log.i(TAG, "audio format: $format")
            onFormat(format)
        }
    }

    fun stop() {
        if (!running.getAndSet(false)) return
        try {
            audioRecord?.stop()
        } catch (_: Throwable) {
        }
        try {
            captureThread?.join(500)
        } catch (_: Throwable) {
        }
        captureThread = null
        try {
            audioRecord?.release()
        } catch (_: Throwable) {
        }
        audioRecord = null
        try {
            codec?.stop()
        } catch (_: Throwable) {
        }
        try {
            codec?.release()
        } catch (_: Throwable) {
        }
        codec = null
        synchronized(queueLock) {
            pendingInputIndices.clear()
            pendingPcm.clear()
        }
        thread.quitSafely()
    }

    companion object {
        private const val TAG = "AudioEncoder"
        private const val SAMPLE_RATE = 44100
        private const val BIT_RATE = 128_000
        private const val MAX_PENDING_CHUNKS = 8
    }
}
