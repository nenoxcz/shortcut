import Foundation

enum Prompt {
    /// Claude Code 기본(코딩 에이전트) 시스템 프롬프트를 대체한다
    static let system = """
        너는 학습 보조 앱의 정답 표시기다. 입력은 사용자가 공부 중인 화면에서 OCR로 읽은 문제와 선택지이며 OCR 오류가 있을 수 있다.
        출력은 답 하나뿐이어야 한다:
        - 객관식: 정답 기호 하나만 (①, ②, ③, ④, ⑤ 중 하나)
        - 단답형: 정답만 15자 이내
        - 문제가 없거나 판단할 수 없으면: ?
        설명, 풀이, 문장, 인사, 마크다운, 따옴표를 절대 붙이지 마라.
        """

    /// 머리말을 붙여 OCR 텍스트가 "-"로 시작해도 CLI 옵션으로 해석되지 않게 한다
    static func make(ocrText: String) -> String {
        "[OCR 텍스트]\n" + ocrText
    }
}

enum AnswerParser {
    static let circled: [Character] = ["①", "②", "③", "④", "⑤"]
    private static let trimSet = CharacterSet.whitespaces.union(CharacterSet(charactersIn: ":：*`\"'.,"))
    private static let refusalMarkers = ["죄송", "할 수 없", "드릴 수 없", "어렵습니다", "sorry", "can't", "cannot", "unable"]
    private static let maxShortAnswer = 20

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
        // 답 대신 거절·설명 문장이 오면 메뉴 막대에 문장을 띄우지 않고 ?로 표시
        let lowered = answer.lowercased()
        if refusalMarkers.contains(where: { lowered.contains($0) }) { return "?" }

        let found = answer.filter { circled.contains($0) }
        if !found.isEmpty { return String(found) }

        let bare = answer.filter { !"()（）번.".contains($0) && !$0.isWhitespace }
        if bare.count == 1, let n = Int(bare), (1...5).contains(n) {
            return String(circled[n - 1])
        }
        return answer.count > maxShortAnswer ? "?" : answer
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
