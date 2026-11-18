import Combine
import Foundation
import SQLite3

/// 内置 CVE 知识库（只读）：首次启动把打包的 gzip 解到 Application Support，
/// 之后用 SQLite + FTS5 做毫秒级检索。
final class CVEDatabase: ObservableObject {
    static let shared = CVEDatabase()
    private var handle: OpaquePointer?
    private let queue = DispatchQueue(label: "artex.cve.db")
    private(set) var ready = false
    @Published private(set) var totalRows = 0

    private var dbPath: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ARTEXX", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("cve.sqlite")
    }

    @Published private(set) var phase: Phase = .idle
    enum Phase: Equatable { case idle, preparing, ready, failed(String) }

    /// 后台准备数据库：解压 → 打开 → 建索引。任何阶段失败都不会卡住 UI。
    func bootstrap() {
        guard phase == .idle || isFailed else { return }
        phase = .preparing
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let result = self.prepare()
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self.phase = .ready
                case .failure(let err):
                    self.phase = .failed(err.localizedDescription)
                    NSLog("[ARTEXX] CVE 库准备失败: \(err.localizedDescription)")
                }
            }
        }
    }

    private var isFailed: Bool {
        if case .failed = phase { return true }
        return false
    }

    private func prepare() -> Result<Void, Error> {
        let target = dbPath

        // 1) 需要解压时先解压（流式，不占内存）
        if !FileManager.default.fileExists(atPath: target.path) {
            guard let gz = Bundle.main.url(forResource: "cve", withExtension: "sqlite.gz") else {
                if let plain = Bundle.main.url(forResource: "cve", withExtension: "sqlite") {
                    try? FileManager.default.copyItem(at: plain, to: target)
                } else {
                    return .failure(Gzip.GzipError.openInput)
                }
                return open(target)
            }
            do {
                try Gzip.decompress(gz, to: target)
            } catch {
                return .failure(error)
            }
        }
        return open(target)
    }

    private func open(_ target: URL) -> Result<Void, Error> {
        if sqlite3_open_v2(target.path, &handle, SQLITE_OPEN_READONLY, nil) != SQLITE_OK {
            handle = nil
            try? FileManager.default.removeItem(at: target)
            return .failure(Gzip.GzipError.openOutput)
        }
        sqlite3_exec(handle, "PRAGMA query_only=1; PRAGMA cache_size=-8000;", nil, nil, nil)
        let count = scalarInt("SELECT count(*) FROM cve") ?? 0
        guard count > 0 else {
            try? FileManager.default.removeItem(at: target)
            return .failure(Gzip.GzipError.shortOutput)
        }
        totalRows = count
        ready = true
        NSLog("[ARTEXX] CVE 库就绪，共 \(totalRows) 条")
        return .success(Void())
    }

    private func scalarInt(_ sql: String) -> Int? {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return Int(sqlite3_column_int64(stmt, 0))
    }

    // MARK: - 检索
    func search(_ keyword: String, severity: String? = nil, vendor: String? = nil,
                minScore: Double = 0, limit: Int = 80) -> [CVERow] {
        guard ready else { return [] }
        var rows: [CVERow] = []
        let kw = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        var sql: String
        var binds: [String] = []

        if kw.isEmpty {
            sql = "SELECT c.id,c.title,c.severity,c.score,c.cwe,c.vendor,c.published,c.refs,c.tags,c.vec,c.rng,c.has_exp,c.exp_id FROM cve c WHERE c.score >= ?"
            binds = ["\(minScore)"]
        } else {
            sql = """
            SELECT c.id,c.title,c.severity,c.score,c.cwe,c.vendor,c.published,c.refs,c.tags,c.vec,c.rng,c.has_exp,c.exp_id
            FROM cve_fts f JOIN cve c ON c.rowid = f.rowid
            WHERE cve_fts MATCH ? AND c.score >= ?
            """
            binds = [Self.ftsQuery(kw), "\(minScore)"]
        }
        if let severity, !severity.isEmpty {
            sql += " AND c.severity = '\(severity)'"
        }
        if let vendor, !vendor.isEmpty {
            sql += " AND c.vendor = '\(vendor)'"
        }
        sql += " ORDER BY c.score DESC, c.published DESC LIMIT \(max(1, min(limit, 500)))"

        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (i, b) in binds.enumerated() {
            sqlite3_bind_text(stmt, Int32(i + 1), (b as NSString).utf8String, -1, transient)
        }
        while sqlite3_step(stmt) == SQLITE_ROW {
            rows.append(makeRow(stmt))
        }
        return rows
    }

    func detail(_ id: String) -> (desc: String, refs: Int)? {
        guard ready else { return nil }
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        let sql = "SELECT desc, refs FROM cve WHERE id = ? LIMIT 1"
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        sqlite3_bind_text(stmt, 1, (id as NSString).utf8String, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return (text(stmt, 0), Int(sqlite3_column_int(stmt, 1)))
    }

    func vendors(limit: Int = 60) -> [(String, Int)] {
        guard ready else { return [] }
        var out: [(String, Int)] = []
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        let sql = "SELECT vendor, count(*) c FROM cve GROUP BY vendor ORDER BY c DESC LIMIT \(limit)"
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        while sqlite3_step(stmt) == SQLITE_ROW { out.append((text(stmt, 0), Int(sqlite3_column_int(stmt, 1)))) }
        return out
    }

    func bySkill(_ skillID: String, limit: Int = 40) -> [CVERow] {
        guard ready else { return [] }
        var rows: [CVERow] = []
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        let sql = "SELECT id,title,severity,score,cwe,vendor,published,refs,tags,vec,rng,has_exp,exp_id FROM cve WHERE tags LIKE ? ORDER BY score DESC LIMIT \(limit)"
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        sqlite3_bind_text(stmt, 1, ("%" + skillID + "%" as NSString).utf8String, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        while sqlite3_step(stmt) == SQLITE_ROW {
            rows.append(makeRow(stmt))
        }
        return rows
    }

    func stats() -> (total: Int, critical: Int, high: Int, medium: Int, vendors: Int) {
        guard ready else { return (0, 0, 0, 0, 0) }
        return (scalarInt("SELECT count(*) FROM cve") ?? 0,
                scalarInt("SELECT count(*) FROM cve WHERE severity='critical'") ?? 0,
                scalarInt("SELECT count(*) FROM cve WHERE severity='high'") ?? 0,
                scalarInt("SELECT count(*) FROM cve WHERE severity='medium'") ?? 0,
                scalarInt("SELECT count(DISTINCT vendor) FROM cve") ?? 0)
    }

    private func makeRow(_ stmt: OpaquePointer?) -> CVERow {
        CVERow(id: text(stmt, 0), title: text(stmt, 1), severity: text(stmt, 2),
               score: sqlite3_column_double(stmt, 3), cwe: text(stmt, 4),
               vendor: text(stmt, 5), published: text(stmt, 6),
               refs: Int(sqlite3_column_int(stmt, 7)),
               skills: text(stmt, 8).split(separator: ",").map(String.init),
               vector: text(stmt, 9), ranges: text(stmt, 10),
               hasExploit: sqlite3_column_int(stmt, 11) == 1,
               exploitId: text(stmt, 12))
    }

    /// 读取预生成的四段式指引（JSON 字符串）
    func guidance(_ id: String) -> CVEGuidance? {
        guard ready else { return nil }
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(handle, "SELECT guidance FROM cve WHERE id = ? LIMIT 1", -1, &stmt, nil) == SQLITE_OK else { return nil }
        sqlite3_bind_text(stmt, 1, (id as NSString).utf8String, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        guard sqlite3_step(stmt) == SQLITE_ROW, let c = sqlite3_column_text(stmt, 1) else { return nil }
        let json = String(cString: c)
        return try? JSONDecoder().decode(CVEGuidance.self, from: Data(json.utf8))
    }

    /// 参考链接（| 分隔）
    func references(_ id: String) -> [String] {
        guard ready else { return [] }
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(handle, "SELECT refjson FROM cve WHERE id = ? LIMIT 1", -1, &stmt, nil) == SQLITE_OK else { return [] }
        sqlite3_bind_text(stmt, 1, (id as NSString).utf8String, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        guard sqlite3_step(stmt) == SQLITE_ROW, let c = sqlite3_column_text(stmt, 1) else { return [] }
        return String(cString: c).split(separator: "|").map(String.init).filter { !$0.isEmpty }
    }

    private func text(_ stmt: OpaquePointer?, _ idx: Int32) -> String {
        guard let c = sqlite3_column_text(stmt, idx) else { return "" }
        return String(cString: c)
    }

    /// FTS5 查询串：多词 AND，自动补前缀匹配，去掉特殊符号。
    private static func ftsQuery(_ raw: String) -> String {
        let tokens = raw.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._")).inverted)
            .filter { $0.count > 1 }
            .prefix(6)
        if tokens.isEmpty { return "\"\(raw)\"" }
        return tokens.map { "\($0)*" }.joined(separator: " AND ")
    }
}
