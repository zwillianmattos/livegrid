import Foundation
import Network

final class UdpPublisher {

    private let host: String
    private let port: UInt16
    private let label: String
    private let queue: DispatchQueue
    private let muxer = MpegTsMuxer()
    private var connection: NWConnection?
    private var opened = false

    init(host: String, port: Int, label: String) {
        self.host = host
        self.port = UInt16(port)
        self.label = label
        self.queue = DispatchQueue(label: "livegrid.udp.\(label)")
    }

    func open() {
        guard !opened else { return }
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return }
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: nwPort)
        let conn = NWConnection(to: endpoint, using: .udp)
        conn.stateUpdateHandler = { [label] state in
            NSLog("UdpPublisher[\(label)] state=\(state)")
        }
        conn.start(queue: queue)
        connection = conn
        opened = true
    }

    func publish(annexB: Data, ptsUs: Int64, isKeyframe: Bool) {
        guard opened, let conn = connection else { return }
        let packets = muxer.wrapAccessUnit(payload: annexB, ptsUs: ptsUs, isKeyframe: isKeyframe)
        var i = 0
        while i < packets.count {
            let count = min(7, packets.count - i)
            var datagram = Data(capacity: count * MpegTsMuxer.packetSize)
            for j in 0..<count { datagram.append(packets[i + j]) }
            conn.send(content: datagram, completion: .contentProcessed { error in
                if let e = error { NSLog("udp send: \(e.localizedDescription)") }
            })
            i += count
        }
    }

    func close() {
        connection?.cancel()
        connection = nil
        opened = false
    }
}
