import Foundation
@main struct RecipeImportTests {
    static func expect(_ condition: @autoclosure () throws -> Bool,_ message: String) throws {
        if try !condition() { throw FoodError.invalid(message) }
    }
    static func main() throws {
        let url="https://hv.life/app-intent/shareUserRecipe?userId=sampleUser&id=00000000-0000-4000-8000-000000000001"
        let shared="Делюсь рецептом «Торт морковный» из приложения «Худеем вместе - Счётчик калорий»: "+url
        let nested="mealapp://open?target="+url
        try expect(try SharedRecipeLink.parse(nested).link == nested,"Preserve a bare app URL containing a nested HTTPS destination")
        try expect(try SharedRecipeLink.parse(nested).reference == nil,"Nested recipe URLs never trigger import")
        let parsed=try SharedRecipeLink.parse(shared)
        try expect(parsed.link == url,"Extract the exact sharing URL")
        try expect(parsed.title == "Торт морковный","Extract recipe title, not app name")
        try expect(parsed.reference?.userID == "sampleUser","Recognize exact provider")
        try expect(try SharedRecipeLink.parse(shared.replacingOccurrences(of:"https:",with:"https\\:")).link == url,"Escaped colon")
        try expect(try SharedRecipeLink.parse(url).title == nil,"Bare URL has no invented title")
        try expect(try SharedRecipeLink.parse("See ("+url+").").link == url,"Sharing punctuation")
        try expect(try SharedRecipeLink.parse("mealapp://dish/250001").reference == nil,"Other deep links stay local")
        try expect(try SharedRecipeLink.parse(url.replacingOccurrences(of:"hv.life",with:"hv.life.example.com")).reference == nil,"Exact provider host match")
        for invalid in [shared+" https://example.com/other",url+"&userId=other",url.replacingOccurrences(of:"00000000-0000-4000-8000-000000000001",with:"../private"),"some words without a link"] {
            var rejected=false; do { _=try SharedRecipeLink.parse(invalid) } catch { rejected=true }
            try expect(rejected,"Reject ambiguous or invalid input")
        }
        try expect(try RecipeReference(userID:"86Rf07",recipeID:"x").profileID() == 123,"Sqids multi-integer decoding")
        let fixture = #"{"title":"Тестовый торт","weight":400,"products":[{"dose":150,"portionIndex":1,"portions":[{"portion":{"amount":1},"nutrient":{"calories":999,"proteins":999,"fats":999,"carbohydrates":999}},{"portion":{"amount":100},"nutrient":{"calories":200,"proteins":10,"fats":8,"carbohydrates":22}}]},{"dose":2,"portionIndex":0,"portions":[{"portion":{"amount":0},"nutrient":{"calories":50,"proteins":5,"fats":1,"carbohydrates":6}}]}]}"#
        let recipe=try ImportedRecipe.decode(Data(fixture.utf8))
        try expect(recipe.name == "Тестовый торт","Decode title")
        try expect(recipe.per100 == Nutrients(kcal:100,protein:Decimal(string:"6.25")!,fat:Decimal(string:"3.5")!,carbs:Decimal(string:"11.25")!),"Selected portion, unit quantities and cooked weight")
        for bad in [fixture.replacingOccurrences(of:"\"weight\":400",with:"\"weight\":0"),fixture.replacingOccurrences(of:"\"proteins\":5",with:"\"proteins\":null"),fixture.replacingOccurrences(of:"\"dose\":150",with:"\"dose\":-1"),fixture.replacingOccurrences(of:"\"portionIndex\":1",with:"\"portionIndex\":9"),fixture.replacingOccurrences(of:"\"calories\":200",with:"\"calories\":true")] {
            var rejected=false; do { _=try ImportedRecipe.decode(Data(bad.utf8)) } catch { rejected=true }
            try expect(rejected,"Reject incomplete or malformed recipe")
        }
        try expect(ImportedRecipe.editable(Decimal(string:"104.4715719063545")!) == "104,471572","Imported input has six useful decimal places")
        try expect(ImportedRecipe.editable(100) == "100","Imported input has no trailing zeros")
        print("PASS: sharing text, escaped URL, recipe title, precise provider validation")
    }
}
