import Foundation

final class MpegTsMuxer {

    static let packetSize = 188
    private static let payloadSize = 184
    private static let syncByte: UInt8 = 0x47
    private static let h264StreamType: UInt8 = 0x1B
    private static let videoStreamId: UInt8 = 0xE0

    private static let crcTable: [UInt32] = {
        var table = [UInt32](repeating: 0, count: 256)
        for i in 0..<256 {
            var c = UInt32(i) << 24
            for _ in 0..<8 {
                if (c & 0x80000000) != 0 {
                    c = (c << 1) ^ 0x04C11DB7
                } else {
                    c <<= 1
                }
            }
            table[i] = c
        }
        return table
    }()

    private let videoPid: Int
    private let pmtPid: Int
    private let psiIntervalFrames: Int
    private var patCc: UInt8 = 0
    private var pmtCc: UInt8 = 0
    private var videoCc: UInt8 = 0
    private var accessUnitCount: Int = 0

    init(videoPid: Int = 0x0100, pmtPid: Int = 0x1000, psiIntervalFrames: Int = 30) {
        self.videoPid = videoPid
        self.pmtPid = pmtPid
        self.psiIntervalFrames = psiIntervalFrames
    }

    func wrapAccessUnit(payload: Data, ptsUs: Int64, isKeyframe: Bool) -> [Data] {
        var out: [Data] = []
        if isKeyframe || accessUnitCount % psiIntervalFrames == 0 {
            out.append(buildPat())
            out.append(buildPmt())
        }
        out.append(contentsOf: buildPes(payload: payload, ptsUs: ptsUs, isKeyframe: isKeyframe))
        accessUnitCount += 1
        return out
    }

    private func buildPat() -> Data {
        var p = [UInt8](repeating: 0xFF, count: Self.packetSize)
        p[0] = Self.syncByte
        p[1] = 0x40
        p[2] = 0x00
        p[3] = 0x10 | (patCc & 0x0F)
        patCc = (patCc &+ 1) & 0x0F
        p[4] = 0x00
        var i = 5
        let sectionStart = i
        p[i] = 0x00; i += 1
        p[i] = 0xB0; i += 1
        p[i] = 0x0D; i += 1
        p[i] = 0x00; i += 1
        p[i] = 0x01; i += 1
        p[i] = 0xC1; i += 1
        p[i] = 0x00; i += 1
        p[i] = 0x00; i += 1
        p[i] = 0x00; i += 1
        p[i] = 0x01; i += 1
        p[i] = UInt8(0xE0 | ((pmtPid >> 8) & 0x1F)); i += 1
        p[i] = UInt8(pmtPid & 0xFF); i += 1
        let crc = Self.crc32(Array(p[sectionStart..<i]))
        p[i] = UInt8((crc >> 24) & 0xFF); i += 1
        p[i] = UInt8((crc >> 16) & 0xFF); i += 1
        p[i] = UInt8((crc >> 8) & 0xFF); i += 1
        p[i] = UInt8(crc & 0xFF)
        return Data(p)
    }

    private func buildPmt() -> Data {
        var p = [UInt8](repeating: 0xFF, count: Self.packetSize)
        p[0] = Self.syncByte
        p[1] = UInt8(0x40 | ((pmtPid >> 8) & 0x1F))
        p[2] = UInt8(pmtPid & 0xFF)
        p[3] = 0x10 | (pmtCc & 0x0F)
        pmtCc = (pmtCc &+ 1) & 0x0F
        p[4] = 0x00
        var i = 5
        let sectionStart = i
        p[i] = 0x02; i += 1
        p[i] = 0xB0; i += 1
        p[i] = 0x12; i += 1
        p[i] = 0x00; i += 1
        p[i] = 0x01; i += 1
        p[i] = 0xC1; i += 1
        p[i] = 0x00; i += 1
        p[i] = 0x00; i += 1
        p[i] = UInt8(0xE0 | ((videoPid >> 8) & 0x1F)); i += 1
        p[i] = UInt8(videoPid & 0xFF); i += 1
        p[i] = 0xF0; i += 1
        p[i] = 0x00; i += 1
        p[i] = Self.h264StreamType; i += 1
        p[i] = UInt8(0xE0 | ((videoPid >> 8) & 0x1F)); i += 1
        p[i] = UInt8(videoPid & 0xFF); i += 1
        p[i] = 0xF0; i += 1
        p[i] = 0x00; i += 1
        let crc = Self.crc32(Array(p[sectionStart..<i]))
        p[i] = UInt8((crc >> 24) & 0xFF); i += 1
        p[i] = UInt8((crc >> 16) & 0xFF); i += 1
        p[i] = UInt8((crc >> 8) & 0xFF); i += 1
        p[i] = UInt8(crc & 0xFF)
        return Data(p)
    }

