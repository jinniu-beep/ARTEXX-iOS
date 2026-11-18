import Foundation
import Compression

/// gzip 解压：流式写入目标文件，内存占用恒定（约 1MB），
/// 避免 78MB gz → 395MB sqlite 时一次性驻留内存被系统杀掉。
enum Gzip {

    /// 把 gzip 数据解压到指定文件。返回解压后的字节数。
    @discardableResult
    static func decompress(_ source: URL, to destination: URL) throws -> Int64 {
        guard let input = InputStream(url: source) else { throw GzipError.openInput }
        input.open()
        defer { input.close() }

        // 读 gzip 头，跳过可选字段，拿到 deflate 起点
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
            var skip = [UInt8](repeating: 0, count: len)
            guard input.read(&skip, maxLength: len) == len else { throw GzipError.badHeader }
        }
        if flg & 0x08 != 0 { try skipZeroTerminated(input) } // FNAME
        if flg & 0x10 != 0 { try skipZeroTerminated(input) } // FCOMMENT
        if flg & 0x02 != 0 { // FHCRC
            var crc = [UInt8](repeating: 0, count: 2)
            guard input.read(&crc, maxLength: 2) == 2 else { throw GzipError.badHeader }
        }

        // 目标文件
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        guard let output = FileHandle(forWritingAtPath: destination.path) else { throw GzipError.openOutput }
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

        let inSize = 1 << 18          // 256 KB 读入
        let outSize = 1 << 20         // 1 MB 输出
        var inBuf = [UInt8](repeating: 0, count: inSize)
        var outBuf = [UInt8](repeating: 0, count: outSize)
        var total: Int64 = 0
        var status = COMPRESSION_STATUS_OK

        repeat {
            let read = input.read(&inBuf, maxLength: inSize)
            if read < 0 { throw GzipError.stream }
            let eof = read == 0
            stream.src_ptr = inBuf.withUnsafeBufferPointer { $0.baseAddress! }
            stream.src_size = read

            repeat {
                let produced = outBuf.withUnsafeMutableBufferPointer { dst -> Int in
                    stream.dst_ptr = dst.baseAddress!
                    stream.dst_size = outSize
                    return compression_stream_process(&stream, eof ? Int32(COMPRESSION_STREAM_FINALIZE.rawValue) : 0)
                        == COMPRESSION_STATUS_ERROR ? -1 : outSize - stream.dst_size
                }
                if produced < 0 { throw GzipError.stream }
                if produced > 0 {
                    try outBuf.withUnsafeBytes { raw in
                        try output.write(contentsOf: raw[0..<produced])
                    }
                    total += Int64(produced)
                }
                status = eof && stream.src_size == 0 ? COMPRESSION_STATUS_END : COMPRESSION_STATUS_OK
                if produced == 0 { break }
            } while stream.src_size > 0

            if eof { break }
        } while status != COMPRESSION_STATUS_END

        try output.synchronize()
        return total
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

    enum GzipError: LocalizedError {
        case openInput, openOutput, badHeader, stream
        var errorDescription: String? {
            switch self {
            case .openInput: return "无法读取内置压缩包"
            case .openOutput: return "无法写入解压文件"
            case .badHeader: return "压缩包格式不正确"
            case .stream: return "解压过程失败"
            }
        }
    }
}
