import Foundation
import AppKit
import Vision

struct QRTestError: Error { let message: String }
func require(_ value: @autoclosure () throws -> Bool,_ message:String) throws {
    if try !value() { throw QRTestError(message:message) }
}
func draftWithLink(_ link:String?) throws -> FoodDraft {
    var json=try JSONSerialization.jsonObject(with:JSONEncoder().encode(FoodDraft.example)) as! [String:Any]
    json["qrLink"]=link
    return try JSONDecoder().decode(FoodDraft.self,from:JSONSerialization.data(withJSONObject:json))
}
func scan(_ raster:LabelRaster) throws -> [VNBarcodeObservation] {
    let request=VNDetectBarcodesRequest(); request.symbologies=[.qr,.code128]
    try VNImageRequestHandler(cgImage:raster.cgImage,options:[:]).perform([request])
    return request.results ?? []
}
@main struct QRTests {
    static func main() throws {
        let link="https://example.com/food/250001?portion=250#nutrition"
        let food=try draftWithLink(link)
        let raster=try LabelRenderer.render(food.validated())
        let codes=try scan(raster)
        try require(codes.contains {$0.symbology == .qr && $0.payloadStringValue == link},"QR on the complete label decodes to the exact dish link")
        try require(codes.contains {$0.symbology == .code128 && $0.payloadStringValue == "250001"},"Code 128 remains scannable beside QR")
        try raster.png().write(to:URL(fileURLWithPath:"build/test-qr-label.png"))
        print("PASS: QR and barcode decode from complete label")
        for url in ["mealapp://dish/250001?portion=250", "mealapp:dish/250001", "mealapp://?dish=250001", "mealapp:?dish=250001", "mealapp:#dish=250001", "https://example.com/блюдо/шаурма", "https://example.com/d?a=a%2Fb&size=250#nutrition", "https://example.com/d/"+String(repeating:"a",count:95)] {
            let label=try LabelRenderer.render(draftWithLink(url).validated())
            try require(try scan(label).contains {$0.symbology == .qr && $0.payloadStringValue == url},"Exact QR payload: \(url)")
        }
        let plain=try LabelRenderer.render(draftWithLink(nil).validated())
        for empty in ["", "  \n  "] {
            try require(try LabelRenderer.render(draftWithLink(empty).validated()).pixels == plain.pixels,"Empty link preserves original layout")
        }
        for invalid in ["not a link", "example.com/dish/1", "https:///dish", "https://", "https://example.com/a b", "mealapp://dish/1\nPRINT 1,50", "javascript:alert(1)", "data:text/plain,hi", "file:///tmp/food"] {
            var rejected=false
            do { _ = try draftWithLink(invalid).validated() } catch { rejected=true }
            try require(rejected,"Invalid link rejected: \(invalid)")
        }
        let overlong="https://example.com/d/"+String(repeating:"a",count:300)
        var rejectedDense=false
        do { _ = try LabelRenderer.render(draftWithLink(overlong).validated()) } catch { rejectedDense=true }
        try require(rejectedDense,"Dense QR rejected instead of shrinking or truncating")
        let trimmed=try LabelRenderer.render(draftWithLink("  \n"+link+" \n").validated())
        try require(trimmed.pixels == raster.pixels,"Trim only surrounding whitespace")
        // Reconstruct actual printer BAR commands, independently of the renderer.
        let bytes=try raster.tspl(copies:3)
        var printed=[UInt8](repeating:255,count:464*240)
        for line in String(decoding:bytes,as:UTF8.self).components(separatedBy:"\r\n") where line.hasPrefix("BAR ") {
            let v=line.dropFirst(4).split(separator:",").compactMap {Int($0)}
            try require(v.count == 4 && v[0]>=0 && v[1]>=0 && v[0]+v[2]<=464 && v[1]+v[3]<=240,"Printer bounds")
            for y in v[1]..<(v[1]+v[3]) { for x in v[0]..<(v[0]+v[2]) { printed[y*464+x]=0 } }
        }
        try require(printed == raster.pixels,"Printed raster exactly matches QR preview")
        let dir=FileManager.default.temporaryDirectory.appendingPathComponent("FoodLabel-QR-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at:dir) }
        let dbURL=dir.appendingPathComponent("labels.sqlite")
        var recordID=""
        do {
            let db=try LabelDatabase(url:dbURL)
            let id=try db.saveFood(id:nil,draft:food)
            try db.saveDraft(food)
            recordID=try db.beginJob(draft:food,raster:raster,bytes:bytes)
            _ = try db.saveFood(id:id,draft:draftWithLink("mealapp://dish/other"))
            // Old records had no qrLink field. They must still load and render.
            let legacy=try draftWithLink(nil)
            _ = try db.saveFood(id:nil,draft:legacy)
            try require(try LabelRenderer.render(legacy.validated()).pixels == plain.pixels,"Legacy record layout")
        }
        do {
            let db=try LabelDatabase(url:dbURL)
            try require(try db.loadDraft()?.qrLink == link,"QR draft survives relaunch")
            try require(try db.foods().contains {$0.draft.qrLink == "mealapp://dish/other"},"Recipe link persists")
            let stored=try db.jobs().first {$0.id == recordID}
            try require(stored?.draft.qrLink == link,"History link immutable after recipe edit")
            try require(try stored?.png == raster.png(),"History stores exact QR image")
        }
        print("PASS: app/web/Unicode links, legacy data, validation, density limit, exact print raster and QR persistence")
    }
}
