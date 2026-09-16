import Foundation

final class LoopbackServer: @unchecked Sendable {
  enum Behavior: Sendable {
    case hang
    case respond(status: Int, headers: [String: String] = [:], body: Data = Data(), initialBytes: Int = .max, bodyDelay: TimeInterval = 0)
    case dropBody
  }

  let port: UInt16
  private let fd: Int32
  private let lock = NSLock()
  private var stopped = false
  private var heads: [String] = []

  var url: URL { URL(string: "http://127.0.0.1:\(port)")! }
  var requests: [String] { lock.withLock { heads } }
  var hits: Int { requests.count }

  init(_ behavior: Behavior) {
    let fd = socket(AF_INET, SOCK_STREAM, 0)
    var addr = sockaddr_in()
    addr.sin_family = sa_family_t(AF_INET)
    addr.sin_addr.s_addr = inet_addr("127.0.0.1")
    var length = socklen_t(MemoryLayout<sockaddr_in>.size)
    withUnsafeMutablePointer(to: &addr) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        _ = bind(fd, $0, length)
        _ = getsockname(fd, $0, &length)
      }
    }
    listen(fd, 16)
    self.fd = fd
    port = UInt16(bigEndian: addr.sin_port)
    if case .hang = behavior { return }
    _ = fcntl(fd, F_SETFL, O_NONBLOCK)
    Thread { [self] in serve(behavior) }.start()
  }

  func stop() {
    lock.withLock {
      guard !stopped else { return }
      stopped = true
      close(fd)
    }
  }

  private func serve(_ behavior: Behavior) {
    while true {
      var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
      _ = poll(&pfd, 1, 50)
      let client: Int32? = lock.withLock {
        guard !stopped else { return nil }
        return accept(fd, nil, nil)
      }
      guard let client else { return }
      guard client >= 0 else { continue }
      _ = fcntl(client, F_SETFL, 0)
      var on: Int32 = 1
      setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
      handle(client, behavior)
      close(client)
    }
  }

  private func handle(_ client: Int32, _ behavior: Behavior) {
    var head = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)
    while head.range(of: Data("\r\n\r\n".utf8)) == nil {
      let count = read(client, &buffer, buffer.count)
      guard count > 0 else { return }
      head.append(contentsOf: buffer[0..<count])
    }
    lock.withLock { heads.append(String(decoding: head, as: UTF8.self)) }

    switch behavior {
    case .hang:
      return
    case let .respond(status, headers, body, initialBytes, bodyDelay):
      write(client, status: status, headers: headers, contentLength: body.count)
      let split = min(initialBytes, body.count)
      write(client, body.prefix(split))
      guard split < body.count else { return }
      Thread.sleep(forTimeInterval: bodyDelay)
      write(client, body.dropFirst(split))
    case .dropBody:
      write(client, status: 200, headers: [:], contentLength: 10_000)
      write(client, Data(repeating: 0x61, count: 1_000))
    }
  }

  private func write(_ client: Int32, status: Int, headers: [String: String], contentLength: Int) {
    var head = "HTTP/1.1 \(status) Status\r\nContent-Length: \(contentLength)\r\nConnection: close\r\n"
    for (name, value) in headers {
      head += "\(name): \(value)\r\n"
    }
    write(client, Data((head + "\r\n").utf8))
  }

  private func write(_ client: Int32, _ data: Data) {
    data.withUnsafeBytes { raw in
      var offset = 0
      while offset < raw.count {
        let sent = Darwin.write(client, raw.baseAddress! + offset, raw.count - offset)
        guard sent > 0 else { return }
        offset += sent
      }
    }
  }
}
