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
    private val clients = mutableListOf<Socket>()
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
                val total: Int
                synchronized(clientLock) {
                    clients.add(sock)
                    total = clients.size
                }
                Log.i(TAG, "$label client connected ${sock.inetAddress?.hostAddress} (total=$total)")
            } catch (t: Throwable) {
                if (!running.get()) return
                txErrors.incrementAndGet()
                Log.w(TAG, "$label accept: ${t.message}")
            }
        }
    }

    fun publish(annexB: ByteArray, ptsUs: Long, isKeyframe: Boolean) {
        val snapshot: List<Socket> = synchronized(clientLock) {
            if (clients.isEmpty()) return
            clients.toList()
        }
        val packets = muxer.wrapAccessUnit(annexB, ptsUs, isKeyframe)
        val total = packets.size * MpegTsMuxer.PACKET_SIZE
        val combined = ByteArray(total)
        var offset = 0
        for (p in packets) {
            System.arraycopy(p, 0, combined, offset, MpegTsMuxer.PACKET_SIZE)
            offset += MpegTsMuxer.PACKET_SIZE
        }
        writeThread.execute {
            val dead = mutableListOf<Socket>()
            var anyOk = false
            for (sock in snapshot) {
                try {
                    sock.getOutputStream().write(combined)
                    anyOk = true
                } catch (t: Throwable) {
                    dead.add(sock)
                    Log.w(TAG, "$label send: ${t.message}, dropping client ${sock.inetAddress?.hostAddress}")
                }
            }
            if (anyOk) {
                txDatagrams.incrementAndGet()
                txBytes.addAndGet(total.toLong())
            }
            if (dead.isNotEmpty()) {
                txErrors.addAndGet(dead.size.toLong())
                synchronized(clientLock) {
                    for (s in dead) {
                        clients.remove(s)
                        runCatching { s.close() }
                    }
                }
            }
        }
    }

    private fun disconnectAllClients() {
        synchronized(clientLock) {
            for (s in clients) runCatching { s.close() }
            clients.clear()
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
        disconnectAllClients()
        acceptThread.shutdownNow()
        writeThread.shutdownNow()
    }

    companion object {
        private const val TAG = "TcpPublisher"
    }
}
