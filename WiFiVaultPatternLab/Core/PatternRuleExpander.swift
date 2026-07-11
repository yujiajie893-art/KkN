import Foundation

enum PatternRuleExpander {
    static let compactDateTokens: [String] = {
        let daysPerMonth = [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        var values: [String] = []
        values.reserveCapacity(366)
        for month in 1...12 {
            for day in 1...daysPerMonth[month - 1] {
                values.append(String(format: "%02d%02d", month, day))
            }
        }
        return values
    }()

    @discardableResult
    static func forEachCandidate(
        root rawRoot: String,
        configuration rawConfiguration: GeneratorConfiguration,
        keyboardPatterns: [String],
        _ body: (String) throws -> Bool
    ) throws -> Bool {
        let configuration = rawConfiguration.normalized()
        let root = rawRoot.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !root.isEmpty, root.count <= 128 else { return true }

        let rootForms = uniqueRootForms(root, includeCaseVariants: configuration.includeCaseVariants)
        let separators = configuration.includeSpecialCharacterVariants
            ? ["", "_", "-", "!", "@", "#"]
            : [""]

        func emit(_ value: String) throws -> Bool {
            guard !value.isEmpty, value.count <= 256 else { return true }
            return try body(value)
        }

        if configuration.includeBaseRoot {
            for form in rootForms {
                if (try emit(form)) == false { return false }
            }
        }

        if configuration.includeSpecialCharacterVariants {
            for form in rootForms {
                for symbol in ["!", "@", "#"] {
                    if (try emit(form + symbol)) == false { return false }
                }
            }
        }

        func emitTokens<S: Sequence>(_ tokens: S) throws -> Bool where S.Element == String {
            for token in tokens {
                for form in rootForms {
                    for separator in separators {
                        if (try emit(form + separator + token)) == false { return false }
                    }
                }
            }
            return true
        }

        if configuration.includeYears {
            let years = (configuration.startYear...configuration.endYear).map(String.init)
            if (try emitTokens(years)) == false { return false }
        }

        if configuration.includeDates {
            if (try emitTokens(compactDateTokens)) == false { return false }
        }

        if configuration.includeKeyboardCombinations {
            let usablePatterns = keyboardPatterns.filter { pattern in
                !pattern.isEmpty && !pattern.allSatisfy(\.isNumber)
            }
            if (try emitTokens(usablePatterns)) == false { return false }
        }

        if configuration.includeNumericSuffix {
            for number in configuration.numericStart...configuration.numericEnd {
                if configuration.includeYears,
                   (configuration.startYear...configuration.endYear).contains(number) {
                    continue
                }
                let token = String(number)
                for form in rootForms {
                    for separator in separators {
                        if (try emit(form + separator + token)) == false { return false }
                    }
                }
            }
        }

        return true
    }

    private static func uniqueRootForms(_ root: String, includeCaseVariants: Bool) -> [String] {
        var values = [root]
        if includeCaseVariants {
            values.append(root.lowercased())
            if let first = root.first {
                values.append(String(first).uppercased() + String(root.dropFirst()))
            }
            values.append(root.uppercased())
        }

        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }
}
