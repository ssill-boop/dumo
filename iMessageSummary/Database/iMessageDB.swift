import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Apple Cocoa epoch is 2001-01-01 00:00:00 UTC; Unix epoch is 1970-01-01.
private let appleEpochOffsetSeconds: TimeInterval = 978_307_200

struct ContactRow: Hashable {
    let handleRowID: Int64
    let handleID: String
    let displayName: String?
}

enum MessageWindow: String, CaseIterable {
    case oneWeek
    case twoWeeks
    case oneMonth

    /// Foundation Date at the start of the window.
    func cutoffDate(now: Date = Date()) -> Date? {
        let component: Calendar.Component
        let value: Int
        switch self {
        case .oneWeek: component = .weekOfYear; value = -1
        case .twoWeeks: component = .weekOfYear; value = -2
        case .oneMonth: component = .month; value = -1
        }
        return Calendar.current.date(byAdding: component, value: value, to: now)
    }

    /// Cutoff in Apple-epoch nanoseconds (the unit the message.date column uses
    /// on macOS 10.13+).
    func cutoffAppleEpochNanos(now: Date = Date()) -> Int64? {
        guard let cutoff = cutoffDate(now: now) else { return nil }
        let appleSeconds = cutoff.timeIntervalSince1970 - appleEpochOffsetSeconds
        return Int64(appleSeconds * 1_000_000_000)
    }
}

final class iMessageDB {
    enum Error: Swift.Error, CustomStringConvertible {
        case databaseMissing(path: String)
        case openFailed(code: Int32, message: String)
        case prepareFailed(message: String, sql: String)

        var description: String {
            switch self {
            case .databaseMissing(let path):
                return "chat.db not found at \(path) (Full Disk Access may not be granted)"
            case .openFailed(let code, let message):
                return "sqlite open failed (code \(code)): \(message)"
            case .prepareFailed(let message, _):
                return "sqlite prepare failed: \(message)"
            }
        }
    }

