import XCTest
@testable import SecretsCrypto

final class RecoveryPhraseTests: XCTestCase {

    func testWordlistSize() {
        XCTAssertEqual(BIP39Wordlist.words.count, 2048)
        XCTAssertEqual(BIP39Wordlist.words.first, "abandon")
        XCTAssertEqual(BIP39Wordlist.words.last, "zoo")
        XCTAssertEqual(BIP39Wordlist.indexByWord["abandon"], 0)
        XCTAssertEqual(BIP39Wordlist.indexByWord["zoo"], 2047)
    }

    func testGenerateProduces24Words() {
        let phrase = RecoveryPhrase.generate()
        XCTAssertEqual(phrase.count, 24)
        for word in phrase {
            XCTAssertNotNil(BIP39Wordlist.indexByWord[word], "word \(word) not in BIP39 wordlist")
        }
    }

    func testRoundTripWithKnownEntropy() throws {
        // Test vector from BIP39 reference.
        // Entropy 32 zero bytes -> 24 words with the well-known prefix.
        let entropy = Data(repeating: 0x00, count: 32)
        let words = RecoveryPhrase.encode(entropy: entropy)
        XCTAssertEqual(words.count, 24)
        XCTAssertEqual(words.prefix(3), ["abandon", "abandon", "abandon"])
        let decoded = try RecoveryPhrase.decode(words)
        XCTAssertEqual(decoded, entropy)
    }

    func testRoundTripWithRandomEntropy() throws {
        for _ in 0..<10 {
            let entropy = SecureRandom.bytes(32)
            let words = RecoveryPhrase.encode(entropy: entropy)
            let decoded = try RecoveryPhrase.decode(words)
            XCTAssertEqual(decoded, entropy)
        }
    }

    func testGenerateIsRandom() {
        let a = RecoveryPhrase.generate()
        let b = RecoveryPhrase.generate()
        XCTAssertNotEqual(a, b)
    }

    func testInvalidWordCount() {
        XCTAssertThrowsError(try RecoveryPhrase.decode(["abandon", "abandon"])) { err in
            XCTAssertEqual(err as? RecoveryPhrase.Error, .invalidWordCount(2))
        }
    }

    func testUnknownWord() {
        var phrase = RecoveryPhrase.generate()
        phrase[5] = "notarealbip39word"
        XCTAssertThrowsError(try RecoveryPhrase.decode(phrase)) { err in
            XCTAssertEqual(err as? RecoveryPhrase.Error, .unknownWord("notarealbip39word"))
        }
    }

    func testChecksumMismatchOnSwap() throws {
        var phrase = RecoveryPhrase.generate()
        // Swap first and second words; very high probability of breaking checksum.
        phrase.swapAt(0, 1)
        XCTAssertThrowsError(try RecoveryPhrase.decode(phrase)) { err in
            XCTAssertEqual(err as? RecoveryPhrase.Error, .checksumMismatch)
        }
    }

    func testNormalize() {
        let phrase = RecoveryPhrase.normalize("  Abandon Ability   able\nAbout, ABOVE  ")
        XCTAssertEqual(phrase, ["abandon", "ability", "able", "about", "above"])
    }

    func testCaseInsensitiveDecoding() throws {
        let entropy = Data(repeating: 0x10, count: 32)
        let words = RecoveryPhrase.encode(entropy: entropy)
        let mixedCase = words.map { $0.uppercased() }
        let decoded = try RecoveryPhrase.decode(mixedCase)
        XCTAssertEqual(decoded, entropy)
    }
}
