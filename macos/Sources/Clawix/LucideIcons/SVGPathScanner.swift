struct SVGPathScanner {
    let chars: [Character]
    var pos: Int = 0

    init(_ s: String) { chars = Array(s) }

    var atEnd: Bool {
        var i = pos
        while i < chars.count, chars[i].isWhitespace || chars[i] == "," { i += 1 }
        return i >= chars.count
    }

    mutating func skipWSComma() {
        while pos < chars.count, chars[pos].isWhitespace || chars[pos] == "," {
            pos += 1
        }
    }

    func peekIsLetter() -> Bool {
        var i = pos
        while i < chars.count, chars[i].isWhitespace || chars[i] == "," { i += 1 }
        return i < chars.count && chars[i].isLetter
    }

    mutating func consumeLetter() -> Character? {
        skipWSComma()
        guard pos < chars.count, chars[pos].isLetter else { return nil }
        let c = chars[pos]
        pos += 1
        return c
    }

    mutating func nextNumber() -> Double? {
        skipWSComma()
        guard pos < chars.count else { return nil }
        let start = pos
        if chars[pos] == "+" || chars[pos] == "-" { pos += 1 }
        var hasDigits = false
        while pos < chars.count, chars[pos].isASCII, chars[pos].isNumber {
            pos += 1
            hasDigits = true
        }
        if pos < chars.count, chars[pos] == "." {
            pos += 1
            while pos < chars.count, chars[pos].isASCII, chars[pos].isNumber {
                pos += 1
                hasDigits = true
            }
        }
        if pos < chars.count, chars[pos] == "e" || chars[pos] == "E" {
            pos += 1
            if pos < chars.count, chars[pos] == "+" || chars[pos] == "-" { pos += 1 }
            while pos < chars.count, chars[pos].isASCII, chars[pos].isNumber {
                pos += 1
            }
        }
        guard hasDigits else { return nil }
        return Double(String(chars[start..<pos]))
    }

    // SVG arc flags are single 0/1 chars and may not be separated
    // from the next number by whitespace.
    mutating func nextFlag() -> Bool? {
        skipWSComma()
        guard pos < chars.count else { return nil }
        let c = chars[pos]
        guard c == "0" || c == "1" else { return nil }
        pos += 1
        return c == "1"
    }
}
