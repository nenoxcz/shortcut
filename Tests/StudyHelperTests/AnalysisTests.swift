@testable import StudyHelper
import XCTest

final class ChangeDetectionTests: XCTestCase {
    /// 전체 화면 캡처처럼 고정 UI 텍스트가 대부분인 화면
    private let chrome = (1...40).map { "브라우저 탭 메뉴 사이드바 항목 \($0)번 링크 텍스트" }.joined(separator: "\n")

    private func screen(_ question: String) -> [String] {
        TextUtil.lines(chrome + "\n" + question)
    }

    func testSameScreenIsNotNew() {
        let q = "1. 다음 중 대한민국의 수도는?\n① 부산 ② 서울 ③ 대구 ④ 광주 ⑤ 인천"
        XCTAssertFalse(TextUtil.isNewQuestion(current: screen(q), previous: screen(q)))
    }

    func testNextQuestionAmidStaticUIIsNew() {
        let q1 = "1. 다음 중 대한민국의 수도는?\n① 부산 ② 서울 ③ 대구 ④ 광주 ⑤ 인천"
        let q2 = "2. 훈민정음을 창제한 왕은?\n① 태조 ② 태종 ③ 세종 ④ 세조 ⑤ 성종"
        XCTAssertTrue(TextUtil.isNewQuestion(current: screen(q2), previous: screen(q1)))
    }

    func testFirstQuestionIsNew() {
        XCTAssertTrue(TextUtil.isNewQuestion(current: screen("1. 문제 텍스트입니다"), previous: []))
    }

    func testTimerTickIsNotNew() {
        let q = "1. 다음 중 대한민국의 수도는?\n① 부산 ② 서울 ③ 대구 ④ 광주 ⑤ 인천"
        let before = screen(q + "\n남은 시간 12:34")
        let after = screen(q + "\n남은 시간 12:29")
        XCTAssertFalse(TextUtil.isNewQuestion(current: after, previous: before))
    }

    func testMathQuestionWithOnlyDigitChangesIsNew() {
        let q1 = "3 + 5 = ?\n① 6 ② 7 ③ 8 ④ 9 ⑤ 10"
        let q2 = "4 + 7 = ?\n① 9 ② 10 ③ 11 ④ 12 ⑤ 13"
        XCTAssertTrue(TextUtil.isNewQuestion(current: screen(q2), previous: screen(q1)))
    }
}

final class AnswerParserTests: XCTestCase {
    func testParse() {
        XCTAssertEqual(AnswerParser.parse("정답: ③"), "③")
        XCTAssertEqual(AnswerParser.parse("정답: 3번"), "③")
        XCTAssertEqual(AnswerParser.parse("정답은 ②입니다."), "②")
        XCTAssertEqual(AnswerParser.parse("**정답: (4)**"), "④")
        XCTAssertEqual(AnswerParser.parse("정답: ?"), "?")
        XCTAssertEqual(AnswerParser.parse(""), "?")
        XCTAssertEqual(AnswerParser.parse("정답: 세종대왕"), "세종대왕")
    }
}
