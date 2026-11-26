package br.com.wanmind.livegrid.encoder

import android.media.AudioFormat
import android.media.AudioRecord
import android.media.AudioTimestamp
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.media.MediaRecorder
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.util.Log
import java.nio.ByteBuffer
import java.util.ArrayDeque
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.min
import kotlin.math.sqrt

/**
 * PCM mono 16-bit -> AAC-LC. PTS em microssegundos no relógio monotonic
 * (System.nanoTime), o mesmo que o GlRenderer usa pros frames de vídeo.
 */
class AudioEncoder(
    private val onSample: (ByteArray, Long, Int) -> Unit,
    private val onLevel: (Float) -> Unit = {},
) {

    private class PcmChunk(val data: ByteArray, val len: Int, val ptsUs: Long)

    private val thread = HandlerThread("audio-enc").apply { start() }
    private val handler = Handler(thread.looper)

    private var audioRecord: AudioRecord? = null
    private var codec: MediaCodec? = null
    private val running = AtomicBoolean(false)
    private var captureThread: Thread? = null

    private val queueLock = Any()
    private val pendingInputIndices = ArrayDeque<Int>()
    private val pendingPcm = ArrayDeque<PcmChunk>()

    var sampleRate: Int = SAMPLE_RATES.first()
        private set

    fun start(): Boolean {
        var record: AudioRecord? = null
        var bufferSize = 0
        loop@ for (rate in SAMPLE_RATES) {
            val minBuf = AudioRecord.getMinBufferSize(
                rate,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
            )
            if (minBuf <= 0) continue
            val size = (minBuf * 2).coerceAtLeast(MIN_BUFFER_BYTES)
            // UNPROCESSED fica de fora de propósito: sem AGC, sai quase mudo em Samsung.
            for (source in SOURCES) {
                val candidate = try {
                    AudioRecord(source, rate, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT, size)
                } catch (t: Throwable) {
                    Log.w(TAG, "AudioRecord source=$source rate=$rate falhou: ${t.message}")
                    null
                } ?: continue
                if (candidate.state == AudioRecord.STATE_INITIALIZED) {
                    record = candidate
                    sampleRate = rate
                    bufferSize = size
                    Log.i(TAG, "AudioRecord source=$source rate=$rate buf=$size")
                    break@loop
                }
                candidate.release()
            }
        }
        if (record == null) {
            Log.e(TAG, "nenhuma combinação de AudioRecord inicializou")
            return false
        }

        val c = try {
            MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_AUDIO_AAC).apply {
                configure(encoderFormat(bufferSize), null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
                setCallback(callback, handler)
            }
        } catch (t: Throwable) {
            Log.e(TAG, "encoder AAC falhou: ${t.message}")
            record.release()
            return false
        }

        try {
            record.startRecording()
        } catch (t: Throwable) {
            Log.e(TAG, "startRecording falhou: ${t.message}")
            record.release()
            c.release()
            return false
        }
        if (record.recordingState != AudioRecord.RECORDSTATE_RECORDING) {
            Log.e(TAG, "AudioRecord não entrou em RECORDING (mic ocupado/bloqueado?)")
            record.release()
            c.release()
            return false
        }

        audioRecord = record
        codec = c
        synchronized(queueLock) {
            pendingInputIndices.clear()
            pendingPcm.clear()
        }
        running.set(true)
        c.start()
        captureThread = Thread({ captureLoop(bufferSize) }, "audio-capture").apply { start() }
        Log.i(TAG, "audio on: ${sampleRate}Hz mono AAC-LC bps=$BIT_RATE")
        return true
    }

    /**
     * Formato da trilha pro MediaMuxer, com csd-0 montado à mão. Permite
     * `addTrack` antes do encoder emitir qualquer coisa: sem corrida com o vídeo.
     */
    fun trackFormat(): MediaFormat =
        MediaFormat.createAudioFormat(MediaFormat.MIMETYPE_AUDIO_AAC, sampleRate, CHANNELS).apply {
            setInteger(MediaFormat.KEY_AAC_PROFILE, MediaCodecInfo.CodecProfileLevel.AACObjectLC)
            setInteger(MediaFormat.KEY_BIT_RATE, BIT_RATE)
            setByteBuffer("csd-0", ByteBuffer.wrap(audioSpecificConfig(sampleRate, CHANNELS)))
        }

    private fun encoderFormat(bufferSize: Int): MediaFormat =
        MediaFormat.createAudioFormat(MediaFormat.MIMETYPE_AUDIO_AAC, sampleRate, CHANNELS).apply {
            setInteger(MediaFormat.KEY_AAC_PROFILE, MediaCodecInfo.CodecProfileLevel.AACObjectLC)
            setInteger(MediaFormat.KEY_BIT_RATE, BIT_RATE)
            setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, bufferSize)
        }

    private fun captureLoop(bufferSize: Int) {
        val record = audioRecord ?: return
        val bytesPerFrame = 2 * CHANNELS
        var anchorUs = -1L
        var framesRead = 0L
        while (running.get()) {
            val buf = ByteArray(bufferSize)
            val n = record.read(buf, 0, buf.size)
            if (n <= 0) {
                if (n < 0) Log.w(TAG, "AudioRecord.read=$n")
                continue
            }
            if (anchorUs < 0) {
                anchorUs = firstFrameTimeUs(record, n / bytesPerFrame)
            }
            // PTS derivado da contagem de amostras: sem jitter de agendamento da thread.
            val ptsUs = anchorUs + framesRead * 1_000_000L / sampleRate
            framesRead += n / bytesPerFrame
            onLevel(rms(buf, n))
            enqueuePcm(buf, n, ptsUs)
        }
    }

    private fun firstFrameTimeUs(record: AudioRecord, framesInFirstRead: Int): Long {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            val ts = AudioTimestamp()
            if (record.getTimestamp(ts, AudioTimestamp.TIMEBASE_MONOTONIC) == AudioRecord.SUCCESS) {
                return (ts.nanoTime - ts.framePosition * 1_000_000_000L / sampleRate) / 1000L
            }
        }
        val durationUs = framesInFirstRead * 1_000_000L / sampleRate
        return System.nanoTime() / 1000L - durationUs
    }

    private fun enqueuePcm(data: ByteArray, len: Int, ptsUs: Long) {
        val readyIndex: Int?
        synchronized(queueLock) {
            readyIndex = pendingInputIndices.pollFirst()
            if (readyIndex == null) {
                pendingPcm.addLast(PcmChunk(data, len, ptsUs))
                while (pendingPcm.size > MAX_PENDING_CHUNKS) pendingPcm.pollFirst()
            }
        }
        if (readyIndex != null) feedBuffer(readyIndex, data, len, ptsUs)
    }

    private fun feedBuffer(index: Int, data: ByteArray, len: Int, ptsUs: Long) {
        val c = codec ?: return
        try {
            val input = c.getInputBuffer(index) ?: return
            input.clear()
            val size = min(len, input.remaining())
            input.put(data, 0, size)
            c.queueInputBuffer(index, 0, size, ptsUs, 0)
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
        return min(1f, (sqrt(sum / count) / 32768.0).toFloat())
    }

    private val callback = object : MediaCodec.Callback() {
        override fun onInputBufferAvailable(codec: MediaCodec, index: Int) {
            val chunk: PcmChunk?
            synchronized(queueLock) {
                chunk = pendingPcm.pollFirst()
                if (chunk == null) pendingInputIndices.addLast(index)
            }
            if (chunk != null) feedBuffer(index, chunk.data, chunk.len, chunk.ptsUs)
        }

        override fun onOutputBufferAvailable(codec: MediaCodec, index: Int, info: MediaCodec.BufferInfo) {
            try {
                val buffer = codec.getOutputBuffer(index)
                val isConfig = info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0
                if (buffer != null && info.size > 0 && !isConfig) {
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
        private const val BIT_RATE = 128_000
        private const val CHANNELS = 1
        private const val MAX_PENDING_CHUNKS = 32
        private const val MIN_BUFFER_BYTES = 4096
        private val SAMPLE_RATES = listOf(48_000, 44_100)
        private val SOURCES = listOf(
            MediaRecorder.AudioSource.CAMCORDER,
            MediaRecorder.AudioSource.MIC,
        )

        private val AAC_FREQ_INDEX = intArrayOf(
            96000, 88200, 64000, 48000, 44100, 32000, 24000, 22050, 16000, 12000, 11025, 8000, 7350,
        )

        /** ISO 14496-3 AudioSpecificConfig de 2 bytes pra AAC-LC (object type 2). */
        fun audioSpecificConfig(sampleRate: Int, channels: Int): ByteArray {
            val freqIndex = AAC_FREQ_INDEX.indexOf(sampleRate)
            require(freqIndex >= 0) { "sample rate AAC inválido: $sampleRate" }
            val objectType = 2
            val b0 = (objectType shl 3) or (freqIndex shr 1)
            val b1 = ((freqIndex and 1) shl 7) or (channels shl 3)
            return byteArrayOf(b0.toByte(), b1.toByte())
        }
    }
}
