import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

struct LabelRaster {
    let width: Int; let height: Int; let pixels: [UInt8]
    var cgImage: CGImage {
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
                       space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0), provider: provider,
                       decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }
    var image: NSImage { NSImage(cgImage: cgImage, size: NSSize(width: width, height: height)) }
    func png() throws -> Data {
        guard let data = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]) else { throw FoodError.invalid("Не удалось создать PNG.") }; return data
    }
    func tspl(copies: Int) throws -> Data {
        guard (1...100).contains(copies) else { throw FoodError.invalid("Недопустимое количество этикеток.") }
        var s = "\r\nSIZE 58 mm,30 mm\r\nDENSITY 8\r\nDIRECTION 1\r\nREFERENCE 0,0\r\nSHIFT 0,0\r\nOFFSET 0 mm\r\nCLS\r\n"
        for y in 0..<height {
            var x = 0
            while x < width {
                if pixels[y*width+x] == 0 {
                    let start = x
                    while x < width && pixels[y*width+x] == 0 { x += 1 }
                    s += "BAR \(start),\(y),\(x-start),1\r\n"
                } else { x += 1 }
            }
        }
        s += "PRINT 1,\(copies)\r\n"
        return Data(s.utf8)
    }
}
enum LabelRenderer {
    static let width = 464, height = 240
    static func render(_ food: ValidFood) throws -> LabelRaster {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                bitsPerSample: 8, samplesPerPixel: 1, hasAlpha: false, isPlanar: false,
                colorSpaceName: .deviceWhite, bytesPerRow: width, bitsPerPixel: 8),
              let graphics = NSGraphicsContext(bitmapImageRep: rep) else { throw FoodError.invalid("Не удалось подготовить этикетку.") }
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = graphics
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSColor.white.setFill(); NSRect(x: 0,y: 0,width: width,height: height).fill()
        func rect(_ x: Int,_ y: Int,_ w: Int,_ h: Int) { NSColor.black.setFill(); NSRect(x: x,y: height-y-h,width: w,height: h).fill() }
        func text(_ s: String, x: CGFloat, top: CGFloat, size: CGFloat, maxWidth: CGFloat, bold: Bool = false, align: Int = 0, minSize: CGFloat = 13) throws {
            var pointSize = size
            func font(_ size: CGFloat) -> NSFont { NSFont(name: bold ? "Arial-BoldMT" : "ArialMT", size: size) ?? NSFont.systemFont(ofSize: size, weight: bold ? .bold : .regular) }
            var attributes: [NSAttributedString.Key: Any] = [.font: font(pointSize), .foregroundColor: NSColor.black]
            var extent = (s as NSString).size(withAttributes: attributes)
            while extent.width > maxWidth && pointSize > minSize {
                pointSize -= 0.5; attributes[.font] = font(pointSize); extent = (s as NSString).size(withAttributes: attributes)
            }
            guard extent.width <= maxWidth+0.5 else { throw FoodError.invalid("Текст слишком длинный для этикетки. Сократите название или проверьте значения.") }
            let left = align == 1 ? x-extent.width/2 : (align == 2 ? x-extent.width : x)
            (s as NSString).draw(at: NSPoint(x: left.rounded(), y: CGFloat(height)-top-extent.height), withAttributes: attributes)
        }
        // A fixed full-width title line avoids collisions with long names or large weights.
        try text(food.name,x: 16,top: 8,size: 28,maxWidth: 432,bold: true,minSize: 16)
        try text("Порция: \(Numbers.display(food.grams)) г",x: 16,top: 42,size: 17,maxWidth: 235)
        let date = DateFormatter(); date.locale = Locale(identifier: "ru_RU"); date.timeZone = food.timeZone; date.dateFormat = "dd.MM.yyyy"
        try text(date.string(from: food.date),x: 448,top: 42,size: 17,maxWidth: 170,align: 2)
        rect(16,68,432,1)
        let centers: [CGFloat] = [171,268,345,420]
        for (i,label) in ["ккал","Б, г","Ж, г","У, г"].enumerated() {
            try text(label,x: centers[i],top: 73,size: 15,maxWidth: 75,align: 1)
        }
        for (row,values) in [food.per100.values,food.perPortion.values].enumerated() {
            let y: CGFloat = row == 0 ? 97 : 128
            try text(row == 0 ? "100 г" : "\(Numbers.display(food.grams)) г",x: 16,top: y,size: 21,maxWidth: 102,bold: row == 1)
            for (i,v) in values.enumerated() {
                try text(Numbers.display(v),x: centers[i],top: y,size: 23,maxWidth: i == 0 ? 96 : 74,bold: row == 1,align: 1)
            }
        }
        let filter = CIFilter.code128BarcodeGenerator(); filter.message = Data(food.barcode.utf8); filter.quietSpace = 10
        guard let code = filter.outputImage else { throw FoodError.invalid("Не удалось создать штрихкод.") }
        let ci = CIContext(options: [.useSoftwareRenderer: true])
        guard let codeImage = ci.createCGImage(code, from: code.extent) else { throw FoodError.invalid("Не удалось отрисовать штрихкод.") }
        let codeRep = NSBitmapImageRep(cgImage: codeImage)
        let module = min(3, 420/codeRep.pixelsWide)
        guard module >= 2 else { throw FoodError.invalid("Штрихкод слишком широкий.") }
        let start = (width-codeRep.pixelsWide*module)/2
        for x in 0..<codeRep.pixelsWide {
            if let c = codeRep.colorAt(x: x,y: codeRep.pixelsHigh/2)?.usingColorSpace(.deviceGray), c.whiteComponent < 0.5 {
                rect(start+x*module,166,module,43)
            }
        }
        try text(food.barcode,x: 232,top: 215,size: 15,maxWidth: 180,align: 1)
        graphics.flushGraphics()
        guard let bytes = rep.bitmapData else { throw FoodError.invalid("Нет растровых данных.") }
        let pixels = (0..<(width*height)).map { bytes[$0] < 170 ? UInt8(0) : UInt8(255) }
        return LabelRaster(width: width,height: height,pixels: pixels)
    }
}
