import Foundation

struct GeneratorConfiguration: Equatable, Sendable {
    var includeBaseRoot = false

    var includeYears = true
    var startYear = 1980
    var endYear = 2030

    var includeNumericSuffix = true
    var numericStart = 1
    var numericEnd = 9_999

    var includeDates = true
    var includeKeyboardCombinations = false
    var includeCaseVariants = true
    var includeSpecialCharacterVariants = true

    var maximumResults = 100_000

    func normalized() -> GeneratorConfiguration {
        var copy = self

        if copy.startYear > copy.endYear {
            swap(&copy.startYear, &copy.endYear)
        }
        copy.startYear = min(max(copy.startYear, 1900), 2100)
        copy.endYear = min(max(copy.endYear, 1900), 2100)

        if copy.numericStart > copy.numericEnd {
            swap(&copy.numericStart, &copy.numericEnd)
        }
        copy.numericStart = min(max(copy.numericStart, 0), 9_999)
        copy.numericEnd = min(max(copy.numericEnd, 0), 9_999)
        copy.maximumResults = min(max(copy.maximumResults, 1), 1_000_000)
        return copy
    }

    var hasEnabledRule: Bool {
        includeBaseRoot
            || includeYears
            || includeNumericSuffix
            || includeDates
            || includeKeyboardCombinations
            || includeSpecialCharacterVariants
    }
}

enum GenerationState: Equatable, Sendable {
    case idle
    case running
    case completed
    case cancelled
    case failed(String)

    var isRunning: Bool {
        self == .running
    }
}

struct GenerationProgress: Equatable, Sendable {
    var generatedCount = 0
    var maximumCount = 1
    var bytesWritten: Int64 = 0
    var elapsedSeconds: TimeInterval = 0

    var fractionCompleted: Double {
        guard maximumCount > 0 else { return 0 }
        return min(max(Double(generatedCount) / Double(maximumCount), 0), 1)
    }

    var ratePerSecond: Double {
        guard elapsedSeconds > 0 else { return 0 }
        return Double(generatedCount) / elapsedSeconds
    }
}

struct GenerationSummary: Equatable, Sendable {
    let fileURL: URL
    let generatedCount: Int
    let bytesWritten: Int64
    let duration: TimeInterval
    let wasTruncated: Bool
    let previewSamples: [String]
    let sourceIDs: [String]

    var ratePerSecond: Double {
        guard duration > 0 else { return 0 }
        return Double(generatedCount) / duration
    }
}

enum PatternFindingKind: String, CaseIterable, Sendable {
    case commonRoot
    case year
    case dateFormat
    case keyboardSequence
    case repeatedCharacters
    case consecutiveDigits

    var title: String {
        switch self {
        case .commonRoot: return "常见词根"
        case .year: return "年份"
        case .dateFormat: return "日期格式"
        case .keyboardSequence: return "键盘序列"
        case .repeatedCharacters: return "重复字符"
        case .consecutiveDigits: return "连续数字"
        }
    }

    var explanation: String {
        switch self {
        case .commonRoot: return "包含公开词典中的常见词根，结构可预测性较高。"
        case .year: return "包含四位年份，常被直接附加在词根后。"
        case .dateFormat: return "包含可识别的月日或年月日结构。"
        case .keyboardSequence: return "包含相邻键或常见键盘顺序。"
        case .repeatedCharacters: return "包含三个或更多连续重复字符。"
        case .consecutiveDigits: return "包含三个或更多升序或降序数字。"
        }
    }
}

struct PatternFinding: Identifiable, Equatable, Sendable {
    let kind: PatternFindingKind
    let matchedText: String
    let sourceName: String?

    init(kind: PatternFindingKind, matchedText: String, sourceName: String? = nil) {
        self.kind = kind
        self.matchedText = matchedText
        self.sourceName = sourceName
    }

    var id: String {
        "\(kind.rawValue):\(matchedText):\(sourceName ?? "")"
    }
}

enum PasswordRiskLevel: String, CaseIterable, Sendable {
    case critical
    case high
    case medium
    case low

    var title: String {
        switch self {
        case .critical: return "极高风险"
        case .high: return "高风险"
        case .medium: return "中等风险"
        case .low: return "较低风险"
        }
    }
}

struct PasswordAnalysis: Equatable, Sendable {
    let password: String
    let findings: [PatternFinding]
    let strengthScore: Int
    let estimatedEntropyBits: Double
    let riskLevel: PasswordRiskLevel
    let recommendations: [String]

    static let empty = PasswordAnalysis(
        password: "",
        findings: [],
        strengthScore: 0,
        estimatedEntropyBits: 0,
        riskLevel: .critical,
        recommendations: []
    )

    var isEmpty: Bool { password.isEmpty }
}
