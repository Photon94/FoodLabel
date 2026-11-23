import Foundation
final class FakeNiim: NiimbotTransport {
    var sent=[[UInt8]](), incoming=[UInt8](), reject:UInt8?, corrupt=false, failWrite=false, rejectRow=false, failCleanup=false, partialStart=false, shortRow=false
    func write(_ bytes: Data) throws -> Int {
        if failWrite { throw FoodError.invalid("USB timeout") }
        var b=Array(bytes); if b.first == 3 { b.removeFirst() }; sent.append(b)
        let cmd=b[2]
        if partialStart && cmd == 1 { throw NiimbotWriteError(count:4,message:"Partial start") }
        if shortRow && cmd == 0x85 { return 5 }
        if failCleanup && cmd == 0xdc && sent.contains(where:{$0[2] == 0xf3}) { throw FoodError.invalid("Disconnected after completed print") }
        if rejectRow && cmd == 0x85 { incoming += Array(NiimbotPacket.encode(0,[0x85])) }
        let response: (UInt8,[UInt8])?
        switch cmd {
        case 0xc1: response=(0xc2,[3])
        case 0x40: response=(0x48,[3,17])
        case 0xdc: response=(0xdd,[UInt8](repeating:0,count:18)+[1])
        case 0x21: response=(0x31,[1])
        case 0x23: response=(0x33,[1])
        case 1: response=(2,[1])
        case 0x13: response=(0x14,[1,0])
        case 0xe3: response=(0xe4,[1])
        case 0xa3: response=(0xb3,[0,2,100,100])
        case 0xf3: response=(0xf4,[1])
        default: response=nil
        }
        if let (id,data)=response {
            var packet=Array(NiimbotPacket.encode(id,cmd == reject ? [0] : data))
            if corrupt { packet[packet.count-3] ^= 1 }
            incoming += packet
        }
        return bytes.count
    }
    func read() throws -> Data {
        guard !incoming.isEmpty else { throw FoodError.invalid("No response") }
        let count=min(3,incoming.count), data=Data(incoming.prefix(count)); incoming.removeFirst(count); return data
    }
}
@main struct NiimbotTests {
    static func check(_ value: Bool,_ name:String) { if !value { fatalError(name) } }
    static func main() throws {
        check(Array(NiimbotPacket.encode(0x40,[8])) == [0x55,0x55,0x40,1,8,0x49,0xaa,0xaa],"Known model query packet")
        var pixels=[UInt8](repeating:255,count:592*354)
        pixels[0]=0; pixels[591]=0; pixels[592+200]=0
        let raster=LabelRaster(width:592,height:354,pixels:pixels)
        let job=try NiimbotJob(raster:raster,copies:2)
        let restored=try NiimbotJob(data:job.data)
        check(restored.rows.count == 354,"Every row preserved")
        var reconstructed=[UInt8](repeating:255,count:pixels.count)
        for (y,row) in restored.rows.enumerated() { for x in 0..<592 where row[x/8] & (0x80 >> (x%8)) != 0 { reconstructed[y*592+x]=0 } }
        check(reconstructed == pixels,"Exact print raster, bit order and final column")
        let transport=FakeNiim(), session=NiimbotSession(transport:transport)
        try session.identify(); try session.printJob(restored)
        check(transport.sent.filter {$0[2] == 1}.count == 1,"One start, no duplicate job")
        check(transport.sent.filter {$0[2] == 0x85}.count == 2,"Black row count")
        check(Array(transport.sent.first {$0[2] == 0x13}![4..<10]) == [1,98,2,80,0,2],"Height width copies big endian")
        for mode in 0..<3 {
            let fake=FakeNiim(); if mode == 0 { fake.reject=0x13 }; if mode == 1 { fake.corrupt=true }; if mode == 2 { fake.failWrite=true }
            let s=NiimbotSession(transport:fake); var failed=false
            do { try s.identify(); try s.printJob(job) } catch { failed=true }
            check(failed,"Reject bad ACK/checksum/USB failure")
            check(fake.sent.filter {$0[2] == 1}.count <= 1,"Never retry on error")
        }
        for mode in 0..<3 {
            let fake=FakeNiim(); fake.rejectRow=mode == 0; fake.partialStart=mode == 1; fake.shortRow=mode == 2
            let s=NiimbotSession(transport:fake); try s.identify(); var failed=false
            do { try s.printJob(job) } catch { failed=true }
            check(failed,"Row rejection or partial write must fail")
            check(s.transferred > 0,"Partial job stays uncertain")
            check(fake.sent.contains {$0[2] == 0xda},"Abort incomplete job without retry")
        }
        let cleanup=FakeNiim(); cleanup.failCleanup=true
        let completed=NiimbotSession(transport:cleanup); try completed.identify(); try completed.printJob(job)
        print("PASS: NIIMBOT frame checksum, fragmented responses, raster round-trip, acknowledgements and no retries")
    }
}
