import AppKit
let directory=URL(fileURLWithPath:"build/AppIcon.iconset")
try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
for size in [16,32,128,256,512] {
    for scale in [1,2] {
        let pixels=size*scale
        let rep=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:pixels,pixelsHigh:pixels,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:rep)
        let transform=NSAffineTransform(); transform.scale(by:CGFloat(pixels)/1024); transform.concat()
        NSColor(calibratedRed:0.12,green:0.38,blue:0.29,alpha:1).setFill()
        NSBezierPath(roundedRect:NSRect(x:52,y:52,width:920,height:920),xRadius:205,yRadius:205).fill()
        NSColor(calibratedRed:0.98,green:0.97,blue:0.92,alpha:1).setFill()
        NSBezierPath(roundedRect:NSRect(x:206,y:239,width:612,height:546),xRadius:48,yRadius:48).fill()
        NSColor(calibratedRed:0.12,green:0.38,blue:0.29,alpha:1).setFill()
        NSBezierPath(roundedRect:NSRect(x:280,y:650,width:310,height:46),xRadius:12,yRadius:12).fill()
        NSBezierPath(roundedRect:NSRect(x:280,y:562,width:460,height:25),xRadius:8,yRadius:8).fill()
        NSBezierPath(roundedRect:NSRect(x:280,y:496,width:360,height:25),xRadius:8,yRadius:8).fill()
        var x:CGFloat=281
        for width:CGFloat in [12,24,10,10,28,16,10,24,12,20,10,30,14,10,22] {
            NSRect(x:x,y:322,width:width,height:100).fill(); x += width+12
        }
        NSGraphicsContext.restoreGraphicsState()
        let suffix=scale==2 ? "@2x" : ""
        try rep.representation(using:.png,properties:[:])!.write(to:directory.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
