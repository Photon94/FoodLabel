import Foundation

struct RecipeReference: Equatable, Sendable {
    let userID: String
    let recipeID: String
}
struct SharedRecipeLink {
    let link: String
    let title: String?
    let reference: RecipeReference?

    static func parse(_ input: String) throws -> SharedRecipeLink {
        guard input.utf8.count <= 8192 else { throw FoodError.invalid("Текст ссылки слишком длинный.") }
        let text=input.trimmingCharacters(in:.whitespacesAndNewlines)
            .replacingOccurrences(of:#"\b(https?)\\://"#,with:"$1://",options:.regularExpression)
        guard !text.isEmpty else { return SharedRecipeLink(link:"",title:nil,reference:nil) }
        var link: String
        // Preserve complete app URLs before looking for URLs embedded in sharing prose.
        if !text.contains(where:{$0.isWhitespace}), URLComponents(string:text)?.scheme != nil {
            link=text
        } else {
            let regex=try NSRegularExpression(pattern:#"https?://[^\s<>«»“”\"]+"#,options:.caseInsensitive)
            let matches=regex.matches(in:text,range:NSRange(text.startIndex...,in:text))
            guard matches.count <= 1 else { throw FoodError.invalid("Вставьте только одну ссылку на блюдо.") }
            guard let match=matches.first, let range=Range(match.range,in:text) else {
                throw FoodError.invalid("В тексте не найдена ссылка. Вставьте ссылку или сообщение «Делюсь рецептом…».")
            }
            link=String(text[range])
            while let last=link.last, ".,;!?»\"”".contains(last) { link.removeLast() }
            while link.last == ")", link.filter({$0 == ")"}).count > link.filter({$0 == "("}).count { link.removeLast() }
        }
        guard let components=URLComponents(string:link), components.url != nil else { throw FoodError.invalid("Не удалось прочитать ссылку.") }
        var reference: RecipeReference?
        if components.host?.lowercased() == "hv.life", components.path == "/app-intent/shareUserRecipe" {
            guard components.scheme?.lowercased() == "https", components.user == nil, components.password == nil,
                  components.port == nil || components.port == 443 else { throw FoodError.invalid("Для загрузки рецепта нужна ссылка https://hv.life/…") }
            func parameter(_ name: String) throws -> String {
                let items=(components.queryItems ?? []).filter {$0.name == name}
                guard items.count == 1, let value=items[0].value, !value.isEmpty else { throw FoodError.invalid("В ссылке нет однозначного идентификатора рецепта.") }
                return value
            }
            let userID=try parameter("userId"), recipeID=try parameter("id")
            guard userID.range(of:"^[A-Za-z0-9_-]{1,128}$",options:.regularExpression) != nil,
                  UUID(uuidString:recipeID) != nil else { throw FoodError.invalid("Повреждены идентификаторы в ссылке на рецепт.") }
            reference=RecipeReference(userID:userID,recipeID:recipeID)
        }
        var title: String?
        if reference != nil {
            let titlePattern=try NSRegularExpression(pattern:#"Делюсь\s+рецептом\s+«([^»\r\n]{1,70})»"#,options:.caseInsensitive)
            if let match=titlePattern.firstMatch(in:text,range:NSRange(text.startIndex...,in:text)),let range=Range(match.range(at:1),in:text) {
                let candidate=String(text[range]).trimmingCharacters(in:.whitespacesAndNewlines)
                if !candidate.isEmpty { title=candidate }
            }
        }
        return SharedRecipeLink(link:link,title:title,reference:reference)
    }
}

extension RecipeReference {
    // Default Sqids decoder, adapted from sqids-python (MIT; see THIRD-PARTY.txt).
    // The source app joins the decoded integers before parsing the profile ID.
    func profileID() throws -> Int64 {
        func shuffled(_ input: [UInt8]) -> [UInt8] {
            var chars=input
            for i in 0..<(chars.count-1) {
                let j=chars.count-1-i
                let r=(i*j + Int(chars[i]) + Int(chars[j])) % chars.count
                chars.swapAt(i,r)
            }
            return chars
        }
        let invalid=FoodError.invalid("Не удалось прочитать идентификатор автора рецепта.")
        var alphabet=shuffled(Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789".utf8))
        let bytes=Array(userID.utf8)
        guard bytes.count > 1, bytes.count <= 128, bytes.allSatisfy({alphabet.contains($0)}),
              let offset=alphabet.firstIndex(of:bytes[0]) else { throw invalid }
        alphabet=Array((Array(alphabet[offset...])+Array(alphabet[..<offset])).reversed())
        var remaining=Array(bytes.dropFirst()), numbers=[String]()
        while !remaining.isEmpty {
            let separator=alphabet[0]
            let end=remaining.firstIndex(of:separator) ?? remaining.count
            if end == 0 { break }
            var number:Int64=0
            for byte in remaining[..<end] {
                guard let digit=alphabet.dropFirst().firstIndex(of:byte) else { throw invalid }
                let (product,overflow1)=number.multipliedReportingOverflow(by:Int64(alphabet.count-1))
                let (next,overflow2)=product.addingReportingOverflow(Int64(digit-1))
                guard !overflow1 && !overflow2 else { throw invalid }
                number=next
            }
            numbers.append(String(number))
            remaining=end == remaining.count ? [] : Array(remaining[(end+1)...])
            alphabet=shuffled(alphabet)
        }
        guard let result=Int64(numbers.joined()), result > 0 else { throw invalid }
        return result
    }
}

struct ImportedRecipe: Equatable, Sendable {
    let name: String
    let per100: Nutrients

    static func editable(_ value: Decimal) -> String {
        var input=value, rounded=Decimal()
        NSDecimalRound(&rounded,&input,6,.plain)
        return Numbers.raw(rounded)
    }

    static func decode(_ data: Data) throws -> ImportedRecipe {
        let invalid=FoodError.invalid("Рецепт не содержит полных КБЖУ или его формат изменился. Заполните данные вручную.")
        struct Payload: Decodable {
            struct Product: Decodable {
                struct Portion: Decodable {
                    struct Head: Decodable { let amount: Decimal }
                    struct Nutrition: Decodable { let calories:Decimal; let proteins:Decimal; let fats:Decimal; let carbohydrates:Decimal }
                    let portion: Head; let nutrient: Nutrition
                }
                let dose:Decimal; let portionIndex:Int; let portions:[Portion]
            }
            let title:String; let weight:Decimal; let products:[Product]
        }
        guard data.count <= 1_048_576, let payload=try? JSONDecoder().decode(Payload.self,from:data) else { throw invalid }
        let name=payload.title.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 70, !name.unicodeScalars.contains(where:{CharacterSet.controlCharacters.contains($0)}),
              !payload.weight.isNaN, payload.weight > 0, payload.weight <= 1_000_000,
              !payload.products.isEmpty, payload.products.count <= 1000 else { throw invalid }
        var total=Nutrients(kcal:0,protein:0,fat:0,carbs:0)
        for product in payload.products {
            guard !product.dose.isNaN, product.dose >= 0, product.dose <= 1_000_000,
                  product.portions.indices.contains(product.portionIndex) else { throw invalid }
            let selected=product.portions[product.portionIndex], n=selected.nutrient
            let amount=selected.portion.amount
            guard !amount.isNaN, amount >= 0, amount <= 1_000_000 else { throw invalid }
            let nutrients=Nutrients(kcal:n.calories,protein:n.proteins,fat:n.fats,carbs:n.carbohydrates)
            guard nutrients.values.allSatisfy({!$0.isNaN && $0 >= 0 && $0 <= 1_000_000}) else { throw invalid }
            // Ingredient.toProductRepo -> calcDose: nutrient * dose / selected amount;
            // amount=0 denotes a unit portion. ReceiptModel divides the sum by cooked weight.
            let scaled=nutrients.scaled(amount == 0 ? product.dose : product.dose/amount)
            total=Nutrients(kcal:total.kcal+scaled.kcal,protein:total.protein+scaled.protein,fat:total.fat+scaled.fat,carbs:total.carbs+scaled.carbs)
        }
        let per100=total.scaled(100/payload.weight)
        guard per100.values.allSatisfy({!$0.isNaN && $0 >= 0 && $0 <= 100000}) else { throw invalid }
        return ImportedRecipe(name:name,per100:per100)
    }
}

protocol RecipeImporting: Sendable {
    func fetch(_ reference: RecipeReference) async throws -> ImportedRecipe
}
private final class RecipeRedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        // The verified endpoint does not redirect. Do not forward identifiers elsewhere.
        completionHandler(nil)
    }
}
struct HVRecipeImporter: RecipeImporting {
    static func request(for reference: RecipeReference) throws -> URLRequest {
        var url=URLComponents(string:"https://admin.hv.life/api/recipe/item")!
        url.queryItems=[URLQueryItem(name:"profile_id",value:String(try reference.profileID())),URLQueryItem(name:"recipe_id",value:reference.recipeID)]
        var request=URLRequest(url:url.url!); request.timeoutInterval=15
        request.setValue("application/json",forHTTPHeaderField:"Accept")
        return request
    }
    func fetch(_ reference: RecipeReference) async throws -> ImportedRecipe {
        let config=URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest=15; config.timeoutIntervalForResource=20
        config.httpCookieStorage=nil; config.urlCache=nil
        let session=URLSession(configuration:config,delegate:RecipeRedirectPolicy(),delegateQueue:nil)
        defer { session.invalidateAndCancel() }
        let (bytes,response)=try await session.bytes(for:Self.request(for:reference))
        guard let http=response as? HTTPURLResponse, http.statusCode == 200 else {
            throw FoodError.invalid("Рецепт недоступен. Проверьте ссылку или попробуйте позже.")
        }
        guard response.expectedContentLength <= 1_048_576 else { throw FoodError.invalid("Рецепт слишком большой для загрузки.") }
        var data=Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < 1_048_576 else { throw FoodError.invalid("Рецепт слишком большой для загрузки.") }
            data.append(byte)
        }
        return try ImportedRecipe.decode(data)
    }
}
