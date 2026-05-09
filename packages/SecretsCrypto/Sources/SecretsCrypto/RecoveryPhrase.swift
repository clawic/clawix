import Foundation
import Crypto

public enum RecoveryPhrase {

    public static let wordCount = 24
    public static let entropyByteCount = 32

    public enum Error: Swift.Error, Equatable, CustomStringConvertible {
        case invalidWordCount(Int)
        case unknownWord(String)
        case checksumMismatch

        public var description: String {
            switch self {
            case .invalidWordCount(let n): return "RecoveryPhrase: expected \(RecoveryPhrase.wordCount) words, got \(n)"
            case .unknownWord(let w): return "RecoveryPhrase: word not in BIP39 wordlist: \(w)"
            case .checksumMismatch: return "RecoveryPhrase: checksum mismatch"
            }
        }
    }

    public static func generate() -> [String] {
        let entropy = SecureRandom.bytes(entropyByteCount)
        return encode(entropy: entropy)
    }

    public static func encode(entropy: Data) -> [String] {
        precondition(entropy.count == entropyByteCount, "entropy must be \(entropyByteCount) bytes")
        let checksumByte = Array(SHA256.hash(data: entropy)).first!

        var bits = [UInt8](repeating: 0, count: (entropyByteCount + 1) * 8)
        for (byteIdx, byte) in entropy.enumerated() {
            for bit in 0..<8 {
                bits[byteIdx * 8 + bit] = (byte >> (7 - bit)) & 1
            }
        }
        for bit in 0..<8 {
            bits[entropyByteCount * 8 + bit] = (checksumByte >> (7 - bit)) & 1
        }

        var words = [String]()
        words.reserveCapacity(wordCount)
        for chunk in 0..<wordCount {
            var index = 0
            for b in 0..<11 {
                index = (index << 1) | Int(bits[chunk * 11 + b])
            }
            words.append(BIP39Wordlist.words[index])
        }
        return words
    }

    public static func decode(_ phrase: [String]) throws -> Data {
        guard phrase.count == wordCount else { throw Error.invalidWordCount(phrase.count) }
        let normalized = phrase.map { $0.lowercased() }

        var bits = [UInt8](repeating: 0, count: wordCount * 11)
        for (chunkIdx, word) in normalized.enumerated() {
            guard let index = BIP39Wordlist.indexByWord[word] else {
                throw Error.unknownWord(word)
            }
            for bit in 0..<11 {
                bits[chunkIdx * 11 + bit] = UInt8((index >> (10 - bit)) & 1)
            }
        }

        var entropy = [UInt8](repeating: 0, count: entropyByteCount)
        for byteIdx in 0..<entropyByteCount {
            var byte: UInt8 = 0
            for bit in 0..<8 {
                byte = (byte << 1) | bits[byteIdx * 8 + bit]
            }
            entropy[byteIdx] = byte
        }
        var checksum: UInt8 = 0
        for bit in 0..<8 {
            checksum = (checksum << 1) | bits[entropyByteCount * 8 + bit]
        }

        let entropyData = Data(entropy)
        let expected = Array(SHA256.hash(data: entropyData)).first!
        guard expected == checksum else { throw Error.checksumMismatch }
        return entropyData
    }

    public static func normalize(_ raw: String) -> [String] {
        raw.split(whereSeparator: { $0.isWhitespace || $0 == "," })
            .map { String($0).lowercased() }
    }
}