    static var defaultPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Messages/chat.db", isDirectory: false)
            .path
    }

    let path: String
    private var db: OpaquePointer?

    init(path: String = iMessageDB.defaultPath) {
        self.path = path
    }

    deinit { close() }

    func open() throws {
        guard FileManager.default.fileExists(atPath: path) else {
            throw Error.databaseMissing(path: path)
        }
        let result = sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil)
        guard result == SQLITE_OK else {
            let message = lastErrorMessage() ?? "unknown"
            sqlite3_close(db)
            db = nil
            throw Error.openFailed(code: result, message: message)
        }
    }

    func close() {
        guard db != nil else { return }
        sqlite3_close(db)
        db = nil
    }

    // MARK: - Queries

    /// Fuzzy lookup: tries to match against handle.id (phone/email) and
    /// chat.display_name (sometimes set for named threads / group chats).
    func findContact(matching query: String) throws -> ContactRow? {
        let sql = """
        SELECT handle.ROWID, handle.id, chat.display_name
        FROM handle
        LEFT JOIN chat_handle_join ON handle.ROWID = chat_handle_join.handle_id
        LEFT JOIN chat ON chat_handle_join.chat_id = chat.ROWID
        WHERE handle.id LIKE ?
           OR chat.display_name LIKE ?
        LIMIT 1;
        """
        let pattern = "%\(query)%"
        var result: ContactRow?
        try prepare(sql) { stmt in
            sqlite3_bind_text(stmt, 1, pattern, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, pattern, -1, SQLITE_TRANSIENT)
            if sqlite3_step(stmt) == SQLITE_ROW {
                result = ContactRow(
                    handleRowID: sqlite3_column_int64(stmt, 0),
                    handleID: readText(stmt, column: 1) ?? "",
                    displayName: readText(stmt, column: 2)
                )
            }
        }
        return result
    }

    /// Messages for a handle, only ones whose ROWID is greater than `sinceRowID`.
    /// Pass 0 to get every message (subject to the SQL filters).
    func fetchMessages(forHandleID handleID: String, sinceRowID: Int64 = 0) throws -> [Message] {
        let sql = """
        SELECT message.ROWID, message.date, message.is_from_me, message.text
        FROM message
        LEFT JOIN handle ON message.handle_id = handle.ROWID
        WHERE handle.id = ?
          AND message.text IS NOT NULL
          AND message.text != ''
          AND message.associated_message_type = 0
          AND message.ROWID > ?
        ORDER BY message.date ASC;
        """
        return try fetchMessages(sql: sql) { stmt in
            sqlite3_bind_text(stmt, 1, handleID, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(stmt, 2, sinceRowID)
        }
    }

    /// Messages for a handle within a configurable time window.
    func fetchMessages(forHandleID handleID: String, window: MessageWindow) throws -> [Message] {
        let sql: String
        if let cutoff = window.cutoffAppleEpochNanos() {
            sql = """
            SELECT message.ROWID, message.date, message.is_from_me, message.text
            FROM message
            LEFT JOIN handle ON message.handle_id = handle.ROWID
            WHERE handle.id = ?
              AND message.text IS NOT NULL
              AND message.text != ''
              AND message.associated_message_type = 0
              AND message.date >= \(cutoff)
            ORDER BY message.date ASC;
            """
        } else {
            sql = """
            SELECT message.ROWID, message.date, message.is_from_me, message.text
            FROM message
            LEFT JOIN handle ON message.handle_id = handle.ROWID
            WHERE handle.id = ?
              AND message.text IS NOT NULL
              AND message.text != ''
              AND message.associated_message_type = 0
            ORDER BY message.date ASC;
            """
        }
        return try fetchMessages(sql: sql) { stmt in
            sqlite3_bind_text(stmt, 1, handleID, -1, SQLITE_TRANSIENT)
        }
    }

    // MARK: - Internals

    private func fetchMessages(sql: String, bind: (OpaquePointer?) -> Void) throws -> [Message] {
        var messages: [Message] = []
        try prepare(sql) { stmt in
            bind(stmt)
            while sqlite3_step(stmt) == SQLITE_ROW {
                let rowID = sqlite3_column_int64(stmt, 0)
                let appleNanos = sqlite3_column_int64(stmt, 1)
                let isFromMe = sqlite3_column_int(stmt, 2) != 0
                let text = readText(stmt, column: 3) ?? ""
                messages.append(Message(
                    rowID: rowID,
                    date: dateFromAppleEpochNanos(appleNanos),
                    isFromMe: isFromMe,
                    text: text
                ))
            }
        }
        return messages
    }

    private func prepare(_ sql: String, run: (OpaquePointer?) -> Void) throws {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw Error.prepareFailed(message: lastErrorMessage() ?? "unknown", sql: sql)
        }
        run(stmt)
    }

    private func readText(_ stmt: OpaquePointer?, column: Int32) -> String? {
        guard let cString = sqlite3_column_text(stmt, column) else { return nil }
        return String(cString: cString)
    }

    private func lastErrorMessage() -> String? {
        guard let cString = sqlite3_errmsg(db) else { return nil }
        return String(cString: cString)
    }

    private func dateFromAppleEpochNanos(_ nanos: Int64) -> Date {
        let unixSeconds = TimeInterval(nanos) / 1_000_000_000 + appleEpochOffsetSeconds
        return Date(timeIntervalSince1970: unixSeconds)
    }
}

#if DEBUG
extension iMessageDB {
    /// One-shot console smoke test for step 2. Override the lookup target by
    /// setting a `TEST_HANDLE` env var (phone number, email, or display-name
    /// fragment) in the Xcode scheme.
    static func runConsoleSmokeTest() {
        let query = ProcessInfo.processInfo.environment["TEST_HANDLE"]
            ?? "+15555555555"
        let db = iMessageDB()
        do {
            try db.open()
            print("[iMessageDB] opened \(db.path)")
            guard let contact = try db.findContact(matching: query) else {
                print("[iMessageDB] no contact matched '\(query)'")
                return
            }
            print("[iMessageDB] match: handle=\(contact.handleID) displayName=\(contact.displayName ?? "nil")")
            let messages = try db.fetchMessages(forHandleID: contact.handleID, window: .oneMonth)
            print("[iMessageDB] \(messages.count) messages in last month")
            let formatter = ISO8601DateFormatter()
            for msg in messages.suffix(20) {
                let who = msg.isFromMe ? "Me" : (contact.displayName ?? contact.handleID)
                print("[\(formatter.string(from: msg.date))] \(who): \(msg.text)")
            }
        } catch {
            print("[iMessageDB] error: \(error)")
        }
    }
}
#endif
