import Foundation
import Compression

/// gzip 解压：标准流式循环，内存占用恒定（<2MB），
/// 避免 78MB gz → 395MB sqlite 一次性驻留内存被系统杀掉。
enum Gzip {

    enum GzipError: LocalizedError {
        case openInput, openOutput, badHeader, stream, shortOutput
        var errorDescription: String? {
            switch self {
            case .openInput: return "无法读取内置压缩包"
            case .openOutput: return "无法写入解压文件"
            case .badHeader: return "压缩包格式不正确"
            case .stream: return "解压过程失败"
            case .shortOutput: return "解压结果不完整"
            }
        }
    }

    /// 把 gzip 文件流式解压到目标路径，返回解压字节数。
    @discardableResult
    static func decompress(_ source: URL, to destination: URL) throws -> Int64 {
        guard let input = InputStream(url: source) else { throw GzipError.openInput }
        input.open()
        defer { input.close() }

        try consumeHeader(input)

        // 先清掉可能存在的半截文件
        try? FileManager.default.removeItem(at: destination)
        guard FileManager.default.createFile(atPath: destination.path, contents: nil),
              let output = FileHandle(forWritingAtPath: destination.path) else {
            throw GzipError.openOutput
        }
        defer { try? output.close() }

        var stream = compression_stream(
            dst_ptr: UnsafeMutablePointer<UInt8>(bitPattern: 1)!,
            dst_size: 0,
            src_ptr: UnsafePointer<UInt8>(bitPattern: 1)!,
            src_size: 0,
            state: nil
        )
        guard compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK else {
            throw GzipError.stream
        }
        defer { compression_stream_destroy(&stream) }

        let inSize = 1 << 18     // 256 KB
        let outSize = 1 << 20    // 1 MB
        var inBuf = [UInt8](repeating: 0, count: inSize)
        var outBuf = [UInt8](repeating: 0, count: outSize)
        var total: Int64 = 0
        var inputEOF = false
        var done = false

        while !done {
            // 1) 需要更多输入就去读
            if stream.src_size == 0 && !inputEOF {
                let n = input.read(&inBuf, maxLength: inSize)
                if n < 0 { throw GzipError.stream }
                if n == 0 {
                    inputEOF = true
                } else {
                    inBuf.withUnsafeBufferPointer { buf in
                        stream.src_ptr = buf.baseAddress!
                        stream.src_size = n
                    }
                }
            }

            // 2) 解压一轮
            outBuf.withUnsafeMutableBufferPointer { dst in
                stream.dst_ptr = dst.baseAddress!
                stream.dst_size = outSize
            }
            let flags = Int32(COMPRESSION_STREAM_FINALIZE.rawValue)
            let rc = compression_stream_process(&stream, inputEOF ? flags : 0)

            if rc == COMPRESSION_STATUS_ERROR { throw GzipError.stream }

            let produced = outSize - stream.dst_size
            if produced > 0 {
                let chunk = Data(bytes: outBuf, count: produced)
                try output.write(contentsOf: chunk)
                total += Int64(produced)
            }

            if rc == COMPRESSION_STATUS_END { done = true; break }

            // 3) 没有进展且输入也没了 → 结束（防止死循环）
            if produced == 0 && stream.src_size == 0 && inputEOF { done = true }
        }

        try output.synchronize()
        if total <= 0 { throw GzipError.shortOutput }
        return total
    }

    /// 跳过 RFC1952 头部（含可选字段）
    private static func consumeHeader(_ input: InputStream) throws {
        var header = [UInt8](repeating: 0, count: 10)
        var got = 0
        while got < 10 {
            let n = input.read(&header[got], maxLength: 10 - got)
            if n <= 0 { throw GzipError.badHeader }
            got += n
        }
        guard header[0] == 0x1f, header[1] == 0x8b, header[2] == 0x08 else { throw GzipError.badHeader }
        let flg = header[3]

        if flg & 0x04 != 0 { // FEXTRA
            var xlen = [UInt8](repeating: 0, count: 2)
            guard input.read(&xlen, maxLength: 2) == 2 else { throw GzipError.badHeader }
            let len = Int(xlen[0]) | (Int(xlen[1]) << 8)
            guard len > 0 else { return }
            var skipped = 0
            var buf = [UInt8](repeating: 0, count: min(len, 4096))
            while skipped < len {
                let want = min(4096, len - skipped)
                let n = input.read(&buf, maxLength: want)
                if n <= 0 { throw GzipError.badHeader }
                skipped += n
            }
        }
        if flg & 0x08 != 0 { try skipZeroTerminated(input) } // FNAME
        if flg & 0x10 != 0 { try skipZeroTerminated(input) } // FCOMMENT
        if flg & 0x02 != 0 {                                  // FHCRC
            var crc = [UInt8](repeating: 0, count: 2)
            guard input.read(&crc, maxLength: 2) == 2 else { throw GzipError.badHeader }
        }
    }

    private static func skipZeroTerminated(_ input: InputStream) throws {
        var byte: UInt8 = 0
        var guardCount = 0
        while input.read(&byte, maxLength: 1) == 1 {
            if byte == 0 { return }
            guardCount += 1
            if guardCount > 65536 { throw GzipError.badHeader }
        }
        throw GzipError.badHeader
    }
}
