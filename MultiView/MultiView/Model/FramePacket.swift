import Foundation

struct FramePacket {
    let isKeyFrame: Bool
    var presentationTime: UInt64
    let parameterSets: Data?
    let payload: Data

    func serialized() -> Data {
        let paramSets = parameterSets ?? Data()
        var data = Data(capacity: 12 + paramSets.count + payload.count)

        data.append(WireMessageType.frame.rawValue)

        var flags: UInt8 = 0
        if isKeyFrame { flags |= 0x01 }
        if parameterSets != nil { flags |= 0x02 }
        data.append(flags)

        var pts = presentationTime.bigEndian
        data.append(Data(bytes: &pts, count: 8))

        var paramLen = UInt16(paramSets.count).bigEndian
        data.append(Data(bytes: &paramLen, count: 2))
        data.append(paramSets)

        data.append(payload)
        return data
    }

    init(isKeyFrame: Bool, presentationTime: UInt64, parameterSets: Data?, payload: Data) {
        self.isKeyFrame = isKeyFrame
        self.presentationTime = presentationTime
        self.parameterSets = parameterSets
        self.payload = payload
    }

    init?(data: Data) {
        guard data.count > 11 else { return nil }
        let flags = data[0]
        self.isKeyFrame = flags & 0x01 != 0
        let hasParamSets = flags & 0x02 != 0

        self.presentationTime = data.subdata(in: 1..<9).withUnsafeBytes { $0.load(as: UInt64.self).bigEndian }
        let paramLen = Int(data.subdata(in: 9..<11).withUnsafeBytes { $0.load(as: UInt16.self).bigEndian })

        guard data.count >= 11 + paramLen else { return nil }
        self.parameterSets = hasParamSets ? data.subdata(in: 11..<(11 + paramLen)) : nil
        self.payload = data.subdata(in: (11 + paramLen)..<data.count)
    }
}
