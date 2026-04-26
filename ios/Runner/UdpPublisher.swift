import Darwin
import Foundation

final class TcpPublisher {

    private let port: UInt16
    private let label: String
    private let acceptQueue: DispatchQueue
    private let writeQueue: DispatchQueue
    private let muxer = MpegTsMuxer()
    private var listenFd: Int32 = -1
    private var clientFd: Int32 = -1
    private let clientLock = NSLock()
    private var running = false

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
        guard Darwin.listen(fd, 1) == 0 else {
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

            clientLock.lock()
            if clientFd >= 0 {
                Darwin.close(clientFd)
            }
            clientFd = cfd
            clientLock.unlock()
            NSLog("TcpPublisher[\(label)] client connected")
        }
    }

    func publish(annexB: Data, ptsUs: Int64, isKeyframe: Bool) {
        clientLock.lock()
        let fd = clientFd
        clientLock.unlock()
        guard fd >= 0 else { return }

        let packets = muxer.wrapAccessUnit(payload: annexB, ptsUs: ptsUs, isKeyframe: isKeyframe)
        var combined = Data(capacity: packets.count * MpegTsMuxer.packetSize)
        for p in packets { combined.append(p) }

        let label = self.label
        writeQueue.async { [weak self] in
            let total = combined.count
            var offset = 0
            combined.withUnsafeBytes { raw in
                guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
                while offset < total {
                    let sent = Darwin.send(fd, base.advanced(by: offset), total - offset, 0)
                    if sent <= 0 {
                        if sent < 0, errno == EINTR { continue }
                        NSLog("TcpPublisher[\(label)] send failed errno=\(errno), dropping client")
                        self?.disconnectClient()
                        return
                    }
                    offset += sent
                }
            }
        }
    }

    private func disconnectClient() {
        clientLock.lock()
        if clientFd >= 0 {
            Darwin.close(clientFd)
            clientFd = -1
        }
        clientLock.unlock()
    }

    func close() {
        running = false
        let lfd = listenFd
        listenFd = -1
        if lfd >= 0 { Darwin.close(lfd) }
        disconnectClient()
    }
}
