import Foundation
import SQLite3

final class LabelDatabase {
    private var db: OpaquePointer?
    let url: URL
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    init(url: URL) throws {
        self.url = url
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            let error = failure("Открытие базы"); sqlite3_close(db); db = nil; throw error
        }
        do {
            sqlite3_busy_timeout(db, 3000)
            try exec("PRAGMA foreign_keys=ON; PRAGMA journal_mode=WAL; PRAGMA synchronous=FULL;")
            let version = try rows("PRAGMA user_version").first?.first ?? "0"
            guard Int(version) ?? 0 <= 1 else { throw FoodError.invalid("Эта база создана более новой версией FoodLabel.") }
            try exec("""
                CREATE TABLE IF NOT EXISTS foods(id TEXT PRIMARY KEY, payload BLOB NOT NULL, updated REAL NOT NULL);
                CREATE TABLE IF NOT EXISTS print_jobs(id TEXT PRIMARY KEY, payload BLOB NOT NULL, created REAL NOT NULL,
                  status TEXT NOT NULL, detail TEXT NOT NULL DEFAULT '', transferred INTEGER NOT NULL DEFAULT 0,
                  png BLOB NOT NULL, tspl BLOB NOT NULL);
                CREATE TABLE IF NOT EXISTS settings(key TEXT PRIMARY KEY, value BLOB NOT NULL);
                INSERT OR IGNORE INTO settings(key,value) VALUES('next_barcode','250002');
                PRAGMA user_version=1;
                """)
        } catch { sqlite3_close(db); db = nil; throw error }
    }
    deinit { sqlite3_close(db) }
    private func failure(_ action: String) -> FoodError {
        FoodError.invalid("\(action): \(db.map { String(cString: sqlite3_errmsg($0)) } ?? "база недоступна")")
    }
    private func exec(_ sql: String) throws {
        guard sqlite3_exec(db,sql,nil,nil,nil) == SQLITE_OK else { throw failure("База данных") }
    }
    private func statement(_ sql: String) throws -> OpaquePointer {
        var s: OpaquePointer?
        guard sqlite3_prepare_v2(db,sql,-1,&s,nil) == SQLITE_OK, let s else { throw failure("Подготовка запроса") }; return s
    }
    private func bind(_ data: Data, at index: Int32, to s: OpaquePointer) throws {
        let result = data.withUnsafeBytes { sqlite3_bind_blob(s,index,$0.baseAddress,Int32($0.count),transient) }
        guard result == SQLITE_OK else { throw failure("Запись значения") }
    }
    private func bind(_ text: String, at index: Int32, to s: OpaquePointer) throws {
        guard sqlite3_bind_text(s,index,text,-1,transient) == SQLITE_OK else { throw failure("Запись текста") }
    }
    private func done(_ s: OpaquePointer) throws { guard sqlite3_step(s) == SQLITE_DONE else { throw failure("Сохранение") } }
    private func string(_ s: OpaquePointer,_ col: Int32) -> String { sqlite3_column_text(s,col).map { String(cString: $0) } ?? "" }
    private func data(_ s: OpaquePointer,_ col: Int32) -> Data {
        guard let p = sqlite3_column_blob(s,col) else { return Data() }; return Data(bytes:p,count:Int(sqlite3_column_bytes(s,col)))
    }
    private func rows(_ sql: String) throws -> [[String]] {
        let s = try statement(sql); defer { sqlite3_finalize(s) }; var output:[[String]]=[]
        while true { let r=sqlite3_step(s); if r == SQLITE_DONE { break }; guard r == SQLITE_ROW else { throw failure("Чтение") }; output.append((0..<sqlite3_column_count(s)).map { string(s,$0) }) }; return output
    }
    func saveFood(id: String?, draft: FoodDraft) throws -> String {
        _ = try draft.validated()
        let id = id ?? UUID().uuidString
        let s = try statement("INSERT INTO foods(id,payload,updated) VALUES(?,?,?) ON CONFLICT(id) DO UPDATE SET payload=excluded.payload,updated=excluded.updated")
        defer { sqlite3_finalize(s) }
        try bind(id,at:1,to:s); try bind(JSONEncoder().encode(draft),at:2,to:s)
        sqlite3_bind_double(s,3,Date().timeIntervalSince1970); try done(s); return id
    }
    func foods() throws -> [SavedFood] {
        let s = try statement("SELECT id,payload,updated FROM foods ORDER BY updated DESC"); defer { sqlite3_finalize(s) }
        var result:[SavedFood]=[]
        while true { let r=sqlite3_step(s); if r == SQLITE_DONE { break }; guard r == SQLITE_ROW else { throw failure("Чтение блюд") }
            result.append(SavedFood(id:string(s,0),draft:try JSONDecoder().decode(FoodDraft.self,from:data(s,1)),updated:Date(timeIntervalSince1970:sqlite3_column_double(s,2))))
        }; return result
    }
    func nextBarcode() throws -> String {
        try exec("BEGIN IMMEDIATE")
        do {
            guard let raw=try rows("SELECT value FROM settings WHERE key='next_barcode'").first?.first,
                  let n=Int(raw), (100000...999999).contains(n) else { throw FoodError.invalid("Закончились свободные внутренние штрихкоды.") }
            let s=try statement("UPDATE settings SET value=? WHERE key='next_barcode'"); defer { sqlite3_finalize(s) }
            try bind(String(n+1),at:1,to:s); try done(s); try exec("COMMIT"); return String(n)
        } catch { try? exec("ROLLBACK"); throw error }
    }
    func saveDraft(_ draft: FoodDraft) throws {
        let s=try statement("INSERT INTO settings(key,value) VALUES('draft',?) ON CONFLICT(key) DO UPDATE SET value=excluded.value"); defer { sqlite3_finalize(s) }
        try bind(JSONEncoder().encode(draft),at:1,to:s); try done(s)
    }
    func loadDraft() throws -> FoodDraft? {
        let s=try statement("SELECT value FROM settings WHERE key='draft'"); defer { sqlite3_finalize(s) }
        let r=sqlite3_step(s); if r == SQLITE_DONE { return nil }; guard r == SQLITE_ROW else { throw failure("Чтение черновика") }
        return try JSONDecoder().decode(FoodDraft.self,from:data(s,0))
    }
    func beginJob(draft: FoodDraft, raster: LabelRaster, bytes: Data) throws -> String {
        _ = try draft.validated(); let id=UUID().uuidString
        let s=try statement("INSERT INTO print_jobs(id,payload,created,status,png,tspl) VALUES(?,?,?,'pending',?,?)"); defer { sqlite3_finalize(s) }
        try bind(id,at:1,to:s); try bind(JSONEncoder().encode(draft),at:2,to:s)
        sqlite3_bind_double(s,3,Date().timeIntervalSince1970)
        try bind(raster.png(),at:4,to:s); try bind(bytes,at:5,to:s); try done(s); return id
    }
    func finishJob(id: String, status: String, detail: String, transferred: Int) throws {
        guard ["sent","error","uncertain"].contains(status) else { throw FoodError.invalid("Неверный статус печати.") }
        let s=try statement("UPDATE print_jobs SET status=?,detail=?,transferred=? WHERE id=?"); defer { sqlite3_finalize(s) }
        try bind(status,at:1,to:s); try bind(detail,at:2,to:s); sqlite3_bind_int64(s,3,Int64(transferred)); try bind(id,at:4,to:s); try done(s)
    }
    func recoverInterruptedJobs() throws {
        try exec("UPDATE print_jobs SET status='uncertain',detail='Приложение закрылось до получения результата. Проверьте принтер перед повторной печатью.' WHERE status='pending'")
    }
    func jobs() throws -> [PrintRecord] {
        let s=try statement("SELECT id,payload,created,status,detail,transferred,png FROM print_jobs ORDER BY created DESC"); defer { sqlite3_finalize(s) }
        var result:[PrintRecord]=[]
        while true { let r=sqlite3_step(s); if r == SQLITE_DONE { break }; guard r == SQLITE_ROW else { throw failure("Чтение истории") }
            result.append(PrintRecord(id:string(s,0),draft:try JSONDecoder().decode(FoodDraft.self,from:data(s,1)),created:Date(timeIntervalSince1970:sqlite3_column_double(s,2)),status:string(s,3),detail:string(s,4),transferred:Int(sqlite3_column_int64(s,5)),png:data(s,6)))
        }; return result
    }
    func backup(to destination: URL) throws {
        guard destination.standardizedFileURL != url.standardizedFileURL else { throw FoodError.invalid("Для копии выберите другой файл.") }
        var out: OpaquePointer?
        guard sqlite3_open(destination.path,&out) == SQLITE_OK else { sqlite3_close(out); throw FoodError.invalid("Не удалось открыть файл резервной копии.") }
        defer { sqlite3_close(out) }
        guard let handle=sqlite3_backup_init(out,"main",db,"main") else { throw FoodError.invalid("Не удалось начать резервное копирование.") }
        let step=sqlite3_backup_step(handle,-1); let finish=sqlite3_backup_finish(handle)
        guard step == SQLITE_DONE && finish == SQLITE_OK else { throw FoodError.invalid("Не удалось завершить резервное копирование.") }
    }
}
