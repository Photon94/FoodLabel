import Foundation
struct PrinterResult: Sendable { let success: Bool; let transferred: Int; let message: String }
actor PrinterService {
    func connectedProfiles() -> [PrinterProfile] {
        let mask=foodlabel_printers()
        return PrinterProfile.allCases.filter { mask & ($0 == .xprinter ? 1 : 2) != 0 }
    }
    func probe(profile: PrinterProfile = .xprinter) -> PrinterResult { profile == .niimbot ? niimbot(nil) : call(nil) }
    func send(_ payload: Data, profile: PrinterProfile = .xprinter) -> PrinterResult { profile == .niimbot ? niimbot(payload) : call(payload) }
    private func niimbot(_ payload: Data?) -> PrinterResult {
        var session: NiimbotSession?
        do {
            let transport=try NiimbotUSBTransport()
            defer { transport.close() }
            let connected=NiimbotSession(transport:transport); session=connected
            try connected.identify()
            if let payload { try connected.printJob(NiimbotJob(data:payload)) }
            return PrinterResult(success:true,transferred:connected.transferred,message:payload == nil ? "NIIMBOT B21 Pro подключён по USB. Этикетки 50 × 30 мм." : "NIIMBOT подтвердил завершение печати. Проверьте этикетки.")
        } catch {
            return PrinterResult(success:false,transferred:session?.transferred ?? 0,message:error.localizedDescription)
        }
    }
    private func call(_ payload: Data?) -> PrinterResult {
        var buffer=[CChar](repeating:0,count:1024), transferred:Int32=0
        let rc:Int32
        if let payload {
            rc=payload.withUnsafeBytes { bytes in foodlabel_usb(bytes.bindMemory(to:UInt8.self).baseAddress,Int32(payload.count),&transferred,&buffer,Int32(buffer.count)) }
        } else { rc=foodlabel_usb(nil,0,&transferred,&buffer,Int32(buffer.count)) }
        return PrinterResult(success:rc==0,transferred:Int(transferred),message:String(cString:buffer))
    }
}

private final class NiimbotUSBTransport: NiimbotTransport {
    private var handle: UnsafeMutableRawPointer?
    init() throws {
        var message=[CChar](repeating:0,count:1024)
        handle=foodlabel_niim_open(&message,Int32(message.count))
        guard handle != nil else { throw FoodError.invalid(String(cString:message)) }
    }
    func close() { if let handle { foodlabel_niim_close(handle); self.handle=nil } }
    deinit { close() }
    func write(_ bytes: Data) throws -> Int {
        var buffer=Array(bytes), count:Int32=0
        let rc=foodlabel_niim_transfer(handle,1,&buffer,Int32(buffer.count),&count)
        guard rc == 0 else { throw NiimbotWriteError(count:Int(count),message:"Передача USB прервана (код \(rc)). Проверьте принтер перед повторной печатью.") }
        return Int(count)
    }
    func read() throws -> Data {
        var buffer=[UInt8](repeating:0,count:512), count:Int32=0
        let rc=foodlabel_niim_transfer(handle,0,&buffer,512,&count)
        // libusb can return bytes along with a read timeout. Preserve them.
        if rc == 0 || rc == -7 { return Data(buffer.prefix(Int(count))) }
        throw FoodError.invalid("Не удалось прочитать ответ NIIMBOT (USB \(rc)).")
    }
}
