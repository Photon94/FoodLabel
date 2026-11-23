import Foundation

enum FoodError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case .invalid(let s) = self { return s }; return nil }
}
enum PrinterProfile: String, Codable, CaseIterable, Sendable {
    case xprinter, niimbot
    var title: String { self == .xprinter ? "Xprinter XP-365B" : "NIIMBOT B21 Pro" }
    var paper: String { self == .xprinter ? "58 × 30 мм" : "50 × 30 мм" }
    var aspectRatio: Double { self == .xprinter ? 58.0/30 : 50.0/30 }
}
enum NutritionBasis: String, Codable, CaseIterable { case per100, portion
    var title: String { self == .per100 ? "На 100 г" : "На порцию" }
}
struct Nutrients: Codable, Equatable {
    var kcal: Decimal; var protein: Decimal; var fat: Decimal; var carbs: Decimal
    var values: [Decimal] { [kcal, protein, fat, carbs] }
    func scaled(_ factor: Decimal) -> Nutrients {
        Nutrients(kcal: kcal*factor, protein: protein*factor, fat: fat*factor, carbs: carbs*factor)
    }
}
enum Numbers {
    static func parse(_ raw: String, name: String, max: Decimal = 100000) throws -> Decimal {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        guard text.count <= 46, text.range(of: "^[0-9]+(?:\\.[0-9]{1,38})?$", options: .regularExpression) != nil,
              let value = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")),
              !value.isNaN, value >= 0, value <= max else {
            throw FoodError.invalid("\(name): введите число от 0 до \(max). Можно использовать точку или запятую.")
        }
        return value
    }
    static func raw(_ value: Decimal) -> String { NSDecimalNumber(decimal: value).stringValue.replacingOccurrences(of: ".", with: ",") }
    static func display(_ value: Decimal) -> String {
        var source = value, rounded = Decimal(); NSDecimalRound(&rounded, &source, 1, .plain)
        return raw(rounded)
    }
}
struct ValidFood {
    let name: String; let grams: Decimal; let per100: Nutrients; let perPortion: Nutrients
    let date: Date; let timeZone: TimeZone; let barcode: String; let copies: Int; let qrLink: String?
}
struct FoodDraft: Codable, Equatable {
    var name = ""
    var weight = "250"
    var kcal = ""; var protein = ""; var fat = ""; var carbs = ""
    var basis: NutritionBasis = .per100
    var date = Date()
    var dateTimeZoneIdentifier: String? = TimeZone.current.identifier
    var labelTimeZone: TimeZone { dateTimeZoneIdentifier.flatMap(TimeZone.init(identifier:)) ?? .current }
    var barcode = "250001"
    var copies = "1"
    var qrLink: String?
    var printerProfile: PrinterProfile?
    var selectedPrinter: PrinterProfile { printerProfile ?? .xprinter }
    static var example: FoodDraft {
        var d = FoodDraft(); d.name = "Шаурма ленивая"; d.kcal = "123"; d.protein = "12,3"; d.fat = "3,4"; d.carbs = "11"; return d
    }
    func inputNutrition() throws -> (Decimal, Nutrients) {
        let grams = try portionWeight()
        let n = try Nutrients(kcal: Numbers.parse(kcal, name: "Калории"), protein: Numbers.parse(protein, name: "Белки"), fat: Numbers.parse(fat, name: "Жиры"), carbs: Numbers.parse(carbs, name: "Углеводы"))
        return (grams, n)
    }
    private func portionWeight() throws -> Decimal {
        let grams = try Numbers.parse(weight, name: "Вес порции", max: 10000)
        var original=grams, rounded=Decimal(); NSDecimalRound(&rounded,&original,1,.plain)
        guard grams >= Decimal(string:"0.1")!, grams == rounded else {
            throw FoodError.invalid("Вес порции: от 0,1 до 10 000 г, не больше одной цифры после запятой.")
        }
        return grams
    }
    mutating func useToday() { date=Date(); dateTimeZoneIdentifier=TimeZone.current.identifier }
    func validated() throws -> ValidFood {
        let name = self.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 70, !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw FoodError.invalid("Укажите название блюда: от 1 до 70 символов, без переносов строки.")
        }
        let (grams, source) = try inputNutrition()
        let per100 = basis == .per100 ? source : source.scaled(100/grams)
        let perPortion = basis == .portion ? source : source.scaled(grams/100)
        guard per100.values.allSatisfy({ !$0.isNaN && $0 <= 100000 }), perPortion.values.allSatisfy({ !$0.isNaN && $0 <= 100000 }) else {
            throw FoodError.invalid("Результат слишком большой. Проверьте вес и КБЖУ.")
        }
        guard barcode.range(of: "^[0-9]{6}$", options: .regularExpression) != nil else {
            throw FoodError.invalid("Внутренний штрихкод должен содержать ровно 6 цифр.")
        }
        guard let count = Int(copies), (1...100).contains(count), copies.allSatisfy({ $0.isASCII && $0.isNumber }) else {
            throw FoodError.invalid("Количество этикеток: целое число от 1 до 100.")
        }
        let link=try validatedQRLink()
        return ValidFood(name: name, grams: grams, per100: per100, perPortion: perPortion, date: date, timeZone: labelTimeZone, barcode: barcode, copies: count, qrLink: link)
    }
    private func validatedQRLink() throws -> String? {
        let text=(qrLink ?? "").trimmingCharacters(in:.whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        guard text.utf8.count <= 1024,
              !text.unicodeScalars.contains(where:{CharacterSet.whitespacesAndNewlines.union(.controlCharacters).contains($0)}),
              let parts=URLComponents(string:text), let scheme=parts.scheme?.lowercased(),
              !["javascript","data","file","vbscript"].contains(scheme),
              parts.url != nil,
              !(parts.host ?? "").isEmpty || !parts.path.isEmpty || !(parts.query ?? "").isEmpty || !(parts.fragment ?? "").isEmpty else {
            throw FoodError.invalid("Вставьте полную ссылку на блюдо, например https://… или ссылку из приложения. Пробелы внутри ссылки недопустимы.")
        }
        if ["http","https"].contains(scheme) && (parts.host ?? "").isEmpty {
            throw FoodError.invalid("В веб-ссылке на блюдо должен быть адрес сайта после https://.")
        }
        return text
    }
    mutating func switchBasis(to newBasis: NutritionBasis) throws {
        guard newBasis != basis else { return }
        let inputs=[kcal,protein,fat,carbs]
        if inputs.allSatisfy({$0.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty}) { basis=newBasis; return }
        let grams=try portionWeight(), factor:Decimal=newBasis == .portion ? grams/100 : 100/grams
        // Convert only populated fields, atomically, preserving blanks and Decimal precision.
        let converted=try inputs.map { raw -> String in
            if raw.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty { return "" }
            let value=try Numbers.parse(raw,name:"КБЖУ") * factor
            guard !value.isNaN, value <= 100000 else { throw FoodError.invalid("Результат слишком большой. Проверьте вес и КБЖУ.") }
            return Numbers.raw(value)
        }
        kcal=converted[0]; protein=converted[1]; fat=converted[2]; carbs=converted[3]; basis=newBasis
    }
}
struct SavedFood: Identifiable { let id: String; let draft: FoodDraft; let updated: Date }
struct PrintRecord: Identifiable {
    let id: String; let draft: FoodDraft; let created: Date; let status: String
    let detail: String; let transferred: Int; let png: Data
    var statusTitle: String {
        switch status { case "sent": return "Отправлено"; case "error": return "Ошибка"; case "pending": return "Отправляется"; default: return "Результат неизвестен" }
    }
}
