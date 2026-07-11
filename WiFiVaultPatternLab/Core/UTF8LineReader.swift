import Foundation

final class UTF8LineReader {
    private let handle: FileHandle
    private let chunkSize: Int
    private var buffer = Data()
    private var cursor = 0
    private var reachedEnd = false

    init(url: URL, chunkSize: Int = 64 * 1_024) throws {
        handle = try FileHandle(forReadingFrom: url)
        self.chunkSize = max(chunkSize, 4_096)
    }

    deinit {
        try? handle.close()
    }

    func nextLine() throws -> String? {
        while true {
            if cursor < buffer.count,
               let newlineIndex = buffer[cursor...].firstIndex(of: 0x0A) {
                let line = decodeLine(from: cursor, to: newlineIndex)
                cursor = newlineIndex + 1
                compactBufferIfNeeded()
                return line
            }

            if reachedEnd {
                guard cursor < buffer.count else { return nil }
                let line = decodeLine(from: cursor, to: buffer.count)
                cursor = buffer.count
                return line
            }

            let chunk = try handle.read(upToCount: chunkSize) ?? Data()
            if chunk.isEmpty {
                reachedEnd = true
            } else {
                buffer.append(chunk)
            }
        }
    }

    private func decodeLine(from start: Int, to end: Int) -> String {
        var adjustedEnd = end
        if adjustedEnd > start, buffer[adjustedEnd - 1] == 0x0D {
            adjustedEnd -= 1
        }
        return String(decoding: buffer[start..<adjustedEnd], as: UTF8.self)
    }

    private func compactBufferIfNeeded() {
        guard cursor >= 1_048_576 || cursor == buffer.count else { return }
        buffer.removeSubrange(0..<cursor)
        cursor = 0
    }
}