    private func buildPes(payload: Data, ptsUs: Int64, isKeyframe: Bool) -> [Data] {
        let pts90 = (ptsUs * 9) / 100
        let header = buildPesHeader(pts90: pts90)
        var pes = Data(capacity: header.count + payload.count)
        pes.append(header)
        pes.append(payload)

        var packets: [Data] = []
        var offset = 0
        var first = true
        while offset < pes.count {
            var pkt = [UInt8](repeating: 0, count: Self.packetSize)
            pkt[0] = Self.syncByte
            let pusi: UInt8 = first ? 0x40 : 0x00
            pkt[1] = UInt8(pusi | UInt8((videoPid >> 8) & 0x1F))
            pkt[2] = UInt8(videoPid & 0xFF)

            let remaining = pes.count - offset
            let includePcr = first && isKeyframe
            var headerLen: Int
            let afSize: Int
            var realChunk: Int

            let provisionalPayload = includePcr ? Self.payloadSize - 8 : Self.payloadSize
            let needsStuffing = remaining < provisionalPayload

            if includePcr || needsStuffing {
                if includePcr {
                    let pcrAf = 7
                    if remaining < Self.payloadSize - pcrAf - 1 {
                        afSize = Self.payloadSize - remaining - 1
                    } else {
                        afSize = pcrAf
                    }
                } else {
                    afSize = Self.payloadSize - remaining - 1
                }
                pkt[3] = 0x30 | (videoCc & 0x0F)
                var i = 4
                pkt[i] = UInt8(afSize); i += 1
                if afSize > 0 {
                    if includePcr {
                        pkt[i] = 0x50; i += 1
                        writePcr(&pkt, offset: i, pcr27: pts90 * 300)
                        i += 6
                        let stuffing = afSize - 7
                        if stuffing > 0 {
                            for k in 0..<stuffing { pkt[i + k] = 0xFF }
                            i += stuffing
                        }
                    } else {
                        pkt[i] = 0x00; i += 1
                        let stuffing = afSize - 1
                        if stuffing > 0 {
                            for k in 0..<stuffing { pkt[i + k] = 0xFF }
                            i += stuffing
                        }
                    }
                }
                headerLen = i
                let actualPayload = Self.packetSize - headerLen
                realChunk = min(actualPayload, remaining)
                pes.withUnsafeBytes { raw in
                    let base = raw.bindMemory(to: UInt8.self).baseAddress!.advanced(by: offset)
                    for k in 0..<realChunk { pkt[headerLen + k] = base[k] }
                }
                offset += realChunk
            } else {
                pkt[3] = 0x10 | (videoCc & 0x0F)
                headerLen = 4
                realChunk = min(remaining, Self.payloadSize)
                pes.withUnsafeBytes { raw in
                    let base = raw.bindMemory(to: UInt8.self).baseAddress!.advanced(by: offset)
                    for k in 0..<realChunk { pkt[headerLen + k] = base[k] }
                }
                offset += realChunk
            }

            videoCc = (videoCc &+ 1) & 0x0F
            packets.append(Data(pkt))
            first = false
        }
        return packets
    }

    private func buildPesHeader(pts90: Int64) -> Data {
        var h = [UInt8](repeating: 0, count: 14)
        h[0] = 0x00
        h[1] = 0x00
        h[2] = 0x01
        h[3] = Self.videoStreamId
        h[4] = 0x00
        h[5] = 0x00
        h[6] = 0x80
        h[7] = 0x80
        h[8] = 0x05
        h[9] = UInt8(0x20 | ((Int((pts90 >> 30) & 0x07) << 1)) | 0x01)
        h[10] = UInt8((pts90 >> 22) & 0xFF)
        h[11] = UInt8((((pts90 >> 15) & 0x7F) << 1) | 0x01)
        h[12] = UInt8((pts90 >> 7) & 0xFF)
        h[13] = UInt8(((pts90 & 0x7F) << 1) | 0x01)
        return Data(h)
    }

    private func writePcr(_ buf: inout [UInt8], offset: Int, pcr27: Int64) {
        let base = pcr27 / 300
        let ext = Int(pcr27 % 300)
        buf[offset] = UInt8((base >> 25) & 0xFF)
        buf[offset + 1] = UInt8((base >> 17) & 0xFF)
        buf[offset + 2] = UInt8((base >> 9) & 0xFF)
        buf[offset + 3] = UInt8((base >> 1) & 0xFF)
        buf[offset + 4] = UInt8(((Int(base & 1) << 7)) | 0x7E | ((ext >> 8) & 0x01))
        buf[offset + 5] = UInt8(ext & 0xFF)
    }

    static func crc32(_ data: [UInt8]) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for b in data {
            let idx = Int(((crc >> 24) ^ UInt32(b)) & 0xFF)
            crc = (crc << 8) ^ Self.crcTable[idx]
        }
        return crc
    }
}
