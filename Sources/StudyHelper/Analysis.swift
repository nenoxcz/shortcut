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

    /// OCR 결과를 정규화된 줄 목록으로 변환 (빈 줄 제외)
    static func lines(_ text: String) -> [String] {
        text.split(whereSeparator: \.isNewline).map { normalize(String($0)) }.filter { !$0.isEmpty }
    }

    /// 이전에 분석한 화면과 비교해 새 문제인지 판단한다.
    /// 전체 유사도가 아니라 줄 단위로 비교하므로 화면 대부분이 고정된 UI여도 문제 교체를 잡아낸다.
    /// 숫자만 바뀐 줄이 하나뿐이면(타이머·시계) 무시하고, 여러 줄이면(계산 문제) 새 문제로 본다.
    static func isNewQuestion(current: [String], previous: [String]) -> Bool {
        let old = Set(previous)
        let oldSkeletons = Set(previous.map(skeleton))
        var newTextChars = 0
        var digitOnlyLines = 0
        for line in current where !old.contains(line) {
            if oldSkeletons.contains(skeleton(line)) {
                digitOnlyLines += 1
            } else {
                newTextChars += line.count
            }
        }
        return newTextChars >= 4 || digitOnlyLines >= 2
    }

    private static func skeleton(_ line: String) -> String {
        line.filter { !$0.isNumber }
    }
}
