import Foundation

// Wire format documented by MultiMote/niimbluelib (MIT); no firmware changes.
enum NiimbotPacket {
    static func encode(_ command: UInt8,_ data: [UInt8] = [1]) -> Data {
        precondition(data.count <= 255)
        return Data([0x55,0x55,command,UInt8(data.count)] + data + [data.reduce(command ^ UInt8(data.count),^),0xaa,0xaa])
    }
    static func u16(_ n: Int) -> [UInt8] { [UInt8(n >> 8), UInt8(n & 255)] }
}
struct NiimbotJob {
    let width: Int
    let rows: [[UInt8]]
    let copies: Int
    var data: Data { Data(Array("NIM1".utf8) + NiimbotPacket.u16(copies) + rows.flatMap {$0}) }
    init(raster: LabelRaster,copies: Int) throws {
        guard [576,592].contains(raster.width), raster.height == 354, raster.pixels.count == raster.width*354, (1...100).contains(copies) else {
            throw FoodError.invalid("Неверный размер этикетки NIIMBOT или количество копий.")
        }
        self.copies=copies; self.width=raster.width
        rows=(0..<354).map { y in
            (0..<(raster.width/8)).map { byte in
                (0..<8).reduce(UInt8(0)) { result,bit in result | (raster.pixels[y*raster.width+byte*8+bit] == 0 ? UInt8(0x80 >> bit) : 0) }
            }
        }
    }
    init(data: Data) throws {
        let b=Array(data)
        guard [6+72*354,6+74*354].contains(b.count), Array(b.prefix(4)) == Array("NIM1".utf8) else { throw FoodError.invalid("Повреждено задание NIIMBOT.") }
        width=(b.count-6)/354*8
        copies=Int(b[4])*256+Int(b[5])
        guard (1...100).contains(copies) else { throw FoodError.invalid("Неверное число копий NIIMBOT.") }
        let rowBytes=width/8
        rows=(0..<354).map { Array(b[(6+$0*rowBytes)..<(6+($0+1)*rowBytes)]) }
    }
}
protocol NiimbotTransport: AnyObject {
    func write(_ bytes: Data) throws -> Int
    func read() throws -> Data
}
struct NiimbotWriteError: LocalizedError {
    let count: Int
    let message: String
    var errorDescription: String? { message }
}
final class NiimbotSession {
    private let transport: NiimbotTransport
    private var buffered=[UInt8]()
    private(set) var transferred=0
    private var counting=false
    init(transport: NiimbotTransport) { self.transport=transport }
    private func send(_ command: UInt8,_ data: [UInt8] = [1],prefix: Bool = false) throws {
        let packet=(prefix ? Data([3]) : Data())+NiimbotPacket.encode(command,data)
        let count: Int
        do { count=try transport.write(packet) }
        catch let error as NiimbotWriteError { if counting { transferred += error.count }; throw error }
        if counting { transferred += count }
        guard count == packet.count else { throw FoodError.invalid("Передача NIIMBOT прервана. Проверьте этикетки перед повторной печатью.") }
    }
    private func receive(_ expected: UInt8) throws -> [UInt8] {
        let deadline=Date().addingTimeInterval(5)
        while Date() < deadline {
            if buffered.count >= 4 {
                guard buffered[0] == 0x55, buffered[1] == 0x55 else { throw FoodError.invalid("Неизвестный ответ NIIMBOT.") }
                let size=Int(buffered[3])+7
                if buffered.count >= size {
                    let packet=Array(buffered.prefix(size)); buffered.removeFirst(size)
                    let body=Array(packet[4..<(size-3)])
                    guard packet[size-2] == 0xaa, packet[size-1] == 0xaa,
                          body.reduce(packet[2] ^ packet[3],^) == packet[size-3] else { throw FoodError.invalid("Ошибка контрольной суммы ответа NIIMBOT.") }
                    if packet[2] == 0x00 { throw FoodError.invalid("NIIMBOT отклонил неподдерживаемую команду. Проверьте этикетки перед повторной печатью.") }
                    if packet[2] == 0xdb { throw FoodError.invalid("NIIMBOT сообщает об ошибке (код \(body.first ?? 0)). Проверьте крышку, бумагу и заряд.") }
                    if packet[2] == expected { return body }
                    // Status notifications may arrive between solicited responses.
                    continue
                }
            }
            buffered += try transport.read()
            guard buffered.count <= 8192 else { throw FoodError.invalid("Слишком большой ответ NIIMBOT.") }
        }
        throw FoodError.invalid("NIIMBOT не подтвердил команду вовремя. Проверьте этикетки перед повторной печатью.")
    }
    private func exchange(_ command: UInt8,_ data: [UInt8] = [1],response: UInt8) throws -> [UInt8] {
        try send(command,data,prefix:command == 0xc1); return try receive(response)
    }
    private func ack(_ command: UInt8,_ data: [UInt8] = [1],response: UInt8) throws {
        let result=try exchange(command,data,response:response)
        guard result == [1] || (command == 0x13 && result == [1,0]) else { throw FoodError.invalid("NIIMBOT отклонил команду \(String(command,radix:16)) (ответ: \(result)). Проверьте принтер перед повторной печатью.") }
    }
    func identify() throws {
        let connected=try exchange(0xc1,response:0xc2)
        guard connected.count == 1, (1...3).contains(connected[0]),
              try exchange(0x40,[8],response:0x48) == [3,17] else {
            throw FoodError.invalid("Устройство не подтвердило модель NIIMBOT B21 Pro.")
        }
        let heartbeat=try exchange(0xdc,[1],response:0xdd)
        let offset: Int
        switch heartbeat.count { case 13: offset=9; case 19: offset=15; default: throw FoodError.invalid("Неизвестный статус NIIMBOT. Печать отключена.") }
        guard heartbeat[offset] == 0 else { throw FoodError.invalid("Закройте крышку NIIMBOT.") }
        guard heartbeat[offset+2] == 0, heartbeat[offset+3] != 0 else { throw FoodError.invalid("Проверьте рулон этикеток в NIIMBOT.") }
    }
    func printJob(_ job: NiimbotJob) throws {
        do { try execute(job) }
        catch {
            if counting { try? send(0xda) } // Cancel this incomplete session, never restart it.
            throw error
        }
    }
    private func execute(_ job: NiimbotJob) throws {
        try ack(0x23,[1],response:0x33) // gap labels
        try ack(0x21,[3],response:0x31)
        // Count from PrintStart, including partial writes: anything after this can be uncertain.
        counting=true
        try ack(1,NiimbotPacket.u16(job.copies)+[0,0,0,0,0,0,0],response:2)
        try send(0xa3) // B21 Pro can drop the first post-start packet.
        try ack(0x13,NiimbotPacket.u16(354)+NiimbotPacket.u16(job.width)+NiimbotPacket.u16(job.copies)+[0,0,0,0,0,0,0],response:0x14)
        for (y,row) in job.rows.enumerated() {
            if row.allSatisfy({$0 == 0}) { try send(0x84,NiimbotPacket.u16(y)+[1]) }
            else {
                // Three 192-dot sections, each count fits in one byte.
                let total=row.reduce(0) {$0+$1.nonzeroBitCount}
                let counts: [UInt8] = row.count <= 72
                    ? (0..<3).map { section in UInt8(row[(section*24)..<((section+1)*24)].reduce(0) {$0+$1.nonzeroBitCount}) }
                    : [0,UInt8(total & 255),UInt8(total >> 8)]
                try send(0x85,NiimbotPacket.u16(y)+counts+[1]+row)
            }
            Thread.sleep(forTimeInterval:0.001)
        }
        try ack(0xe3,response:0xe4)
        let deadline=Date().addingTimeInterval(Double(job.copies)*5+15)
        var complete=false
        while Date() < deadline {
            Thread.sleep(forTimeInterval:0.3)
            let status=try exchange(0xa3,response:0xb3)
            guard status.count >= 4 else { throw FoodError.invalid("Неполный статус печати NIIMBOT.") }
            if status.count == 10, status[6] != 0 { throw FoodError.invalid("Ошибка печати NIIMBOT: \(status[6]).") }
            if Int(status[0])*256+Int(status[1]) == job.copies { complete=true; break }
        }
        guard complete else { throw FoodError.invalid("NIIMBOT не подтвердил завершение. Проверьте этикетки перед повторной печатью.") }
        try ack(0xf3,response:0xf4)
        try? send(0xdc,[1]) // Printing is confirmed; this cleanup cannot change that result. Consume the model's post-end dropped command.
    }
}
