package br.com.wanmind.livegrid.encoder

import java.util.concurrent.atomic.AtomicLong
import kotlin.math.roundToInt

class BitrateMeter {

    private val totalBytes = AtomicLong(0)

    @Volatile
    private var lastSampleBytes = 0L

    @Volatile
    private var lastSampleNanos = 0L

    @Volatile
    private var smoothedBps = 0.0

    fun record(bytes: Int) {
        if (bytes > 0) {
            totalBytes.addAndGet(bytes.toLong())
        }
    }

    @Synchronized
    fun sampleBps(): Int {
        val nowNanos = System.nanoTime()
        val nowBytes = totalBytes.get()

        if (lastSampleNanos == 0L) {
            lastSampleNanos = nowNanos
            lastSampleBytes = nowBytes
            return 0
        }

        val dtNanos = nowNanos - lastSampleNanos

        if (dtNanos < MIN_INTERVAL_NANOS) {
            return smoothedBps.roundToInt()
        }

        val dBytes = nowBytes - lastSampleBytes
        lastSampleBytes = nowBytes
        lastSampleNanos = nowNanos

        val instantBps = (dBytes * 8.0 * 1_000_000_000.0) / dtNanos

        smoothedBps = if (smoothedBps == 0.0) {
            instantBps
        } else {
            smoothedBps * (1 - ALPHA) + instantBps * ALPHA
        }

        return smoothedBps.roundToInt()
    }

    fun reset() {
        synchronized(this) {
            totalBytes.set(0)
            lastSampleBytes = 0L
            lastSampleNanos = 0L
            smoothedBps = 0.0
        }
    }

    companion object {
        private const val MIN_INTERVAL_NANOS = 200_000_000L // Recalcula a cada 200ms
        private const val ALPHA = 0.25 // Fator de suavização (quanto menor, mais suave)
    }
}