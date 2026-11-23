import Foundation
import Vision
@main struct PrinterTests {
    static func require(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        if try !condition() { throw FoodError.invalid(message) }
    }
    static func main() throws {
        var draft=FoodDraft.example
        // Legacy records and the current default retain the original printer.
        let legacy=try JSONDecoder().decode(FoodDraft.self,from:JSONEncoder().encode(draft))
        try require(legacy.selectedPrinter == .xprinter,"Legacy printer default")
        draft.printerProfile = .niimbot
        let raster=try LabelRenderer.render(draft.validated(),profile:draft.selectedPrinter)
        try require(raster.width == 592 && raster.height == 354,"NIIMBOT native raster size")
        try require(raster.pixels.prefix(592*24).allSatisfy {$0 == 255},"NIIMBOT top margin at least 2 mm")
        for link in [nil,"https://example.com/dish/250001","mealapp://dish/250001"] as [String?] {
            draft.qrLink=link
            let rendered=try LabelRenderer.render(draft.validated(),profile:.niimbot)
            let request=VNDetectBarcodesRequest()
            try VNImageRequestHandler(cgImage:rendered.cgImage).perform([request])
            let results=request.results ?? []
            try require(results.contains {$0.symbology == .code128 && $0.payloadStringValue == "250001"},"NIIMBOT barcode decodes")
            if let link { try require(results.contains {$0.symbology == .qr && $0.payloadStringValue == link},"NIIMBOT QR decodes exactly") }
        }
        let roundtrip=try JSONDecoder().decode(FoodDraft.self,from:JSONEncoder().encode(draft))
        try require(roundtrip.selectedPrinter == .niimbot,"Printer profile persists")
        print("PASS: NIIMBOT raster, barcode/QR decoding, legacy and profile persistence")
    }
}
