import Foundation

enum Prompt {
    static func make(ocrText: String) -> String {
        """
        아래는 화면에서 OCR로 추출한 한국어 문제와 선택지입니다. OCR 오류가 있을 수 있습니다.
        규칙:
        - 객관식이면 정답 번호 하나를 ①, ②, ③, ④, ⑤ 중에서 고르세요.
        - 단답형이면 정답을 15자 이내의 짧은 텍스트로 쓰세요.
        - 문제가 아니거나 판단하기 어려우면 ? 로 답하세요.
        - 설명 없이 "정답: <답>" 한 줄만 출력하세요.

        [OCR 텍스트]
        \(ocrText)
        """
    }
}

enum AnswerParser {
    static let circled: [Character] = ["①", "②", "③", "④", "⑤"]
    private static let trimSet = CharacterSet.whitespaces.union(CharacterSet(charactersIn: ":：*`\"'.,"))

    /// claude 출력 → 메뉴 막대 표시 문자열 (①~⑤, ?, 또는 짧은 텍스트)
    static func parse(_ output: String) -> String {
        let lines = output.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        var answer = lines.last(where: { $0.contains("정답") }) ?? lines.last ?? ""
        if let range = answer.range(of: "정답") {
            answer = String(answer[range.upperBound...])
        }
        answer = answer.trimmingCharacters(in: trimSet)
        if answer.isEmpty || answer.hasPrefix("?") { return "?" }

        let found = answer.filter { circled.contains($0) }
        if !found.isEmpty { return String(found) }

        let bare = answer.filter { !"()（）번.".contains($0) && !$0.isWhitespace }
        if bare.count == 1, let n = Int(bare), (1...5).contains(n) {
            return String(circled[n - 1])
        }
        return String(answer.prefix(15))
    }
}

enum TextUtil {
    /// 공백·문장부호를 제거해 OCR 잡음에 덜 민감하게 만든다.
    static func normalize(_ text: String) -> String {
        var result = ""
        result.unicodeScalars.append(contentsOf: text.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
        return result
    }

    /// 문자 바이그램 Dice 계수 (0...1)
    static func similarity(_ a: String, _ b: String) -> Double {
        if a == b { return 1 }
        let x = Array(a), y = Array(b)
        guard x.count > 1, y.count > 1 else { return 0 }
        var counts: [String: Int] = [:]
        for i in 0..<(x.count - 1) {
            counts[String(x[i...i + 1]), default: 0] += 1
        }
        var shared = 0
        for i in 0..<(y.count - 1) {
            let key = String(y[i...i + 1])
            if let c = counts[key], c > 0 {
                shared += 1
                counts[key] = c - 1
            }
        }
        return 2.0 * Double(shared) / Double(x.count - 1 + y.count - 1)
    }
}
