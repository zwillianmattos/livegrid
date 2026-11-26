package br.com.wanmind.livegrid.encoder

import android.content.Context
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.AudioTimestamp
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.media.MediaRecorder
import android.os.Handler
import android.os.HandlerThread
import android.util.Log
import java.nio.ByteBuffer
import java.util.ArrayDeque
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.min
import kotlin.math.sqrt

/**
 * PCM 16-bit (mono ou estéreo, fixo no start) -> AAC-LC. PTS em microssegundos no
 * relógio monotonic (System.nanoTime), o mesmo que o GlRenderer usa pros frames de vídeo.
 */
class AudioEncoder(
    context: Context,
    private val onSample: (ByteArray, Long, Int) -> Unit,
    private val onLevel: (Float) -> Unit = {},
) {

    private class PcmChunk(val data: ByteArray, val len: Int, val ptsUs: Long)

    private val thread = HandlerThread("audio-enc").apply { start() }
    private val handler = Handler(thread.looper)
    private val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager

    private val recordLock = Any()
    @Volatile private var audioRecord: AudioRecord? = null
    @Volatile private var preferredDevice: AudioDeviceInfo? = null
    @Volatile private var resyncRequested = false
    private var deviceCallback: AudioDeviceCallback? = null
    private var codec: MediaCodec? = null
    private val running = AtomicBoolean(false)
    @Volatile private var captureThread: Thread? = null
    private var setupDone = CountDownLatch(0)

    private val queueLock = Any()
    private val pendingInputIndices = ArrayDeque<Int>()
    private val pendingPcm = ArrayDeque<PcmChunk>()

    var sampleRate: Int = SAMPLE_RATES.first()
        private set

    var channels: Int = 1
        private set

    private val bitRate: Int get() = if (channels == 2) BIT_RATE_STEREO else BIT_RATE_MONO

    private class CaptureConfig(val source: Int, val mask: Int, val bufferSize: Int)

    /**
     * Decide taxa/canais na hora (o muxer precisa do trackFormat na criação). A verificação
     * de roteamento e o fallback de fonte rodam no handler, sem bloquear quem chamou.
     */
    fun start(): Boolean {
        val device = pickInputDevice()
        Log.i(TAG, "input preferido: ${describe(device)} channelCounts=${device?.channelCounts?.toList()}")
        val opened = openRecord(device) ?: run {
            Log.e(TAG, "nenhuma combinação de AudioRecord inicializou")
            thread.quitSafely()
            return false
        }
        val (record, source, bufferSize) = opened
        val channelMask = if (channels == 2) AudioFormat.CHANNEL_IN_STEREO else AudioFormat.CHANNEL_IN_MONO

        val c = try {
            MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_AUDIO_AAC).apply {
                configure(encoderFormat(bufferSize), null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
                setCallback(callback, handler)
            }
        } catch (t: Throwable) {
            Log.e(TAG, "encoder AAC falhou: ${t.message}")
            record.release()
            thread.quitSafely()
            return false
        }

        preferredDevice = device
        codec = c
        synchronized(queueLock) {
            pendingInputIndices.clear()
            pendingPcm.clear()
        }
        running.set(true)
        c.start()
        val config = CaptureConfig(source, channelMask, bufferSize)
        val latch = CountDownLatch(1)
        setupDone = latch
        handler.post {
            try {
                setupCapture(record, device, config)
            } catch (t: Throwable) {
                Log.e(TAG, "setup de captura falhou: ${t.message}")
            } finally {
                latch.countDown()
            }
        }
        registerDeviceCallback()
        Log.i(TAG, "audio on: ${sampleRate}Hz ch=$channels AAC-LC bps=$bitRate")
        return true
    }

    fun routedInput(): AudioDeviceInfo? = try {
        audioRecord?.routedDevice
    } catch (_: Throwable) {
        null
    }

    private fun setupCapture(initial: AudioRecord, device: AudioDeviceInfo?, config: CaptureConfig) {
        if (!running.get()) {
            initial.release()
            return
        }
        var source = config.source
        var record: AudioRecord? = initial
        var polled = false
        if (!startRecord(initial, device)) {
            stopQuietly(initial)
            record = null
        } else if (device != null && isExternal(device)) {
            polled = true
            if (!isRoutedTo(initial, device)) {
                Log.w(TAG, "source=$source não roteou para ${describe(device)} (routed=${describe(initial.routedDevice)})")
                // A policy de áudio continua roteando pra sessão ativa: cada candidato precisa testar sozinho.
                stopQuietly(initial)
                record = null
                for (alt in EXTERNAL_FALLBACK_SOURCES) {
                    if (alt == config.source || !running.get()) continue
                    val candidate = createRecord(alt, sampleRate, config.mask, config.bufferSize) ?: continue
                    if (startRecord(candidate, device) && isRoutedTo(candidate, device)) {
                        record = candidate
                        source = alt
                        Log.i(TAG, "fallback source=$alt roteou para ${describe(device)}")
                        break
                    }
                    stopQuietly(candidate)
                }
                if (record == null && running.get()) {
                    Log.w(TAG, "nenhuma fonte roteou para ${describe(device)}; mantendo source=${config.source} no mic interno")
                    record = createRecord(config.source, sampleRate, config.mask, config.bufferSize)
                        ?.takeIf { startRecord(it, null) || run { stopQuietly(it); false } }
                }
            }
        }
        // Sem leitor durante o poll o buffer estoura; reiniciar zera o buffer antes do anchor.
        if (record != null && polled && !restartRecord(record)) {
            stopQuietly(record)
            record = null
        }
        if (record == null) Log.e(TAG, "AudioRecord não iniciou; gravando silêncio")
        synchronized(recordLock) {
            if (!running.get()) {
                record?.let { stopQuietly(it) }
                return
            }
            audioRecord = record
            captureThread = Thread(
                { captureLoop(record, source, config) },
                "audio-capture",
            ).apply { start() }
        }
        Log.i(TAG, "AudioRecord source=$source routed=${describe(record?.routedDevice)}")
    }

    private data class Opened(val record: AudioRecord, val source: Int, val bufferSize: Int)

    private fun openRecord(device: AudioDeviceInfo?): Opened? {
        val counts = device?.channelCounts ?: IntArray(0)
        val tryStereo = device == null || counts.isEmpty() || counts.contains(2) ||
            device.type == AudioDeviceInfo.TYPE_BUILTIN_MIC
        val channelOptions = if (tryStereo) listOf(2, 1) else listOf(1)
        for (ch in channelOptions) {
            val mask = if (ch == 2) AudioFormat.CHANNEL_IN_STEREO else AudioFormat.CHANNEL_IN_MONO
            for (rate in SAMPLE_RATES) {
                val minBuf = AudioRecord.getMinBufferSize(rate, mask, AudioFormat.ENCODING_PCM_16BIT)
                if (minBuf <= 0) continue
                val size = (minBuf * 2).coerceAtLeast(MIN_BUFFER_BYTES * ch)
                for (source in SOURCES) {
                    val record = createRecord(source, rate, mask, size) ?: continue
                    sampleRate = rate
                    channels = ch
                    Log.i(TAG, "AudioRecord source=$source rate=$rate ch=$ch buf=$size")
                    return Opened(record, source, size)
                }
            }
        }
        return null
    }

    private fun createRecord(source: Int, rate: Int, mask: Int, size: Int): AudioRecord? {
        val candidate = try {
            AudioRecord(source, rate, mask, AudioFormat.ENCODING_PCM_16BIT, size)
        } catch (t: Throwable) {
            Log.w(TAG, "AudioRecord source=$source rate=$rate mask=$mask falhou: ${t.message}")
            return null
        }
        if (candidate.state == AudioRecord.STATE_INITIALIZED) return candidate
        candidate.release()
        return null
    }

    private fun startRecord(record: AudioRecord, device: AudioDeviceInfo?): Boolean {
        try {
            if (device != null) record.setPreferredDevice(device)
            record.startRecording()
        } catch (t: Throwable) {
            Log.e(TAG, "startRecording falhou: ${t.message}")
            return false
        }
        if (record.recordingState != AudioRecord.RECORDSTATE_RECORDING) {
            Log.e(TAG, "AudioRecord não entrou em RECORDING (mic ocupado/bloqueado?)")
            return false
        }
        return true
    }

    private fun restartRecord(record: AudioRecord): Boolean {
        try {
            record.stop()
            record.startRecording()
        } catch (t: Throwable) {
            Log.e(TAG, "restart do AudioRecord falhou: ${t.message}")
            return false
        }
        return record.recordingState == AudioRecord.RECORDSTATE_RECORDING
    }

    private fun isRoutedTo(record: AudioRecord, device: AudioDeviceInfo): Boolean {
        // getRoutedDevice pode vir null logo após startRecording até o HAL abrir o stream.
        repeat(ROUTE_POLL_ATTEMPTS) {
            if (!running.get()) return false
            val routed = try {
                record.routedDevice
            } catch (_: Throwable) {
                null
            }
            if (routed != null) return routed.id == device.id || routed.type == device.type
            Thread.sleep(ROUTE_POLL_MS)
        }
        return false
    }

    private fun stopQuietly(record: AudioRecord) {
        try {
            record.stop()
        } catch (_: Throwable) {
        }
        try {
            record.release()
        } catch (_: Throwable) {
        }
    }

    private fun pickInputDevice(): AudioDeviceInfo? {
        val devices = try {
            audioManager.getDevices(AudioManager.GET_DEVICES_INPUTS)
        } catch (t: Throwable) {
            Log.w(TAG, "getDevices falhou: ${t.message}")
            return null
        }
        return devices
            .filter { priority(it.type) >= 0 }
            .maxByOrNull { priority(it.type) }
    }

    private fun registerDeviceCallback() {
        val cb = object : AudioDeviceCallback() {
            override fun onAudioDevicesAdded(addedDevices: Array<out AudioDeviceInfo>?) = reapplyPreferred()
            override fun onAudioDevicesRemoved(removedDevices: Array<out AudioDeviceInfo>?) = reapplyPreferred()
        }
        audioManager.registerAudioDeviceCallback(cb, handler)
        deviceCallback = cb
    }

    // Só troca o roteamento do AudioRecord vivo: taxa e canais da trilha ficam os do start.
    private fun reapplyPreferred() {
        if (!running.get()) return
        val device = pickInputDevice()
        preferredDevice = device
        resyncRequested = true
        val record = audioRecord ?: return
        try {
            record.setPreferredDevice(device)
            Log.i(TAG, "hot-plug: preferido=${describe(device)} routed=${describe(record.routedDevice)}")
        } catch (t: Throwable) {
            Log.w(TAG, "hot-plug setPreferredDevice: ${t.message}")
        }
    }

    /**
     * Formato da trilha pro MediaMuxer, com csd-0 montado à mão. Permite
     * `addTrack` antes do encoder emitir qualquer coisa: sem corrida com o vídeo.
     */
    fun trackFormat(): MediaFormat =
        MediaFormat.createAudioFormat(MediaFormat.MIMETYPE_AUDIO_AAC, sampleRate, channels).apply {
            setInteger(MediaFormat.KEY_AAC_PROFILE, MediaCodecInfo.CodecProfileLevel.AACObjectLC)
            setInteger(MediaFormat.KEY_BIT_RATE, bitRate)
            setByteBuffer("csd-0", ByteBuffer.wrap(audioSpecificConfig(sampleRate, channels)))
        }

    private fun encoderFormat(bufferSize: Int): MediaFormat =
        MediaFormat.createAudioFormat(MediaFormat.MIMETYPE_AUDIO_AAC, sampleRate, channels).apply {
            setInteger(MediaFormat.KEY_AAC_PROFILE, MediaCodecInfo.CodecProfileLevel.AACObjectLC)
            setInteger(MediaFormat.KEY_BIT_RATE, bitRate)
            setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, bufferSize)
        }

    /**
     * PTS = anchor + amostras contadas (sem jitter de agendamento). O anchor vem de
     * getTimestamp e só anda pra frente: amostras perdidas (overrun, re-rota) puxariam o
     * áudio pra antes do vídeo.
     */
    private fun captureLoop(initial: AudioRecord?, source: Int, config: CaptureConfig) {
        val bytesPerFrame = 2 * channels
        val chunkBytes = config.bufferSize - config.bufferSize % bytesPerFrame
        // MAX_PENDING_CHUNKS na fila + 1 sendo lido + 1 sendo copiado pro codec.
        val pool = Array(MAX_PENDING_CHUNKS + 2) { ByteArray(chunkBytes) }
        val silence = ByteArray(chunkBytes)
        val ts = AudioTimestamp()
        var record = initial
        var slot = 0
        var anchorUs = -1L
        var anchorFrame = 0L
        var framesRead = 0L
        var recordBase = 0L
        var lastResyncFrame = 0L
        var lastPtsUs = Long.MIN_VALUE
        var errors = 0
        var recreations = 0
        resyncRequested = false

        while (running.get()) {
            val rec = record
            val buf: ByteArray
            val n: Int
            if (rec == null) {
                buf = silence
                n = chunkBytes
                val frames = n / bytesPerFrame
                Thread.sleep(frames * 1000L / sampleRate)
                val expected = System.nanoTime() / 1000L - framesToUs(frames.toLong())
                if (anchorUs < 0 || expected - ptsAt(anchorUs, anchorFrame, framesRead) > RESYNC_THRESHOLD_US) {
                    anchorUs = expected
                    anchorFrame = framesRead
                }
            } else {
                buf = pool[slot]
                n = rec.read(buf, 0, chunkBytes)
                if (n < 0) {
                    errors++
                    if (errors == 1) Log.w(TAG, "AudioRecord.read=$n")
                    val dead = n == AudioRecord.ERROR_DEAD_OBJECT
                    if ((dead && errors >= DEAD_OBJECT_RETRIES) || errors >= MAX_READ_ERRORS) {
                        errors = 0
                        record = if (recreations++ < MAX_RECREATIONS) recreateRecord(rec, source, config) else null
                        recordBase = framesRead
                        resyncRequested = true
                        if (record == null) {
                            Log.e(TAG, "AudioRecord perdido; seguindo mudo")
                            swapRecord(null)
                            stopQuietly(rec)
                        }
                    } else {
                        Thread.sleep(READ_ERROR_SLEEP_MS)
                    }
                    continue
                }
                if (n == 0) continue
                errors = 0
                slot = (slot + 1) % pool.size
                val frames = n / bytesPerFrame
                if (anchorUs < 0) {
                    anchorUs = timestampUs(rec, ts, framesRead - recordBase, frames, ANCHOR_MAX_LAG_US)
                        ?: (System.nanoTime() / 1000L - framesToUs(frames.toLong()))
                    anchorFrame = framesRead
                    lastResyncFrame = framesRead
                } else if (resyncRequested || framesRead - lastResyncFrame >= sampleRate) {
                    resyncRequested = false
                    lastResyncFrame = framesRead
                    val expected = timestampUs(rec, ts, framesRead - recordBase, frames, RESYNC_MAX_LAG_US)
                    val current = ptsAt(anchorUs, anchorFrame, framesRead)
                    if (expected != null && expected - current > RESYNC_THRESHOLD_US) {
                        Log.i(TAG, "resync áudio +${(expected - current) / 1000} ms")
                        anchorUs = expected
                        anchorFrame = framesRead
                    }
                }
            }
            var ptsUs = ptsAt(anchorUs, anchorFrame, framesRead)
            if (ptsUs <= lastPtsUs) ptsUs = lastPtsUs + 1
            lastPtsUs = ptsUs
            framesRead += n / bytesPerFrame
            onLevel(if (rec == null) 0f else rms(buf, n))
            enqueuePcm(buf, n, ptsUs)
        }
    }

    private fun framesToUs(frames: Long): Long = frames * 1_000_000L / sampleRate

    private fun ptsAt(anchorUs: Long, anchorFrame: Long, frame: Long): Long =
        anchorUs + framesToUs(frame - anchorFrame)

    /** Tempo monotonic do 1º frame do read recém-feito, ou null se o timestamp for inválido. */
    private fun timestampUs(record: AudioRecord, ts: AudioTimestamp, localFrame: Long, frames: Int, maxLagUs: Long): Long? {
        val ok = try {
            record.getTimestamp(ts, AudioTimestamp.TIMEBASE_MONOTONIC) == AudioRecord.SUCCESS
        } catch (_: Throwable) {
            false
        }
        if (!ok) return null
        val startUs = ts.nanoTime / 1000L + framesToUs(localFrame - ts.framePosition)
        val endUs = startUs + framesToUs(frames.toLong())
        val nowUs = System.nanoTime() / 1000L
        // Alguns HALs mantêm framePosition de antes do restart: rejeita o que cair fora do relógio.
        if (endUs > nowUs + TIMESTAMP_FUTURE_SLACK_US || endUs < nowUs - maxLagUs) return null
        return startUs
    }

    private fun swapRecord(record: AudioRecord?): Boolean = synchronized(recordLock) {
        if (!running.get()) return false
        audioRecord = record
        true
    }

    private fun recreateRecord(old: AudioRecord, source: Int, config: CaptureConfig): AudioRecord? {
        Log.w(TAG, "recriando AudioRecord source=$source")
        swapRecord(null)
        stopQuietly(old)
        if (!running.get()) return null
        val fresh = createRecord(source, sampleRate, config.mask, config.bufferSize) ?: return null
        if (!startRecord(fresh, preferredDevice) || !swapRecord(fresh)) {
            stopQuietly(fresh)
            return null
        }
        Log.i(TAG, "AudioRecord recriado routed=${describe(fresh.routedDevice)}")
        return fresh
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
        deviceCallback?.let {
            try {
                audioManager.unregisterAudioDeviceCallback(it)
            } catch (_: Throwable) {
            }
        }
        deviceCallback = null
        if (!running.getAndSet(false)) {
            thread.quitSafely()
            return
        }
        try {
            setupDone.await(SETUP_WAIT_MS, TimeUnit.MILLISECONDS)
        } catch (_: InterruptedException) {
        }
        synchronized(recordLock) {
            try {
                audioRecord?.stop()
            } catch (_: Throwable) {
            }
        }
        try {
            captureThread?.join(500)
        } catch (_: Throwable) {
        }
        captureThread = null
        synchronized(recordLock) {
            try {
                audioRecord?.release()
            } catch (_: Throwable) {
            }
            audioRecord = null
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
        synchronized(queueLock) {
            pendingInputIndices.clear()
            pendingPcm.clear()
        }
        thread.quitSafely()
    }

    companion object {
        private const val TAG = "AudioEncoder"
        private const val BIT_RATE_MONO = 128_000
        private const val BIT_RATE_STEREO = 192_000
        private const val ROUTE_POLL_ATTEMPTS = 10
        private const val ROUTE_POLL_MS = 30L
        private const val MAX_PENDING_CHUNKS = 32
        private const val RESYNC_THRESHOLD_US = 20_000L
        private const val TIMESTAMP_FUTURE_SLACK_US = 20_000L
        private const val ANCHOR_MAX_LAG_US = 200_000L
        private const val RESYNC_MAX_LAG_US = 1_000_000L
        private const val READ_ERROR_SLEEP_MS = 10L
        private const val DEAD_OBJECT_RETRIES = 3
        private const val MAX_READ_ERRORS = 50
        private const val MAX_RECREATIONS = 3
        private const val SETUP_WAIT_MS = 1_000L
        private const val MIN_BUFFER_BYTES = 4096
        private val SAMPLE_RATES = listOf(48_000, 44_100)
        private val SOURCES = listOf(
            MediaRecorder.AudioSource.CAMCORDER,
            MediaRecorder.AudioSource.MIC,
        )
        // UNPROCESSED fica de fora mesmo aqui: sem AGC, sai quase mudo em Samsung.
        private val EXTERNAL_FALLBACK_SOURCES = listOf(
            MediaRecorder.AudioSource.MIC,
            MediaRecorder.AudioSource.VOICE_RECOGNITION,
        )

        private val USB_TYPES = setOf(
            AudioDeviceInfo.TYPE_USB_DEVICE,
            AudioDeviceInfo.TYPE_USB_HEADSET,
            AudioDeviceInfo.TYPE_USB_ACCESSORY,
        )
        private val WIRED_TYPES = setOf(
            AudioDeviceInfo.TYPE_WIRED_HEADSET,
            AudioDeviceInfo.TYPE_LINE_ANALOG,
            AudioDeviceInfo.TYPE_LINE_DIGITAL,
        )
        private val BLUETOOTH_TYPES = setOf(
            AudioDeviceInfo.TYPE_BLUETOOTH_SCO,
            AudioDeviceInfo.TYPE_BLUETOOTH_A2DP,
            AudioDeviceInfo.TYPE_BLE_HEADSET,
        )

        // Bluetooth fica fora (-1): SCO entrega 8/16 kHz.
        private fun priority(type: Int): Int = when (type) {
            in USB_TYPES -> 2
            in WIRED_TYPES -> 1
            AudioDeviceInfo.TYPE_BUILTIN_MIC -> 0
            else -> -1
        }

        private fun isExternal(device: AudioDeviceInfo): Boolean =
            device.type in USB_TYPES || device.type in WIRED_TYPES

        fun inputTypeLabel(device: AudioDeviceInfo?): String = when (device?.type) {
            null -> "none"
            in USB_TYPES -> "usb"
            in WIRED_TYPES -> "wired"
            in BLUETOOTH_TYPES -> "bluetooth"
            else -> "builtin"
        }

        private fun describe(device: AudioDeviceInfo?): String =
            if (device == null) "default" else "${inputTypeLabel(device)}:${device.productName}#${device.id}"

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
