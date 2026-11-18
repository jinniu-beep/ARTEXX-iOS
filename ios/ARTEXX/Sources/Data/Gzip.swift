import Foundation
import Compression

// MARK: - gzip 解压（Apple Compression 框架）
import Compression

enum GzipError: Error { case badHeader, stream }

extension Data {
    /// 解开 gzip 数据（跳过 RFC1952 头，用 zlib raw deflate 流式解压）
    func gunzipped() -> Data? {
        let bytes = [UInt8](self)
        guard bytes.count > 18, bytes[0] == 0x1f, bytes[1] == 0x8b, bytes[2] == 0x08 else { return nil }
        let flg = bytes[3]
        var idx = 10
        if flg & 0x04 != 0 {
            guard idx + 2 <= bytes.count else { return nil }
            let xlen = Int(bytes[idx]) | (Int(bytes[idx + 1]) << 8)
            idx += 2 + xlen
        }
        if flg & 0x08 != 0 { while idx < bytes.count && bytes[idx] != 0 { idx += 1 }; idx += 1 }
        if flg & 0x10 != 0 { while idx < bytes.count && bytes[idx] != 0 { idx += 1 }; idx += 1 }
        if flg & 0x02 != 0 { idx += 2 }
        guard idx < bytes.count else { return nil }

        let body = Data(bytes[idx..<bytes.count])
        var stream = compression_stream(dst_ptr: UnsafeMutablePointer<UInt8>(bitPattern: 1)!,
                                        dst_size: 0,
                                        src_ptr: UnsafePointer<UInt8>(bitPattern: 1)!,
                                        src_size: 0,
                                        state: nil)
        guard compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK else { return nil }
        defer { compression_stream_destroy(&stream) }

        let chunk = 1 << 20
        var out = Data()
        out.reserveCapacity(count * 5)
        var buffer = [UInt8](repeating: 0, count: chunk)
        var result = COMPRESSION_STATUS_OK

        return body.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Data? in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return nil }
            stream.src_ptr = base
            stream.src_size = body.count
            repeat {
                result = buffer.withUnsafeMutableBufferPointer { dst -> compression_status in
                    stream.dst_ptr = dst.baseAddress!
                    stream.dst_size = chunk
                    return compression_stream_process(&stream, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
                }
                let produced = chunk - stream.dst_size
                if produced > 0 { out.append(contentsOf: buffer[0..<produced]) }
                if result == COMPRESSION_STATUS_ERROR { return nil }
            } while result == COMPRESSION_STATUS_OK
            return out.isEmpty ? nil : out
        }
    }
}
