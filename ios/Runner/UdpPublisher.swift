import Darwin
import Foundation

final class TcpPublisher {

    struct Snapshot {
        let datagrams: Int64
        let bytes: Int64
        let errors: Int64
    }

    private let port: UInt16
    private let label: String
    private let acceptQueue: DispatchQueue
    private let writeQueue: DispatchQueue
    private let muxer = MpegTsMuxer()
    private var listenFd: Int32 = -1
    private var clientFds: [Int32] = []
    private var running = false

    private let counterLock = NSLock()
    private var txDatagrams: Int64 = 0
    private var txBytes: Int64 = 0
    private var txErrors: Int64 = 0

    func snapshot() -> Snapshot {
        counterLock.lock()
        defer { counterLock.unlock() }
        return Snapshot(datagrams: txDatagrams, bytes: txBytes, errors: txErrors)
    }

    init(port: Int, label: String) {
        self.port = UInt16(port)
        self.label = label
        self.acceptQueue = DispatchQueue(label: "livegrid.tcp.accept.\(label)", qos: .userInitiated)
        self.writeQueue = DispatchQueue(label: "livegrid.tcp.write.\(label)", qos: .userInitiated)
    }

    func open() {
        guard listenFd < 0 else { return }
        let fd = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        guard fd >= 0 else {
            NSLog("TcpPublisher[\(label)] socket failed errno=\(errno)")
            return
        }

        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
        var nosigpipe: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &nosigpipe, socklen_t(MemoryLayout<Int32>.size))

        var sa = sockaddr_in()
        sa.sin_family = sa_family_t(AF_INET)
        sa.sin_port = port.bigEndian
        sa.sin_addr.s_addr = in_addr_t(0).bigEndian
        sa.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)

        let bindResult = withUnsafePointer(to: &sa) { saPtr -> Int32 in
            saPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.bind(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            NSLog("TcpPublisher[\(label)] bind failed port=\(port) errno=\(errno)")
            Darwin.close(fd)
            return
        }
        guard Darwin.listen(fd, 8) == 0 else {
            NSLog("TcpPublisher[\(label)] listen failed errno=\(errno)")
            Darwin.close(fd)
            return
        }

        listenFd = fd
        running = true
        NSLog("TcpPublisher[\(label)] listening on :\(port)")
        acceptQueue.async { [weak self] in
            self?.acceptLoop()
        }
    }

    private func acceptLoop() {
        while running {
            var clientAddr = sockaddr_in()
            var len = socklen_t(MemoryLayout<sockaddr_in>.size)
            let cfd = withUnsafeMutablePointer(to: &clientAddr) { caPtr -> Int32 in
                caPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                    Darwin.accept(listenFd, sockPtr, &len)
                }
            }
            if !running { if cfd >= 0 { Darwin.close(cfd) }; return }
            if cfd < 0 {
                if errno == EINTR { continue }
                usleep(100_000)
                continue
            }

            var nodelay: Int32 = 1
            setsockopt(cfd, IPPROTO_TCP, TCP_NODELAY, &nodelay, socklen_t(MemoryLayout<Int32>.size))
            var nosigpipe: Int32 = 1
            setsockopt(cfd, SOL_SOCKET, SO_NOSIGPIPE, &nosigpipe, socklen_t(MemoryLayout<Int32>.size))
            var sndBuf: Int32 = 4 * 1024 * 1024
            setsockopt(cfd, SOL_SOCKET, SO_SNDBUF, &sndBuf, socklen_t(MemoryLayout<Int32>.size))

            let newFd = cfd
            let label = self.label
            writeQueue.async { [weak self] in
                guard let self = self else { Darwin.close(newFd); return }
                self.clientFds.append(newFd)
                NSLog("TcpPublisher[\(label)] client connected (total=\(self.clientFds.count))")
            }
        }
    }

    func publish(annexB: Data, ptsUs: Int64, isKeyframe: Bool) {
        let packets = muxer.wrapAccessUnit(payload: annexB, ptsUs: ptsUs, isKeyframe: isKeyframe)
        var combined = Data(capacity: packets.count * MpegTsMuxer.packetSize)
        for p in packets { combined.append(p) }

        let label = self.label
        writeQueue.async { [weak self] in
            guard let self = self else { return }
            if self.clientFds.isEmpty { return }

            let total = combined.count
            var stillAlive: [Int32] = []
            stillAlive.reserveCapacity(self.clientFds.count)
            var anyOk = false
            var droppedCount = 0

            combined.withUnsafeBytes { raw in
                guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
                for fd in self.clientFds {
                    var offset = 0
                    var failed = false
                    while offset < total {
                        let sent = Darwin.send(fd, base.advanced(by: offset), total - offset, 0)
                        if sent <= 0 {
                            if sent < 0, errno == EINTR { continue }
                            failed = true
                            break
                        }
                        offset += sent
                    }
                    if failed {
                        Darwin.close(fd)
                        droppedCount += 1
                    } else {
                        stillAlive.append(fd)
                        anyOk = true
                    }
                }
            }

            if droppedCount > 0 {
                NSLog("TcpPublisher[\(label)] dropped \(droppedCount) client(s), \(stillAlive.count) remaining")
            }
            self.clientFds = stillAlive

            self.counterLock.lock()
            if anyOk {
                self.txDatagrams &+= 1
                self.txBytes &+= Int64(total)
            }
            if droppedCount > 0 {
                self.txErrors &+= Int64(droppedCount)
            }
            self.counterLock.unlock()
        }
    }

    func close() {
        running = false
        let lfd = listenFd
        listenFd = -1
        if lfd >= 0 { Darwin.close(lfd) }
        writeQueue.async { [weak self] in
            guard let self = self else { return }
            for fd in self.clientFds { Darwin.close(fd) }
            self.clientFds.removeAll()
        }
    }
}
