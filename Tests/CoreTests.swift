import Foundation
import AppKit
import Vision
struct TestFailure: Error { let message: String }
func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
    if try !condition() { throw TestFailure(message: message) }
}
func rejects(_ action: () throws -> Void, _ message: String) throws {
    do { try action() } catch { return }; throw TestFailure(message: message)
}
@main struct CoreTests {
    static func main() throws {
        var food = FoodDraft.example
        let result = try food.validated()
        try expect(result.perPortion.kcal == Decimal(string: "307.5")!, "250g energy")
        try expect(result.perPortion.protein == Decimal(string: "30.75")!, "unrounded protein")
        try expect(result.perPortion.fat == Decimal(string: "8.5")!, "250g fat")
        try expect(result.perPortion.carbs == Decimal(string: "27.5")!, "250g carbs")
        try expect(Numbers.display(result.perPortion.protein) == "30,8", "decimal rounding")
        let original = try food.validated().per100
        try food.switchBasis(to: .portion)
        try expect(try food.validated().per100 == original, "switch preserves nutrition")
        try food.switchBasis(to: .per100)
        try expect(try food.validated().per100 == original, "round trip basis")
        var thirds = FoodDraft.example; thirds.weight = "3"; thirds.basis = .portion; thirds.kcal = "1"
        for _ in 0..<10 {
            try thirds.switchBasis(to: .per100)
            _ = try thirds.validated()
            try thirds.switchBasis(to: .portion)
            let difference = try thirds.validated().perPortion.kcal - 1
            try expect(abs(difference) < Decimal(string: "0.00000000000000000001")!, "repeating decimal remains usable")
        }
        food.weight = "125,5"
        try expect(try food.validated().perPortion.kcal == Decimal(string: "154.365")!, "decimal comma weight")
        for invalid in ["", "-1", "NaN", "inf", "1e999", "1.2.3", "12,3.4", "99999999999999"] {
            food = .example; food.protein = invalid
            try rejects({ _ = try food.validated() }, "invalid nutrient: \(invalid)")
        }
        for invalid in ["0", "-1", "NaN"] {
            food = .example; food.weight = invalid
            try rejects({ _ = try food.validated() }, "invalid mass")
        }
        food = .example; food.name = "\n  "
        try rejects({ _ = try food.validated() }, "empty name")
        food = .example; food.barcode = "12\nCLS"
        try rejects({ _ = try food.validated() }, "barcode injection")
        food = .example; food.copies = "0"
        try rejects({ _ = try food.validated() }, "zero copies")
        food.copies = "101"
        try rejects({ _ = try food.validated() }, "excess copies")
        food = .example; food.copies = "15"
        let raster = try LabelRenderer.render(food.validated())
        try expect(raster.width == 464 && raster.height == 240, "dimensions")
        try expect(raster.pixels.count == 111360, "pixel count")
        let job = try raster.tspl(copies: 15)
        let command = String(decoding: job, as: UTF8.self)
        try expect(command.hasSuffix("PRINT 1,15\r\n"), "copies")
        try expect(command.components(separatedBy: "PRINT ").count == 2, "one print command")
        let scan = VNDetectBarcodesRequest(); scan.symbologies = [.code128]
        try VNImageRequestHandler(cgImage: raster.cgImage, options: [:]).perform([scan])
        try expect(scan.results?.first?.payloadStringValue == "250001", "barcode decodes")
        try raster.png().write(to: URL(fileURLWithPath: "build/test-label.png"))
        food.name = String(repeating: "Длинное название блюда ", count: 8)
        try rejects({ _ = try food.validated() }, "overlong name")
        food = .example; food.name = "Запечённая курица с рисом и овощами"
        _ = try LabelRenderer.render(food.validated())
        print("PASS: nutrition, basis switching, validation, raster, barcode and copy count")
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("FoodLabel-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("test.sqlite")
        var savedID = "", jobID = ""
        do {
            let db = try LabelDatabase(url: url)
            savedID = try db.saveFood(id: nil, draft: .example)
            let a = try db.nextBarcode(), b = try db.nextBarcode()
            try expect(a != b && a.count == 6, "unique barcodes")
            jobID = try db.beginJob(draft: .example, raster: raster, bytes: job)
            var changed = FoodDraft.example; changed.name = "Другое блюдо"
            _ = try db.saveFood(id: savedID, draft: changed)
            let history = try db.jobs()
            try expect(history.first?.draft.name == "Шаурма ленивая", "immutable snapshot")
            try expect(history.first?.status == "pending", "log before send")
        }
        do {
            let db = try LabelDatabase(url: url); try db.recoverInterruptedJobs()
            try expect(try db.foods().first?.draft.name == "Другое блюдо", "recipe reopen")
            try expect(try db.jobs().first?.status == "uncertain", "interrupted recovery")
            try db.finishJob(id: jobID, status: "sent", detail: "test", transferred: job.count)
            try expect(try db.jobs().first?.transferred == job.count, "result persisted")
            let backup = dir.appendingPathComponent("backup.sqlite"); try db.backup(to: backup)
            let restored = try LabelDatabase(url: backup)
            try expect(try restored.jobs().first?.draft.name == "Шаурма ленивая", "backup")
        }
        print("PASS: SQLite persistence, immutable history, recovery and backup")
    }
}
