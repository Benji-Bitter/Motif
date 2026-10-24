import Foundation
import SQLite3

/// One typed column value for binds and results.
public enum SQLiteValue: Equatable, Sendable {
    case text(String)
    case integer(Int64)
    case real(Double)
    case blob(Data)
    case null

    var text: String? { if case .text(let s) = self { return s } ; return nil }
    var integer: Int64? { if case .integer(let i) = self { return i } ; return nil }
    var real: Double? { if case .real(let r) = self { return r } ; return nil }
    var blob: Data? { if case .blob(let d) = self { return d } ; return nil }
}

public enum SQLiteError: Error, Equatable, Sendable {
    case openFailed(String)
    case prepareFailed(String)
    case stepFailed(String)
    case bindFailed(String)
}

/// Minimal synchronous SQLite wrapper. All access is serialized by the owning
/// actor (LibraryStore), so a single connection is fine.
final class SQLiteDatabase {
    private var handle: OpaquePointer?

    init(path: String) throws {
        if sqlite3_open(path, &handle) != SQLITE_OK {
            let message = handle.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            throw SQLiteError.openFailed(message)
        }
    }

    deinit { sqlite3_close(handle) }

    func execute(_ sql: String) throws {
        if sqlite3_exec(handle, sql, nil, nil, nil) != SQLITE_OK {
            throw SQLiteError.stepFailed(lastError())
        }
    }

    @discardableResult
    func run(_ sql: String, _ params: [SQLiteValue] = []) throws -> Int {
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        try bind(params, to: stmt)
        let rc = sqlite3_step(stmt)
        guard rc == SQLITE_DONE || rc == SQLITE_ROW else {
            throw SQLiteError.stepFailed(lastError())
        }
        return Int(sqlite3_changes(handle))
    }

    func query(_ sql: String, _ params: [SQLiteValue] = []) throws -> [[String: SQLiteValue]] {
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        try bind(params, to: stmt)
        var rows: [[String: SQLiteValue]] = []
        while true {
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_DONE { break }
            guard rc == SQLITE_ROW else { throw SQLiteError.stepFailed(lastError()) }
            var row: [String: SQLiteValue] = [:]
            let count = sqlite3_column_count(stmt)
            for i in 0..<count {
                let name = String(cString: sqlite3_column_name(stmt, i))
                switch sqlite3_column_type(stmt, i) {
                case SQLITE_INTEGER:
                    row[name] = .integer(sqlite3_column_int64(stmt, i))
                case SQLITE_FLOAT:
                    row[name] = .real(sqlite3_column_double(stmt, i))
                case SQLITE_BLOB:
                    if let ptr = sqlite3_column_blob(stmt, i) {
                        row[name] = .blob(Data(bytes: ptr, count: Int(sqlite3_column_bytes(stmt, i))))
                    } else {
                        row[name] = .blob(Data())
                    }
                case SQLITE_NULL:
                    row[name] = .null
                default:
                    row[name] = .text(String(cString: sqlite3_column_text(stmt, i)))
                }
            }
            rows.append(row)
        }
        return rows
    }

    private func prepare(_ sql: String) throws -> OpaquePointer? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SQLiteError.prepareFailed(lastError())
        }
        return stmt
    }

    private func bind(_ params: [SQLiteValue], to stmt: OpaquePointer?) throws {
        for (index, value) in params.enumerated() {
            let i = Int32(index + 1)
            let rc: Int32
            switch value {
            case .text(let s):
                rc = sqlite3_bind_text(stmt, i, s, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            case .integer(let n):
                rc = sqlite3_bind_int64(stmt, i, n)
            case .real(let r):
                rc = sqlite3_bind_double(stmt, i, r)
            case .blob(let d):
                rc = d.withUnsafeBytes { ptr in
                    sqlite3_bind_blob(stmt, i, ptr.baseAddress, Int32(d.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                }
            case .null:
                rc = sqlite3_bind_null(stmt, i)
            }
            guard rc == SQLITE_OK else { throw SQLiteError.bindFailed(lastError()) }
        }
    }

    private func lastError() -> String {
        handle.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown sqlite error"
    }
}
