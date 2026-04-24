package br.com.wanmind.livegrid.encoder

import java.util.concurrent.atomic.AtomicLong

class BitrateMeter {

    private val totalBytes = AtomicLong(0)
    private var lastSampleBytes = 0L
    private var lastSampleNanos = 0L

    fun record(bytes: Int) {
        totalBytes.addAndGet(bytes.toLong())
    }

    fun sampleBps(): Int {
        val nowNanos = System.nanoTime()
        val now = totalBytes.get()
        if (lastSampleNanos == 0L) {
            lastSampleNanos = nowNanos
            lastSampleBytes = now
            return 0
        }
        val dtNanos = nowNanos - lastSampleNanos
        if (dtNanos < MIN_INTERVAL_NANOS) return 0
        val dBytes = now - lastSampleBytes
        lastSampleBytes = now
        lastSampleNanos = nowNanos
        return ((dBytes * 8L * 1_000_000_000L) / dtNanos).toInt()
    }

    companion object {
        private const val MIN_INTERVAL_NANOS = 100_000_000L
    }
}
