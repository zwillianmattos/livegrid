package br.com.wanmind.livegrid.stream

import android.util.Log
import br.com.wanmind.livegrid.encoder.MpegTsMuxer
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong

class TcpPublisher(
    private val port: Int,
    private val label: String,
) {

    data class Snapshot(
        val datagrams: Long,
        val bytes: Long,
        val errors: Long,
    )

    private val muxer = MpegTsMuxer()
    private val running = AtomicBoolean(false)
    private var server: ServerSocket? = null
    private var client: Socket? = null
    private val clientLock = Any()
    private val acceptThread = Executors.newSingleThreadExecutor { r ->
        Thread(r, "tcp-accept-$label").apply { isDaemon = true }
    }
    private val writeThread = Executors.newSingleThreadExecutor { r ->
        Thread(r, "tcp-write-$label").apply { isDaemon = true }
    }

    private val txDatagrams = AtomicLong(0)
    private val txBytes = AtomicLong(0)
    private val txErrors = AtomicLong(0)

    fun open() {
        if (running.getAndSet(true)) return
        try {
            val s = ServerSocket().apply {
                reuseAddress = true
                bind(InetSocketAddress(port))
            }
            server = s
            Log.i(TAG, "$label listening tcp://0.0.0.0:$port")
            acceptThread.execute { acceptLoop(s) }
        } catch (t: Throwable) {
            Log.e(TAG, "$label open falhou: ${t.message}")
            running.set(false)
        }
    }

    private fun acceptLoop(s: ServerSocket) {
        while (running.get()) {
            try {
                val sock = s.accept()
                sock.tcpNoDelay = true
                runCatching { sock.sendBufferSize = 4 * 1024 * 1024 }
                synchronized(clientLock) {
                    client?.let { runCatching { it.close() } }
                    client = sock
                }
                Log.i(TAG, "$label client connected ${sock.inetAddress?.hostAddress}")
            } catch (t: Throwable) {
                if (!running.get()) return
                txErrors.incrementAndGet()
                Log.w(TAG, "$label accept: ${t.message}")
            }
        }
    }

    fun publish(annexB: ByteArray, ptsUs: Long, isKeyframe: Boolean) {
        val sock = synchronized(clientLock) { client } ?: return
        val packets = muxer.wrapAccessUnit(annexB, ptsUs, isKeyframe)
        val total = packets.size * MpegTsMuxer.PACKET_SIZE
        val combined = ByteArray(total)
        var offset = 0
        for (p in packets) {
            System.arraycopy(p, 0, combined, offset, MpegTsMuxer.PACKET_SIZE)
            offset += MpegTsMuxer.PACKET_SIZE
        }
        writeThread.execute {
            try {
                sock.getOutputStream().write(combined)
                txDatagrams.incrementAndGet()
                txBytes.addAndGet(total.toLong())
            } catch (t: Throwable) {
                txErrors.incrementAndGet()
                Log.w(TAG, "$label send: ${t.message}, dropping client")
                disconnectClient()
            }
        }
    }

    private fun disconnectClient() {
        synchronized(clientLock) {
            client?.let { runCatching { it.close() } }
            client = null
        }
    }

    fun snapshot(): Snapshot = Snapshot(
        datagrams = txDatagrams.get(),
        bytes = txBytes.get(),
        errors = txErrors.get(),
    )

    fun close() {
        if (!running.getAndSet(false)) return
        runCatching { server?.close() }
        server = null
        disconnectClient()
        acceptThread.shutdownNow()
        writeThread.shutdownNow()
    }

    companion object {
        private const val TAG = "TcpPublisher"
    }
}
