import Foundation
import SQLite3

/// Persistent SQLite storage for translation history and word lookups
final class TranslationStore: @unchecked Sendable {
    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "com.transreader.store", qos: .userInitiated)

    init() {
        let configDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".transreader")
        try? FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)

        let dbPath = configDir.appendingPathComponent("translations.db").path

        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            appLog("[DB] Failed to open database at \(dbPath)")
            db = nil
            return
        }

        createTables()
    }

    deinit {
        sqlite3_close(db)
    }

    // MARK: - Schema

    private func createTables() {
        let translationsSQL = """
        CREATE TABLE IF NOT EXISTS translations (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp REAL NOT NULL,
            source_text TEXT NOT NULL,
            sentences TEXT NOT NULL,
            source_app TEXT DEFAULT '',
            source_url TEXT DEFAULT '',
            elapsed_ms INTEGER DEFAULT 0,
            created_at TEXT DEFAULT (datetime('now', 'localtime'))
        );
        """

        let lookupsSQL = """
        CREATE TABLE IF NOT EXISTS word_lookups (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp TEXT NOT NULL,
            word TEXT NOT NULL,
            result TEXT NOT NULL,
            source_app TEXT DEFAULT '',
            source_url TEXT DEFAULT '',
            created_at TEXT NOT NULL DEFAULT (datetime('now'))
        );
        """

        exec(translationsSQL)
        exec(lookupsSQL)

        // Indexes for query performance
        exec("CREATE INDEX IF NOT EXISTS idx_translations_timestamp ON translations(timestamp);")
        exec("CREATE INDEX IF NOT EXISTS idx_translations_source_app ON translations(source_app);")
        exec("CREATE INDEX IF NOT EXISTS idx_translations_created_at ON translations(created_at);")
        exec("CREATE INDEX IF NOT EXISTS idx_word_lookups_timestamp ON word_lookups(timestamp);")
        exec("CREATE INDEX IF NOT EXISTS idx_word_lookups_word ON word_lookups(word);")
        exec("CREATE INDEX IF NOT EXISTS idx_word_lookups_created_at ON word_lookups(created_at);")
    }

    // MARK: - Save Translation

    func saveTranslation(_ result: TranslationResult, sourceApp: String = "", sourceUrl: String = "") {
        queue.async { [weak self] in
            guard let self = self, let db = self.db else { return }

            let sql = """
            INSERT INTO translations (timestamp, source_text, sentences, source_app, source_url, elapsed_ms)
            VALUES (?, ?, ?, ?, ?, ?);
            """

            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }

            let ts = ISO8601DateFormatter().string(from: result.timestamp)
            let encoder = JSONEncoder()
            let sentencesJSON = (try? encoder.encode(result.sentences)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"

            sqlite3_bind_text(stmt, 1, (ts as NSString).utf8String, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            sqlite3_bind_text(stmt, 2, (result.sourceText as NSString).utf8String, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            sqlite3_bind_text(stmt, 3, (sentencesJSON as NSString).utf8String, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            sqlite3_bind_text(stmt, 4, (sourceApp as NSString).utf8String, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            sqlite3_bind_text(stmt, 5, (sourceUrl as NSString).utf8String, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            sqlite3_bind_int(stmt, 6, Int32(result.elapsedMs))

            let rc = sqlite3_step(stmt)
            if rc != SQLITE_DONE {
                let err = String(cString: sqlite3_errmsg(db))
                appLog("[DB] Save translation failed: \(err) (rc=\(rc))")
            } else {
                appLog("[DB] Saved translation: \(result.sentences.count) sentences, \(sentencesJSON.count) bytes")
            }
        }
    }

    // MARK: - Save Word Lookup

    func saveWordLookup(word: String, result: DictionaryEntry, sourceApp: String = "", sourceUrl: String = "") {
        queue.async { [weak self] in
            guard let self = self, let db = self.db else { return }

            let sql = """
            INSERT INTO word_lookups (timestamp, word, result, source_app, source_url)
            VALUES (?, ?, ?, ?, ?);
            """

            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }

            let ts = ISO8601DateFormatter().string(from: Date())
            let encoder = JSONEncoder()
            let resultJSON = (try? encoder.encode(result)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"

            sqlite3_bind_text(stmt, 1, (ts as NSString).utf8String, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            sqlite3_bind_text(stmt, 2, (word as NSString).utf8String, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            sqlite3_bind_text(stmt, 3, (resultJSON as NSString).utf8String, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            sqlite3_bind_text(stmt, 4, (sourceApp as NSString).utf8String, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            sqlite3_bind_text(stmt, 5, (sourceUrl as NSString).utf8String, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))

            sqlite3_step(stmt)
        }
    }

    // MARK: - Query Reading Dates

    struct ReadingDate: Hashable, Sendable {
        let date: String
        let translationCount: Int
        let lookupCount: Int
    }

    func getReadingDates(limit: Int = 90) -> [ReadingDate] {
        var results: [ReadingDate] = []
        queue.sync { [weak self] in
            guard let self = self, let db = self.db else { return }

            let sql = """
            SELECT date(created_at) as d,
                   SUM(json_array_length(sentences)) as cnt
            FROM translations
            GROUP BY d
            ORDER BY d DESC
            LIMIT ?;
            """

            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int(stmt, 1, Int32(limit))

            while sqlite3_step(stmt) == SQLITE_ROW {
                let date = columnText(stmt, 0)
                guard !date.isEmpty else { continue }
                let count = Int(sqlite3_column_int(stmt, 1))
                results.append(ReadingDate(date: date, translationCount: count, lookupCount: 0))
            }
        }
        return results
    }

    // MARK: - Query Reading Groups (by app/url for a date)

    struct ReadingGroup: Hashable, Sendable {
        let sourceApp: String
        let sourceUrl: String
        let count: Int
    }

    func getReadingGroups(date: String) -> [ReadingGroup] {
        var results: [ReadingGroup] = []
        queue.sync { [weak self] in
            guard let self = self, let db = self.db else { return }

            let sql = """
            SELECT source_app, source_url, COUNT(*) as cnt
            FROM translations
            WHERE date(created_at) = ?
            GROUP BY source_app, source_url
            ORDER BY cnt DESC;
            """

            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, (date as NSString).utf8String, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))

            while sqlite3_step(stmt) == SQLITE_ROW {
                let app = columnText(stmt, 0)
                let url = columnText(stmt, 1)
                let cnt = Int(sqlite3_column_int(stmt, 2))
                results.append(ReadingGroup(sourceApp: app, sourceUrl: url, count: cnt))
            }
        }
        return results
    }

    // MARK: - Query Translations for a date

    func getTranslations(date: String, query: String? = nil, sourceApp: String? = nil, sourceUrl: String? = nil) -> [SavedTranslation] {
        var results: [SavedTranslation] = []
        queue.sync { [weak self] in
            guard let self = self, let db = self.db else { return }

            var sql = """
            SELECT timestamp, source_text, sentences, 'manual', source_app, source_url, elapsed_ms
            FROM translations
            WHERE date(created_at) = ?
            """
            var bindValues: [String] = [date]

            if let q = query, !q.isEmpty {
                let escaped = Self.escapeLike(q)
                sql += " AND (source_text LIKE ? ESCAPE '\\' OR sentences LIKE ? ESCAPE '\\')"
                bindValues.append("%\(escaped)%")
                bindValues.append("%\(escaped)%")
            }
            if let app = sourceApp, !app.isEmpty {
                sql += " AND source_app = ?"
                bindValues.append(app)
            }
            if let url = sourceUrl, !url.isEmpty {
                sql += " AND source_url = ?"
                bindValues.append(url)
            }

            sql += " ORDER BY timestamp DESC;"

            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            for (i, val) in bindValues.enumerated() {
                sqlite3_bind_text(stmt, Int32(i + 1), (val as NSString).utf8String, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            }

            results = self.parseTranslationRows(stmt)
        }
        return results
    }

    // MARK: - Search Translations (cross-date)

    func searchTranslations(query: String, sourceApp: String? = nil, sourceUrl: String? = nil, limit: Int = 100) -> [SavedTranslation] {
        var results: [SavedTranslation] = []
        queue.sync { [weak self] in
            guard let self = self, let db = self.db else { return }

            var sql = """
            SELECT timestamp, source_text, sentences, 'manual', source_app, source_url, elapsed_ms
            FROM translations WHERE 1=1
            """
            var bindValues: [String] = []

            if !query.isEmpty {
                let escaped = Self.escapeLike(query)
                sql += " AND (source_text LIKE ? ESCAPE '\\' OR sentences LIKE ? ESCAPE '\\')"
                bindValues.append("%\(escaped)%")
                bindValues.append("%\(escaped)%")
            }
            if let app = sourceApp, !app.isEmpty {
                sql += " AND source_app = ?"
                bindValues.append(app)
            }
            if let url = sourceUrl, !url.isEmpty {
                sql += " AND source_url = ?"
                bindValues.append(url)
            }

            sql += " ORDER BY timestamp DESC LIMIT ?;"

            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }
            for (i, val) in bindValues.enumerated() {
                sqlite3_bind_text(stmt, Int32(i + 1), (val as NSString).utf8String, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            }
            sqlite3_bind_int(stmt, Int32(bindValues.count + 1), Int32(limit))

            results = self.parseTranslationRows(stmt)
        }
        return results
    }

    func getDistinctSourceApps() -> [String] {
        var results: [String] = []
        queue.sync { [weak self] in
            guard let self = self, let db = self.db else { return }

            let sql = "SELECT DISTINCT source_app FROM translations WHERE source_app != '' ORDER BY source_app;"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }

            while sqlite3_step(stmt) == SQLITE_ROW {
                results.append(columnText(stmt, 0))
            }
        }
        return results
    }

    // MARK: - Shared Helpers

    private func parseTranslationRows(_ stmt: OpaquePointer?) -> [SavedTranslation] {
        var results: [SavedTranslation] = []
        let decoder = JSONDecoder()
        while sqlite3_step(stmt) == SQLITE_ROW {
            let ts = columnText(stmt, 0)
            let sourceText = columnText(stmt, 1)
            let sentencesJSON = columnText(stmt, 2)
            let source = columnText(stmt, 3)
            let sourceApp = columnText(stmt, 4)
            let sourceUrl = columnText(stmt, 5)
            let elapsed = Int(sqlite3_column_int(stmt, 6))

            let sentences = (try? decoder.decode([Sentence].self, from: Data(sentencesJSON.utf8))) ?? []
            // Support both ISO8601 ("2026-04-02T09:59:20Z") and Unix timestamp ("1775095154.38165")
            let timestamp: Date
            if let unixTime = Double(ts) {
                timestamp = Date(timeIntervalSince1970: unixTime)
            } else {
                timestamp = ISO8601DateFormatter().date(from: ts) ?? Date()
            }

            results.append(SavedTranslation(
                timestamp: timestamp,
                sourceText: sourceText,
                sentences: sentences,
                source: TranslationSource(rawValue: source) ?? .manual,
                sourceApp: sourceApp,
                sourceUrl: sourceUrl,
                elapsedMs: elapsed
            ))
        }
        return results
    }

    /// Escape LIKE special characters (%, _, \)
    private static func escapeLike(_ str: String) -> String {
        str.replacingOccurrences(of: "\\", with: "\\\\")
           .replacingOccurrences(of: "%", with: "\\%")
           .replacingOccurrences(of: "_", with: "\\_")
    }

    // MARK: - Stats

    struct URLCount: Sendable, Hashable {
        let url: String
        let count: Int
    }

    struct ReadingStats: Sendable {
        let todayTranslations: Int
        let todayLookups: Int
        let weekTranslations: Int
        let weekLookups: Int
        let monthTranslations: Int
        let monthLookups: Int
        let totalTranslations: Int
        let totalLookups: Int
        let activeApps: [String]
        let topUrls: [URLCount]
    }

    func getStats() -> ReadingStats {
        var todayT = 0, weekT = 0, monthT = 0, totalT = 0
        var todayL = 0, weekL = 0, monthL = 0, totalL = 0
        var activeApps: [String] = []
        var topUrls: [URLCount] = []

        queue.sync { [weak self] in
            guard let self = self, let db = self.db else { return }

            // Translation counts
            let sql1 = """
            SELECT
                COALESCE(SUM(CASE WHEN date(created_at) = date('now') THEN 1 ELSE 0 END), 0),
                COALESCE(SUM(CASE WHEN date(created_at) >= date('now', '-7 days') THEN 1 ELSE 0 END), 0),
                COALESCE(SUM(CASE WHEN date(created_at) >= date('now', '-30 days') THEN 1 ELSE 0 END), 0),
                COUNT(*)
            FROM translations;
            """
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql1, -1, &stmt, nil) == SQLITE_OK {
                if sqlite3_step(stmt) == SQLITE_ROW {
                    todayT = Int(sqlite3_column_int(stmt, 0))
                    weekT = Int(sqlite3_column_int(stmt, 1))
                    monthT = Int(sqlite3_column_int(stmt, 2))
                    totalT = Int(sqlite3_column_int(stmt, 3))
                }
            }
            sqlite3_finalize(stmt); stmt = nil

            // Lookup counts
            let sql2 = """
            SELECT
                COALESCE(SUM(CASE WHEN date(created_at) = date('now') THEN 1 ELSE 0 END), 0),
                COALESCE(SUM(CASE WHEN date(created_at) >= date('now', '-7 days') THEN 1 ELSE 0 END), 0),
                COALESCE(SUM(CASE WHEN date(created_at) >= date('now', '-30 days') THEN 1 ELSE 0 END), 0),
                COUNT(*)
            FROM word_lookups;
            """
            if sqlite3_prepare_v2(db, sql2, -1, &stmt, nil) == SQLITE_OK {
                if sqlite3_step(stmt) == SQLITE_ROW {
                    todayL = Int(sqlite3_column_int(stmt, 0))
                    weekL = Int(sqlite3_column_int(stmt, 1))
                    monthL = Int(sqlite3_column_int(stmt, 2))
                    totalL = Int(sqlite3_column_int(stmt, 3))
                }
            }
            sqlite3_finalize(stmt); stmt = nil

            // Active apps (last 30 days)
            let sql3 = """
            SELECT DISTINCT source_app FROM translations
            WHERE date(created_at) >= date('now', '-30 days') AND source_app != ''
            ORDER BY source_app;
            """
            if sqlite3_prepare_v2(db, sql3, -1, &stmt, nil) == SQLITE_OK {
                while sqlite3_step(stmt) == SQLITE_ROW {
                    activeApps.append(columnText(stmt, 0))
                }
            }
            sqlite3_finalize(stmt); stmt = nil

            // Top URLs (last 30 days, top 5)
            let sql4 = """
            SELECT source_url, COUNT(*) as cnt FROM translations
            WHERE date(created_at) >= date('now', '-30 days') AND source_url != ''
            GROUP BY source_url ORDER BY cnt DESC LIMIT 5;
            """
            if sqlite3_prepare_v2(db, sql4, -1, &stmt, nil) == SQLITE_OK {
                while sqlite3_step(stmt) == SQLITE_ROW {
                    let url = columnText(stmt, 0)
                    let cnt = Int(sqlite3_column_int(stmt, 1))
                    topUrls.append(URLCount(url: url, count: cnt))
                }
            }
            sqlite3_finalize(stmt)
        }

        return ReadingStats(
            todayTranslations: todayT, todayLookups: todayL,
            weekTranslations: weekT, weekLookups: weekL,
            monthTranslations: monthT, monthLookups: monthL,
            totalTranslations: totalT, totalLookups: totalL,
            activeApps: activeApps, topUrls: topUrls
        )
    }

    // MARK: - Helpers

    private func columnText(_ stmt: OpaquePointer?, _ col: Int32) -> String {
        guard let ptr = sqlite3_column_text(stmt, col) else { return "" }
        return String(cString: ptr)
    }

    private func exec(_ sql: String) {
        var errMsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &errMsg) != SQLITE_OK {
            if let errMsg = errMsg {
                appLog("[DB] SQL Error: \(String(cString: errMsg))")
                sqlite3_free(errMsg)
            }
        }
    }
}

struct SavedTranslation: Hashable, Sendable {
    let timestamp: Date
    let sourceText: String
    let sentences: [Sentence]
    let source: TranslationSource
    let sourceApp: String
    let sourceUrl: String
    let elapsedMs: Int

    func hash(into hasher: inout Hasher) {
        hasher.combine(timestamp)
    }

    static func == (lhs: SavedTranslation, rhs: SavedTranslation) -> Bool {
        lhs.timestamp == rhs.timestamp
    }
}
