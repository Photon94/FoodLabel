import Foundation
import AppKit
actor ControlledImporter: RecipeImporting {
    var requests:[RecipeReference]=[]
    var completions:[CheckedContinuation<ImportedRecipe,Error>]=[]
    func fetch(_ reference: RecipeReference) async throws -> ImportedRecipe {
        requests.append(reference)
        return try await withCheckedThrowingContinuation { completions.append($0) }
    }
    func count() -> Int { requests.count }
    func succeed(_ index:Int,name:String) { completions[index].resume(returning:ImportedRecipe(name:name,per100:Nutrients(kcal:100,protein:10,fat:3,carbs:8))) }
    func fail(_ index:Int) { completions[index].resume(throwing:URLError(.notConnectedToInternet)) }
}
@main struct RecipeModelTests {
    @MainActor static func expect(_ condition: @autoclosure () -> Bool,_ message:String) throws {
        if !condition() { throw FoodError.invalid(message) }
    }
    @MainActor static func waitFor(_ condition: () async -> Bool) async throws {
        for _ in 0..<200 { if await condition() { return }; try await Task.sleep(nanoseconds:10_000_000) }
        throw FoodError.invalid("Timed out")
    }
    @MainActor static func main() async throws {
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent("FoodLabel-recipe-tests-"+UUID().uuidString)
        setenv("FOODLABEL_DATA_DIR",directory.path,1)
        defer { try? FileManager.default.removeItem(at:directory) }
        let fake=ControlledImporter(), model=AppModel(recipeImporter:fake,checkPrinterOnLaunch:false)
        let link="https://hv.life/app-intent/shareUserRecipe?userId=86Rf07&id=00000000-0000-4000-8000-000000000001"
        let message="Делюсь рецептом «Торт» из приложения: "+link
        model.draft = .example
        model.setRecipeLink("https://hv.life/app-intent/shareUserRecipe?userId=abc&id=bad")
        model.refresh()
        try expect(!model.canPrint && model.validFood == nil,"A malformed recipe URL cannot print with previous nutrition")
        model.saveFood()
        try expect(model.foods.isEmpty,"Malformed recipe URL cannot be saved as a valid dish")
        let restored=AppModel(recipeImporter:fake,checkPrinterOnLaunch:false)
        try expect(!restored.canPrint && restored.validFood == nil,"Invalid recipe stays blocked after draft restore")
        model.draft = .example; model.draft.weight="150"
        model.setRecipeLink(message)
        try expect(model.draft.qrLink == link && model.draft.name == "Торт","Normalize full message immediately")
        try expect(model.draft.kcal.isEmpty && !model.canPrint && model.importingRecipe,"Old nutrition cannot print with new name")
        try await waitFor { await fake.count() == 1 }
        await fake.succeed(0,name:"Source title")
        try await waitFor { !model.importingRecipe }
        model.refresh()
        try expect(model.draft.name == "Source title" && model.draft.weight == "150" && model.validFood?.perPortion.kcal == 150,"Import per100, preserve portion and convert")
        let successfulDraft=model.draft
        model.setRecipeLink(model.draft.qrLink!)
        try expect(model.draft == successfulDraft && !model.importingRecipe,"Reapplying unchanged field text must not clear imported nutrition")
        try expect(try! model.database!.loadDraft()?.qrLink == link,"Persist clean URL")
        model.setRecipeLink(message)
        try await waitFor { await fake.count() == 2 }
        model.draft.name="Manual title"; model.draft.kcal="321"
        await fake.succeed(1,name:"Stale result")
        try await Task.sleep(nanoseconds:30_000_000)
        try expect(model.draft.name == "Manual title" && model.draft.kcal == "321","Manual edits survive late response")
        model.setRecipeLink(message)
        try await waitFor { await fake.count() == 3 }
        model.setRecipeLink("")
        await fake.succeed(2,name:"Removed link")
        try await Task.sleep(nanoseconds:30_000_000)
        try expect(model.draft.qrLink == nil && !model.importingRecipe && model.draft.name != "Removed link","Clearing link cancels stale import")
        model.setRecipeLink(message)
        try await waitFor { await fake.count() == 4 }
        await fake.fail(3)
        try await waitFor { !model.importingRecipe }
        try expect(model.draft.kcal.isEmpty && !model.canPrint && model.canRetryRecipe,"Failure keeps old nutrition cleared and offers retry")
        model.retryRecipeImport()
        try await waitFor { await fake.count() == 5 }
        model.newFood(); let newDraft=model.draft
        await fake.succeed(4,name:"Previous dish")
        try await Task.sleep(nanoseconds:30_000_000)
        try expect(model.draft == newDraft,"New dish survives previous import")
        model.draft = .example; model.setRecipeLink("mealapp://dish/123")
        try expect(model.draft.kcal == "123" && !model.importingRecipe,"Other QR links preserve nutrition")
        print("PASS: import success, conversion, persistence, cancellation, manual edits, failure, retry, new dish, ordinary QR")
    }
}
