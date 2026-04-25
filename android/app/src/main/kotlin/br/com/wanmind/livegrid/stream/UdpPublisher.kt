package br.com.wanmind.livegrid.stream

import android.util.Log
import br.com.wanmind.livegrid.encoder.MpegTsMuxer
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong

class UdpPublisher(
    private val host: String,
    private val port: Int,
    private val label: String,
) {

    data class Snapshot(
        val datagrams: Long,
        val bytes: Long,
        val errors: Long,
    )

    private val muxer = MpegTsMuxer()
    private var socket: DatagramSocket? = null
    private var address: InetAddress? = null
    private val opened = AtomicBoolean(false)

    private val sendBuf = ByteArray(PACKETS_PER_DATAGRAM * MpegTsMuxer.PACKET_SIZE)
    private val sendPacket = DatagramPacket(sendBuf, sendBuf.size)

    private val txDatagrams = AtomicLong(0)
    private val txBytes = AtomicLong(0)
    private val txErrors = AtomicLong(0)

    fun open() {
        if (opened.getAndSet(true)) return
        try {
            socket = DatagramSocket()
            val addr = InetAddress.getByName(host)
            address = addr
            sendPacket.address = addr
            sendPacket.port = port
            Log.i(TAG, "$label udp://$host:$port ok")
        } catch (t: Throwable) {
            Log.e(TAG, "$label open falhou: ${t.message}")
            opened.set(false)
        }
    }

    fun publish(annexB: ByteArray, ptsUs: Long, isKeyframe: Boolean) {
        val s = socket ?: return
        address ?: return
        try {
            val packets = muxer.wrapAccessUnit(annexB, ptsUs, isKeyframe)
            var i = 0
            while (i < packets.size) {
                val count = minOf(PACKETS_PER_DATAGRAM, packets.size - i)
                val length = count * MpegTsMuxer.PACKET_SIZE
                for (j in 0 until count) {
                    System.arraycopy(packets[i + j], 0, sendBuf, j * MpegTsMuxer.PACKET_SIZE, MpegTsMuxer.PACKET_SIZE)
                }
                sendPacket.setData(sendBuf, 0, length)
                s.send(sendPacket)
                txDatagrams.incrementAndGet()
                txBytes.addAndGet(length.toLong())
                i += count
            }
        } catch (t: Throwable) {
            txErrors.incrementAndGet()
            Log.w(TAG, "$label publish falhou: ${t.message}")
        }
    }

    fun snapshot(): Snapshot = Snapshot(
        datagrams = txDatagrams.get(),
        bytes = txBytes.get(),
        errors = txErrors.get(),
    )

    fun close() {
        if (!opened.getAndSet(false)) return
        try {
            socket?.close()
        } catch (_: Throwable) {
        }
        socket = null
        address = null
    }

    companion object {
        private const val TAG = "UdpPublisher"
        private const val PACKETS_PER_DATAGRAM = 7
    }
}
