import Foundation

enum PasswordStructureAnalyzer {
    private static let builtInKeyboardSequences = [
        "qwertyuiop", "asdfghjkl", "zxcvbnm", "1234567890",
        "qwerty", "asdfgh", "zxcvbn", "1qaz2wsx", "zaq12wsx",
        "qazwsx", "wsxedc", "edcrfv", "rfvtgb", "tgbyhn",
        "poiuy", "lkjhg", "mnbvc", "098765", "987654"
    ]

    static func findings(
        in password: String,
        commonRootIndex: CommonRootIndex? = nil
    ) -> [PatternFinding] {
        guard !password.isEmpty else { return [] }
        var findings: [PatternFinding] = []

        if let commonRootIndex {
            findings.append(contentsOf: commonRootIndex.commonRootFindings(in: password))
        }
        if let match = firstYear(in: password) {
            findings.append(PatternFinding(kind: .year, matchedText: match))
        }
        if let match = firstDatePattern(in: password) {
            findings.append(PatternFinding(kind: .dateFormat, matchedText: match))
        }
        if let match = firstKeyboardSequence(in: password, commonRootIndex: commonRootIndex) {
            findings.append(PatternFinding(kind: .keyboardSequence, matchedText: match))
        }
        if let match = firstRepeatedCharacterRun(in: password) {
            findings.append(PatternFinding(kind: .repeatedCharacters, matchedText: match))
        }
        if let match = firstConsecutiveDigitRun(in: password) {
            findings.append(PatternFinding(kind: .consecutiveDigits, matchedText: match))
        }

        var seen = Set<String>()
        return findings.filter { seen.insert($0.id).inserted }
    }

    private static func firstYear(in password: String) -> String? {
        for run in numericRuns(in: password) where run.count >= 4 {
            let digits = Array(run)
            for start in 0...(digits.count - 4) {
                let candidate = String(digits[start..<(start + 4)])
                if let value = Int(candidate), (1900...2100).contains(value) {
                    return candidate
                }
            }
        }
        return nil
    }

    private static func firstDatePattern(in password: String) -> String? {
        if let separated = firstSeparatedDate(in: password) {
            return separated
        }

        for run in numericRuns(in: password) {
            let digits = Array(run)
            if digits.count >= 8 {
                for start in 0...(digits.count - 8) {
                    let candidate = String(digits[start..<(start + 8)])
                    if let year = Int(candidate.prefix(4)),
                       let month = Int(candidate.dropFirst(4).prefix(2)),
                       let day = Int(candidate.suffix(2)),
                       (1900...2100).contains(year),
                       isValidDate(year: year, month: month, day: day) {
                        return candidate
                    }
                }
            }

            if digits.count >= 4 {
                for start in 0...(digits.count - 4) {
                    let candidate = String(digits[start..<(start + 4)])
                    if let year = Int(candidate), (1900...2100).contains(year) {
                        continue
                    }
                    guard let first = Int(candidate.prefix(2)),
                          let second = Int(candidate.suffix(2)) else { continue }
                    if isValidMonthDay(month: first, day: second)
                        || isValidMonthDay(month: second, day: first) {
                        return candidate
                    }
                }
            }
        }
        return nil
    }

    private static func firstSeparatedDate(in password: String) -> String? {
        let patterns = [
            #"(?<!\d)(\d{4})[-/](\d{1,2})[-/](\d{1,2})(?!\d)"#,
            #"(?<!\d)(\d{1,2})[-/](\d{1,2})(?!\d)"#,
        ]

        for pattern in patterns {
            guard let expression = try? NSRegularExpression(pattern: pattern) else { continue }
            let fullRange = NSRange(password.startIndex..<password.endIndex, in: password)
            for match in expression.matches(in: password, range: fullRange) {
                guard let swiftRange = Range(match.range, in: password),
                      let firstRange = Range(match.range(at: 1), in: password),
                      let secondRange = Range(match.range(at: 2), in: password),
                      let first = Int(password[firstRange]),
                      let second = Int(password[secondRange]) else { continue }

                if match.numberOfRanges == 4,
                   let thirdRange = Range(match.range(at: 3), in: password),
                   let third = Int(password[thirdRange]),
                   (1900...2100).contains(first),
                   isValidDate(year: first, month: second, day: third) {
                    return String(password[swiftRange])
                }
                if match.numberOfRanges == 3 {
                    // Do not reinterpret the MM/DD tail of an invalid YYYY/MM/DD value
                    // as an independent short date. An invalid full date produces no date match.
                    let prefix = password[..<swiftRange.lowerBound]
                    let isTailOfFullDate: Bool = {
                        guard prefix.count >= 5 else { return false }
                        let tail = prefix.suffix(5)
                        guard tail.last == "/" || tail.last == "-" else { return false }
                        return tail.dropLast().allSatisfy { $0.isNumber }
                    }()
                    if !isTailOfFullDate,
                       (isValidMonthDay(month: first, day: second)
                        || isValidMonthDay(month: second, day: first)) {
                        return String(password[swiftRange])
                    }
                }
            }
        }
        return nil
    }

    private static func firstKeyboardSequence(
        in password: String,
        commonRootIndex: CommonRootIndex?
    ) -> String? {
        let lowercased = password.lowercased()
        let builtIn = builtInKeyboardSequences
            .sorted { $0.count > $1.count }
            .first { lowercased.contains($0) }
        let indexed = commonRootIndex?.keyboardMatch(in: lowercased)
        switch (builtIn, indexed) {
        case let (left?, right?): return left.count >= right.count ? left : right
        case let (left?, nil): return left
        case let (nil, right?): return right
        case (nil, nil): return nil
        }
    }

    private static func firstRepeatedCharacterRun(in password: String) -> String? {
        let characters = Array(password)
        guard characters.count >= 3 else { return nil }

        var index = 0
        while index < characters.count {
            var end = index + 1
            while end < characters.count,
                  characters[end].lowercased() == characters[index].lowercased() {
                end += 1
            }
            if end - index >= 3 {
                return String(characters[index..<end])
            }
            index = end
        }
        return nil
    }

    private static func firstConsecutiveDigitRun(in password: String) -> String? {
        for run in numericRuns(in: password) where run.count >= 3 {
            let digits = run.compactMap(\.wholeNumberValue)
            var start = 0
            while start <= digits.count - 3 {
                let direction = digits[start + 1] - digits[start]
                guard direction == 1 || direction == -1 else {
                    start += 1
                    continue
                }

                var end = start + 2
                while end < digits.count,
                      digits[end] - digits[end - 1] == direction {
                    end += 1
                }
                if end - start >= 3 {
                    return digits[start..<end].map(String.init).joined()
                }
                start += 1
            }
        }
        return nil
    }

    private static func numericRuns(in password: String) -> [String] {
        var runs: [String] = []
        var current = ""
        for character in password {
            if character.wholeNumberValue != nil {
                current.append(character)
            } else if !current.isEmpty {
                runs.append(current)
                current = ""
            }
        }
        if !current.isEmpty { runs.append(current) }
        return runs
    }

    private static func isValidMonthDay(month: Int, day: Int) -> Bool {
        guard (1...12).contains(month) else { return false }
        let daysPerMonth = [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        return (1...daysPerMonth[month - 1]).contains(day)
    }

    private static func isValidDate(year: Int, month: Int, day: Int) -> Bool {
        guard isValidMonthDay(month: month, day: day) else { return false }
        if month == 2, day == 29 {
            return year.isMultiple(of: 400)
                || (year.isMultiple(of: 4) && !year.isMultiple(of: 100))
        }
        return true
    }
}
