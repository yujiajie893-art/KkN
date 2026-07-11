import Foundation

enum RiskScoringEngine {
    static func analyze(
        _ password: String,
        commonRootIndex: CommonRootIndex? = nil
    ) -> PasswordAnalysis {
        guard !password.isEmpty else { return .empty }

        let findings = PasswordStructureAnalyzer.findings(
            in: password,
            commonRootIndex: commonRootIndex
        )
        let scalars = password.unicodeScalars
        let hasLowercase = scalars.contains { CharacterSet.lowercaseLetters.contains($0) }
        let hasUppercase = scalars.contains { CharacterSet.uppercaseLetters.contains($0) }
        let hasDigits = scalars.contains { CharacterSet.decimalDigits.contains($0) }
        let hasSymbols = scalars.contains {
            !CharacterSet.alphanumerics.contains($0)
                && !CharacterSet.whitespacesAndNewlines.contains($0)
        }
        let isDigitsOnly = !password.isEmpty && scalars.allSatisfy {
            CharacterSet.decimalDigits.contains($0)
        }

        var characterPool = 0
        if hasLowercase { characterPool += 26 }
        if hasUppercase { characterPool += 26 }
        if hasDigits { characterPool += 10 }
        if hasSymbols { characterPool += 33 }
        let entropy = characterPool > 0
            ? Double(password.count) * log2(Double(characterPool))
            : 0

        var score = 0
        var recommendations: [String] = []

        switch password.count {
        case 0...7:
            recommendations.append("长度至少提升到 12 位；重要账户更建议 16 位以上。")
        case 8...9:
            score += 18
            recommendations.append("当前只达到常见最低长度，建议继续加长。")
        case 10...11:
            score += 30
            recommendations.append("再增加 2–6 个无规律字符会更稳。")
        case 12...15:
            score += 45
        default:
            score += 58
        }

        let classCount = [hasLowercase, hasUppercase, hasDigits, hasSymbols]
            .filter { $0 }
            .count
        score += classCount * 8
        if classCount <= 1 {
            score -= 10
            recommendations.append("不要只用单一字符类型。")
        } else if classCount == 2 {
            recommendations.append("可加入第三种字符类型，但优先保证长度与随机性。")
        }

        if isDigitsOnly {
            score -= password.count <= 10 ? 25 : 12
            recommendations.append("避免纯数字组合。")
        }

        let findingKinds = Set(findings.map(\.kind))
        for kind in findingKinds {
            switch kind {
            case .commonRoot:
                score -= 22
                recommendations.append("替换公开词根，不要只在词根后追加数字。")
            case .year:
                score -= 18
                recommendations.append("移除出生年、纪念年等四位年份。")
            case .dateFormat:
                score -= 18
                recommendations.append("避免生日或纪念日格式。")
            case .keyboardSequence:
                score -= 28
                recommendations.append("打散 qwerty、asdf、1qaz 等相邻键顺序。")
            case .repeatedCharacters:
                score -= 30
                recommendations.append("删除连续重复字符。")
            case .consecutiveDigits:
                score -= 22
                recommendations.append("删除 123、987 等连续数字。")
            }
        }

        if entropy >= 75 {
            score += 12
        } else if entropy < 40 {
            recommendations.append("当前估算搜索空间偏小，优先增加随机长度。")
        }

        score = min(max(score, 0), 100)
        let riskLevel: PasswordRiskLevel
        switch score {
        case 0..<35: riskLevel = .critical
        case 35..<55: riskLevel = .high
        case 55..<75: riskLevel = .medium
        default: riskLevel = .low
        }

        if recommendations.isEmpty {
            recommendations.append("未发现明显结构弱点；仍应确保该密码唯一且未在别处复用。")
        }

        var seenRecommendations = Set<String>()
        return PasswordAnalysis(
            password: password,
            findings: findings,
            strengthScore: score,
            estimatedEntropyBits: entropy,
            riskLevel: riskLevel,
            recommendations: recommendations.filter {
                seenRecommendations.insert($0).inserted
            }
        )
    }
}
