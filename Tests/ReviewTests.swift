import Foundation
import AppKit
@main struct ReviewTests {
    @MainActor static func main() throws {
        var failures=0
        func check(_ name:String,_ body:() throws -> Bool) {
            do { if try body() { print("PASS: \(name)"); return } }
            catch { print("DETAIL: \(error)") }
            print("FAIL: \(name)"); failures += 1
        }
        check("blank and partial drafts allow basis selection") {
            var blank=FoodDraft(); try blank.switchBasis(to:.portion)
            guard blank.basis == .portion && blank.kcal.isEmpty else { return false }
            blank.kcal="307,5"; try blank.switchBasis(to:.per100)
            return blank.kcal == "123" && blank.protein.isEmpty
        }
        check("out-of-range conversion leaves draft unchanged") {
            var draft=FoodDraft.example; draft.weight="10000"; draft.kcal="100000"
            let before=draft
            do { try draft.switchBasis(to:.portion); return false } catch { return draft == before }
        }
        check("weight cannot silently round away precision") {
            var draft=FoodDraft.example; draft.weight="0.14"
            do { _ = try draft.validated(); return false } catch { return true }
        }
        check("history label date survives time zone change") {
            let previous=NSTimeZone.default; defer { NSTimeZone.default=previous }
            NSTimeZone.default=TimeZone(identifier:"Europe/Moscow")!
            var draft=FoodDraft.example
            draft.date=ISO8601DateFormatter().date(from:"2026-11-19T22:00:00Z")!
            let before=try LabelRenderer.render(draft.validated()).pixels
            let data=try JSONEncoder().encode(draft)
            NSTimeZone.default=TimeZone(identifier:"America/Los_Angeles")!
            let restored=try JSONDecoder().decode(FoodDraft.self,from:data)
            return try before == LabelRenderer.render(restored.validated()).pixels
        }
        let dir=FileManager.default.temporaryDirectory.appendingPathComponent("FoodLabel-model-test-\(UUID().uuidString)")
        setenv("FOODLABEL_DATA_DIR",dir.path,1)
        defer { try? FileManager.default.removeItem(at:dir) }
        check("edit disables printing until new preview is ready") {
            let model=AppModel()
            guard model.canPrint else { return false }
            model.draft.name="Новая этикетка"
            guard !model.canPrint else { return false }
            model.refresh()
            return model.canPrint && model.validFood?.name == "Новая этикетка"
        }
        if failures > 0 { exit(1) }
    }
}
