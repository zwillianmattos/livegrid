package br.com.wanmind.livegrid.stream

import android.util.Log
import br.com.wanmind.livegrid.encoder.MpegTsMuxer
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.util.concurrent.atomic.AtomicBoolean

class UdpPublisher(
    private val host: String,
    private val port: Int,
    private val label: String,
) {

    private val muxer = MpegTsMuxer()
    private var socket: DatagramSocket? = null
    private var address: InetAddress? = null
    private val opened = AtomicBoolean(false)

    fun open() {
        if (opened.getAndSet(true)) return
        try {
            socket = DatagramSocket()
            address = InetAddress.getByName(host)
            Log.i(TAG, "$label udp://$host:$port ok")
        } catch (t: Throwable) {
            Log.e(TAG, "$label open falhou: ${t.message}")
            opened.set(false)
        }
    }

    fun publish(annexB: ByteArray, ptsUs: Long, isKeyframe: Boolean) {
        val s = socket ?: return
        val addr = address ?: return
        try {
            val packets = muxer.wrapAccessUnit(annexB, ptsUs, isKeyframe)
            var i = 0
            while (i < packets.size) {
                val count = minOf(PACKETS_PER_DATAGRAM, packets.size - i)
                val buf = ByteArray(count * MpegTsMuxer.PACKET_SIZE)
                for (j in 0 until count) {
                    System.arraycopy(packets[i + j], 0, buf, j * MpegTsMuxer.PACKET_SIZE, MpegTsMuxer.PACKET_SIZE)
                }
                s.send(DatagramPacket(buf, buf.size, addr, port))
                i += count
            }
        } catch (t: Throwable) {
            Log.w(TAG, "$label publish falhou: ${t.message}")
        }
    }

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
