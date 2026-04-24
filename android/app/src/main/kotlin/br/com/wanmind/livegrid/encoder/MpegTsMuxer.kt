package br.com.wanmind.livegrid.encoder

class MpegTsMuxer(
    private val videoPid: Int = 0x0100,
    private val pmtPid: Int = 0x1000,
    private val psiIntervalFrames: Int = 30,
) {

    private var patCc = 0
    private var pmtCc = 0
    private var videoCc = 0
    private var accessUnitCount = 0

    fun wrapAccessUnit(payload: ByteArray, ptsUs: Long, isKeyframe: Boolean): List<ByteArray> {
        val out = ArrayList<ByteArray>()
        if (isKeyframe || accessUnitCount % psiIntervalFrames == 0) {
            out += buildPat()
            out += buildPmt()
        }
        out += buildPes(payload, ptsUs, isKeyframe)
        accessUnitCount++
        return out
    }

    private fun buildPat(): ByteArray {
        val p = ByteArray(PACKET_SIZE) { 0xFF.toByte() }
        p[0] = SYNC_BYTE
        p[1] = 0x40
        p[2] = 0x00
        p[3] = (0x10 or patCc).toByte()
        patCc = (patCc + 1) and 0x0F
        p[4] = 0x00
        var i = 5
        val sectionStart = i
        p[i++] = 0x00
        p[i++] = 0xB0.toByte()
        p[i++] = 0x0D
        p[i++] = 0x00
        p[i++] = 0x01
        p[i++] = 0xC1.toByte()
        p[i++] = 0x00
        p[i++] = 0x00
        p[i++] = 0x00
        p[i++] = 0x01
        p[i++] = ((0xE0 or ((pmtPid shr 8) and 0x1F))).toByte()
        p[i++] = (pmtPid and 0xFF).toByte()
        val crc = crc32(p, sectionStart, i - sectionStart)
        p[i++] = ((crc ushr 24) and 0xFF).toByte()
        p[i++] = ((crc ushr 16) and 0xFF).toByte()
        p[i++] = ((crc ushr 8) and 0xFF).toByte()
        p[i++] = (crc and 0xFF).toByte()
        return p
    }

    private fun buildPmt(): ByteArray {
        val p = ByteArray(PACKET_SIZE) { 0xFF.toByte() }
        p[0] = SYNC_BYTE
        p[1] = (0x40 or ((pmtPid shr 8) and 0x1F)).toByte()
        p[2] = (pmtPid and 0xFF).toByte()
        p[3] = (0x10 or pmtCc).toByte()
        pmtCc = (pmtCc + 1) and 0x0F
        p[4] = 0x00
        var i = 5
        val sectionStart = i
        p[i++] = 0x02
        p[i++] = 0xB0.toByte()
        p[i++] = 0x12
        p[i++] = 0x00
        p[i++] = 0x01
        p[i++] = 0xC1.toByte()
        p[i++] = 0x00
        p[i++] = 0x00
        p[i++] = ((0xE0 or ((videoPid shr 8) and 0x1F))).toByte()
        p[i++] = (videoPid and 0xFF).toByte()
        p[i++] = 0xF0.toByte()
        p[i++] = 0x00
        p[i++] = H264_STREAM_TYPE
        p[i++] = ((0xE0 or ((videoPid shr 8) and 0x1F))).toByte()
        p[i++] = (videoPid and 0xFF).toByte()
        p[i++] = 0xF0.toByte()
        p[i++] = 0x00
        val crc = crc32(p, sectionStart, i - sectionStart)
        p[i++] = ((crc ushr 24) and 0xFF).toByte()
        p[i++] = ((crc ushr 16) and 0xFF).toByte()
        p[i++] = ((crc ushr 8) and 0xFF).toByte()
        p[i++] = (crc and 0xFF).toByte()
        return p
    }

    private fun buildPes(payload: ByteArray, ptsUs: Long, isKeyframe: Boolean): List<ByteArray> {
        val pts90 = (ptsUs * 9L) / 100L
        val header = buildPesHeader(pts90)
        val pes = ByteArray(header.size + payload.size)
        System.arraycopy(header, 0, pes, 0, header.size)
        System.arraycopy(payload, 0, pes, header.size, payload.size)

        val packets = ArrayList<ByteArray>(pes.size / PAYLOAD_SIZE + 1)
        var offset = 0
        var first = true
        while (offset < pes.size) {
            val pkt = ByteArray(PACKET_SIZE)
            pkt[0] = SYNC_BYTE
            val pusi = if (first) 0x40 else 0x00
            pkt[1] = (pusi or ((videoPid shr 8) and 0x1F)).toByte()
            pkt[2] = (videoPid and 0xFF).toByte()

            val remaining = pes.size - offset
            val headerLen: Int
            val afSize: Int
            val includePcr = first && isKeyframe

            var provisionalPayload = if (includePcr) PAYLOAD_SIZE - 8 else PAYLOAD_SIZE
            val chunkSize: Int
            val needsStuffing: Boolean
            if (remaining < provisionalPayload) {
                chunkSize = remaining
                needsStuffing = true
            } else {
                chunkSize = provisionalPayload
                needsStuffing = false
            }

            if (includePcr || needsStuffing) {
                afSize = if (includePcr) {
                    val pcrAf = 7
                    if (remaining < PAYLOAD_SIZE - pcrAf - 1) {
                        PAYLOAD_SIZE - remaining - 1
                    } else {
                        pcrAf
                    }
                } else {
                    PAYLOAD_SIZE - remaining - 1
                }
                pkt[3] = (0x30 or videoCc).toByte()
                var i = 4
                pkt[i++] = afSize.toByte()
                if (afSize > 0) {
                    if (includePcr) {
                        pkt[i++] = 0x50
                        writePcr(pkt, i, pts90 * 300L)
                        i += 6
                        val stuffing = afSize - 7
                        if (stuffing > 0) {
                            for (k in 0 until stuffing) pkt[i + k] = 0xFF.toByte()
                            i += stuffing
                        }
                    } else {
                        pkt[i++] = 0x00
                        val stuffing = afSize - 1
                        if (stuffing > 0) {
                            for (k in 0 until stuffing) pkt[i + k] = 0xFF.toByte()
                            i += stuffing
                        }
                    }
                }
                headerLen = i
                val actualPayload = PACKET_SIZE - headerLen
                val realChunk = minOf(actualPayload, remaining)
                System.arraycopy(pes, offset, pkt, headerLen, realChunk)
                offset += realChunk
            } else {
                pkt[3] = (0x10 or videoCc).toByte()
                headerLen = 4
                System.arraycopy(pes, offset, pkt, headerLen, chunkSize)
                offset += chunkSize
            }

            videoCc = (videoCc + 1) and 0x0F
            packets += pkt
            first = false
        }
        return packets
    }

    private fun buildPesHeader(pts90: Long): ByteArray {
        val h = ByteArray(14)
        h[0] = 0x00
        h[1] = 0x00
        h[2] = 0x01
        h[3] = VIDEO_STREAM_ID.toByte()
        h[4] = 0x00
        h[5] = 0x00
        h[6] = 0x80.toByte()
        h[7] = 0x80.toByte()
        h[8] = 0x05
        h[9] = (0x20 or (((pts90 ushr 30) and 0x07) shl 1).toInt() or 0x01).toByte()
        h[10] = ((pts90 ushr 22) and 0xFF).toByte()
        h[11] = ((((pts90 ushr 15) and 0x7F) shl 1) or 0x01).toByte()
        h[12] = ((pts90 ushr 7) and 0xFF).toByte()
        h[13] = (((pts90 and 0x7F) shl 1) or 0x01).toByte()
        return h
    }

    private fun writePcr(buf: ByteArray, offset: Int, pcr27: Long) {
        val base = pcr27 / 300L
        val ext = (pcr27 % 300L).toInt()
        buf[offset] = ((base ushr 25) and 0xFF).toByte()
        buf[offset + 1] = ((base ushr 17) and 0xFF).toByte()
        buf[offset + 2] = ((base ushr 9) and 0xFF).toByte()
        buf[offset + 3] = ((base ushr 1) and 0xFF).toByte()
        buf[offset + 4] = (((base and 0x01L) shl 7).toInt() or 0x7E or ((ext ushr 8) and 0x01)).toByte()
        buf[offset + 5] = (ext and 0xFF).toByte()
    }

    companion object {
        const val PACKET_SIZE = 188
        private const val PAYLOAD_SIZE = 184
        private const val SYNC_BYTE = 0x47.toByte()
        private const val H264_STREAM_TYPE = 0x1B.toByte()
        private const val VIDEO_STREAM_ID = 0xE0

        private val CRC_TABLE = IntArray(256).also { table ->
            for (i in 0 until 256) {
                var c = i shl 24
                repeat(8) {
                    c = if ((c.toLong() and 0x80000000L) != 0L) {
                        (c shl 1) xor 0x04C11DB7
                    } else {
                        c shl 1
                    }
                }
                table[i] = c
            }
        }

        fun crc32(data: ByteArray, offset: Int, length: Int): Int {
            var crc = -1
            for (i in offset until offset + length) {
                val idx = ((crc ushr 24) xor (data[i].toInt() and 0xFF)) and 0xFF
                crc = (crc shl 8) xor CRC_TABLE[idx]
            }
            return crc
        }
    }
}
