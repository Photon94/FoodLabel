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
    static func render(_ food: ValidFood, profile: PrinterProfile = .xprinter) throws -> LabelRaster {
        let width = profile == .niimbot ? 592 : Self.width
        let height = profile == .niimbot ? 354 : Self.height
        let contentTop = profile == .niimbot ? 16 : 0
        let sx = CGFloat(width)/464, sy = CGFloat(height-contentTop)/240
        let fontScale: CGFloat = profile == .niimbot ? 1.4 : 1

        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                bitsPerSample: 8, samplesPerPixel: 1, hasAlpha: false, isPlanar: false,
                colorSpaceName: .deviceWhite, bytesPerRow: width, bitsPerPixel: 8),
              let graphics = NSGraphicsContext(bitmapImageRep: rep) else { throw FoodError.invalid("Не удалось подготовить этикетку.") }
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = graphics
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSColor.white.setFill(); NSRect(x: 0,y: 0,width: width,height: height).fill()
        func pixelRect(_ x: Int,_ y: Int,_ w: Int,_ h: Int) { NSColor.black.setFill(); NSRect(x: x,y: height-contentTop-y-h,width: w,height: h).fill() }
        func rect(_ x: Int,_ y: Int,_ w: Int,_ h: Int) {
            pixelRect(Int((CGFloat(x)*sx).rounded()),Int((CGFloat(y)*sy).rounded()),Int((CGFloat(w)*sx).rounded()),max(1,Int((CGFloat(h)*sy).rounded())))
        }
        func text(_ s: String, x: CGFloat, top: CGFloat, size: CGFloat, maxWidth: CGFloat, bold: Bool = false, align: Int = 0, minSize: CGFloat = 13) throws {
            let x=x*sx, top=top*sy, maxWidth=maxWidth*sx, minSize=minSize*fontScale
            var pointSize = size*fontScale
            func font(_ size: CGFloat) -> NSFont { NSFont(name: bold ? "Arial-BoldMT" : "ArialMT", size: size) ?? NSFont.systemFont(ofSize: size, weight: bold ? .bold : .regular) }
            var attributes: [NSAttributedString.Key: Any] = [.font: font(pointSize), .foregroundColor: NSColor.black]
            var extent = (s as NSString).size(withAttributes: attributes)
            while extent.width > maxWidth && pointSize > minSize {
                pointSize -= 0.5; attributes[.font] = font(pointSize); extent = (s as NSString).size(withAttributes: attributes)
            }
            guard extent.width <= maxWidth+0.5 else { throw FoodError.invalid("Текст слишком длинный для этикетки. Сократите название или проверьте значения.") }
            let left = align == 1 ? x-extent.width/2 : (align == 2 ? x-extent.width : x)
            (s as NSString).draw(at: NSPoint(x: left.rounded(), y: CGFloat(height-contentTop)-top-extent.height), withAttributes: attributes)
        }
        // A fixed full-width title line avoids collisions with long names or large weights.
        try text(food.name,x: 16,top: 8,size: 28,maxWidth: 432,bold: true,minSize: 16)
        try text("Порция: \(Numbers.display(food.grams)) г",x: 16,top: 42,size: 17,maxWidth: 235)
        let date = DateFormatter(); date.locale = Locale(identifier: "ru_RU"); date.timeZone = food.timeZone; date.dateFormat = "dd.MM.yyyy"
        try text(date.string(from: food.date),x: 448,top: 42,size: 17,maxWidth: 170,align: 2)
        rect(16,68,432,1)
        let compact=food.qrLink != nil
        let centers: [CGFloat] = compact ? [105,155,205,255] : [171,268,345,420]
        for (i,label) in ["ккал","Б, г","Ж, г","У, г"].enumerated() {
            try text(label,x: centers[i],top: 73,size: compact ? 12 : 15,maxWidth: compact ? 48 : 75,align: 1,minSize: compact ? 11 : 13)
        }
        for (row,values) in [food.per100.values,food.perPortion.values].enumerated() {
            let y: CGFloat = row == 0 ? 97 : 128
            try text(row == 0 ? "100 г" : "\(Numbers.display(food.grams)) г",x: 16,top: y,size: compact ? 16 : 21,maxWidth: compact ? 62 : 102,bold: row == 1)
            for (i,v) in values.enumerated() {
                try text(Numbers.display(v),x: centers[i],top: y,size: compact ? 17 : 23,maxWidth: compact ? 48 : (i == 0 ? 96 : 74),bold: row == 1,align: 1)
            }
        }
        let filter = CIFilter.code128BarcodeGenerator(); filter.message = Data(food.barcode.utf8); filter.quietSpace = 10
        guard let code = filter.outputImage else { throw FoodError.invalid("Не удалось создать штрихкод.") }
        let ci = CIContext(options: [.useSoftwareRenderer: true])
        guard let codeImage = ci.createCGImage(code, from: code.extent) else { throw FoodError.invalid("Не удалось отрисовать штрихкод.") }
        let codeRep = NSBitmapImageRep(cgImage: codeImage)
        let barcodeWidth=Int(CGFloat(compact ? 256 : 420)*sx)
        let module = min(profile == .niimbot ? 4 : 3, barcodeWidth/codeRep.pixelsWide)
        guard module >= 2 else { throw FoodError.invalid("Штрихкод слишком широкий.") }
        let start = compact ? Int(16*sx)+(barcodeWidth-codeRep.pixelsWide*module)/2 : (width-codeRep.pixelsWide*module)/2
        for x in 0..<codeRep.pixelsWide {
            if let c = codeRep.colorAt(x: x,y: codeRep.pixelsHigh/2)?.usingColorSpace(.deviceGray), c.whiteComponent < 0.5 {
                pixelRect(start+x*module,Int(166*sy),module,Int(43*sy))
            }
        }
        try text(food.barcode,x: compact ? 144 : 232,top: 215,size: 15,maxWidth: 180,align: 1)
        if let link=food.qrLink {
            let qr=CIFilter.qrCodeGenerator(); qr.message=Data(link.utf8); qr.correctionLevel="M"
            guard let output=qr.outputImage, let generated=ci.createCGImage(output,from:output.extent) else {
                throw FoodError.invalid("Не удалось создать QR-код для ссылки.")
            }
            let bitmap=NSBitmapImageRep(cgImage:generated)
            func black(_ x:Int,_ y:Int) -> Bool {
                (bitmap.colorAt(x:x,y:y)?.usingColorSpace(.deviceGray)?.whiteComponent ?? 1) < 0.5
            }
            // Strip Core Image's own border, then add exactly four quiet modules.
            var left=bitmap.pixelsWide, top=bitmap.pixelsHigh, right=0, bottom=0
            for y in 0..<bitmap.pixelsHigh { for x in 0..<bitmap.pixelsWide where black(x,y) {
                left=min(left,x); top=min(top,y); right=max(right,x); bottom=max(bottom,y)
            } }
            let modules=right-left+1, quiet=4, side=Int(160*sx)
            guard modules > 0, modules == bottom-top+1 else { throw FoodError.invalid("Не удалось отрисовать QR-код.") }
            let scale=side/(modules+quiet*2)
            guard scale >= 3 else {
                throw FoodError.invalid("Ссылка слишком длинная для читаемого QR на этикетке \(profile.paper). Вставьте более короткую ссылку из приложения.")
            }
            let padding=(side-(modules+quiet*2)*scale)/2+quiet*scale
            for y in 0..<modules { for x in 0..<modules where black(left+x,top+y) {
                pixelRect(Int(288*sx)+padding+x*scale,Int(74*sy)+(Int(160*sy)-side)/2+padding+y*scale,scale,scale)
            } }
        }
        graphics.flushGraphics()
        guard let bytes = rep.bitmapData else { throw FoodError.invalid("Нет растровых данных.") }
        let pixels = (0..<(width*height)).map { bytes[$0] < 170 ? UInt8(0) : UInt8(255) }
        return LabelRaster(width: width,height: height,pixels: pixels)
    }
}
