import Foundation

/// Tiny PCM-WAV encoder shared by the STT path. Encodes a 16 kHz mono
/// Float32 buffer as a 16-bit PCM WAV `Data` blob — the format every
/// OpenAI-compatible audio endpoint accepts (Whisper, Groq, Deepgram,
/// custom).
enum WAVEncoder {

    static func encodePCM16(samples: [Float], sampleRate: Int = 16_000, channels: Int = 1) -> Data {
        let bitsPerSample: Int = 16
        let byteRate = sampleRate * channels * (bitsPerSample / 8)
        let blockAlign = channels * (bitsPerSample / 8)
        let dataBytes = samples.count * (bitsPerSample / 8)
        var data = Data(capacity: 44 + dataBytes)
        data.append("RIFF".data(using: .ascii)!)
        data.append(uint32LE(UInt32(36 + dataBytes)))
        data.append("WAVE".data(using: .ascii)!)
        data.append("fmt ".data(using: .ascii)!)
        data.append(uint32LE(16))
        data.append(uint16LE(1)) // PCM
        data.append(uint16LE(UInt16(channels)))
        data.append(uint32LE(UInt32(sampleRate)))
        data.append(uint32LE(UInt32(byteRate)))
        data.append(uint16LE(UInt16(blockAlign)))
        data.append(uint16LE(UInt16(bitsPerSample)))
        data.append("data".data(using: .ascii)!)
        data.append(uint32LE(UInt32(dataBytes)))
        for sample in samples {
            let clamped = max(-1, min(1, sample))
            let value = Int16(clamped * Float(Int16.max))
            data.append(uint16LE(UInt16(bitPattern: value)))
        }
        return data
    }

    private static func uint16LE(_ v: UInt16) -> Data {
        var x = v.littleEndian
        return Data(bytes: &x, count: MemoryLayout<UInt16>.size)
    }

    private static func uint32LE(_ v: UInt32) -> Data {
        var x = v.littleEndian
        return Data(bytes: &x, count: MemoryLayout<UInt32>.size)
    }
}
