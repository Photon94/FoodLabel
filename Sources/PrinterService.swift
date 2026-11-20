import Foundation
struct PrinterResult: Sendable { let success: Bool; let transferred: Int; let message: String }
actor PrinterService {
    func probe() -> PrinterResult { call(nil) }
    func send(_ payload: Data) -> PrinterResult { call(payload) }
    private func call(_ payload: Data?) -> PrinterResult {
        var buffer=[CChar](repeating:0,count:1024), transferred:Int32=0
        let rc:Int32
        if let payload {
            rc=payload.withUnsafeBytes { bytes in foodlabel_usb(bytes.bindMemory(to:UInt8.self).baseAddress,Int32(payload.count),&transferred,&buffer,Int32(buffer.count)) }
        } else { rc=foodlabel_usb(nil,0,&transferred,&buffer,Int32(buffer.count)) }
        return PrinterResult(success:rc==0,transferred:Int(transferred),message:String(cString:buffer))
    }
}
