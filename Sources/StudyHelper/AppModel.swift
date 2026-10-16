import AppKit
import CoreGraphics
import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var menuBarText = "학습"
    @Published private(set) var status = "대기"
    @Published private(set) var ocrPreview = ""
    @Published private(set) var region: CaptureRegion?

    private let regionSelector = RegionSelector()
    private var loopTask: Task<Void, Never>?
    private var analysisTask: Task<Void, Never>?
    /// 마지막으로 Claude에 보낸(또는 분석 중인) 문제의 정규화된 줄 목록
    private var lastAnalyzedLines: [String] = []
    /// Claude 호출이 실패하면 이 시각 이후에 같은 문제를 다시 시도한다
    private var retryAt: Date?

    private static let interval: Duration = .seconds(5)
    private static let retryDelay: TimeInterval = 30
    private static let minQuestionLength = 8

    init() {
        region = CaptureRegion.load()
    }

    var regionDescription: String {
        guard let r = region else { return "영역: 주 화면 전체" }
        return "영역: \(Int(r.rect.width))×\(Int(r.rect.height)) @ (\(Int(r.rect.minX)), \(Int(r.rect.minY)))"
    }

    func toggle() {
        isRunning ? stop() : start()
    }

    func start() {
        guard !isRunning else { return }
        guard CGPreflightScreenCaptureAccess() else {
            CGRequestScreenCaptureAccess()
            status = "화면 기록 권한 필요 (허용 후 앱 재시작)"
            menuBarText = "권한"
            return
        }
        isRunning = true
        lastAnalyzedLines = []
        retryAt = nil
        menuBarText = "…"
        status = "실행 중"
        loopTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tick()
                try? await Task.sleep(for: Self.interval)
            }
        }
    }

    func stop() {
        loopTask?.cancel()
        loopTask = nil
        analysisTask?.cancel()
        analysisTask = nil
        isRunning = false
        status = "중지됨"
        menuBarText = "학습"
    }

    func selectRegion() {
        Task { [weak self] in
            // 메뉴가 닫힌 뒤 오버레이를 띄운다
            try? await Task.sleep(for: .milliseconds(200))
            self?.regionSelector.begin { region in
                guard let self, let region else { return }
                self.region = region
                region.save()
                self.lastAnalyzedLines = []
            }
        }
    }

    func resetRegion() {
        region = nil
        CaptureRegion.clear()
        lastAnalyzedLines = []
    }

    func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    private func tick() async {
        do {
            let image = try await ScreenCapturer.capture(region: effectiveRegion())
            let text = try await TextRecognizer.recognize(image)
            guard isRunning, !Task.isCancelled else { return }

            ocrPreview = String(text.replacingOccurrences(of: "\n", with: " ").prefix(40))

            let lines = TextUtil.lines(text)
            guard lines.joined().count >= Self.minQuestionLength else {
                if analysisTask == nil { status = "문제 텍스트 없음" }
                return
            }
            if let retryAt, analysisTask == nil, Date() >= retryAt {
                lastAnalyzedLines = []
            }
            guard TextUtil.isNewQuestion(current: lines, previous: lastAnalyzedLines) else {
                if analysisTask == nil, retryAt == nil { status = "변화 없음" }
                return
            }
            // 분석 중에 문제가 바뀌면 이전 분석을 버리고 즉시 새 문제를 분석한다
            analysisTask?.cancel()
            analysisTask = nil
            analyze(text: text, lines: lines)
        } catch {
            guard isRunning else { return }
            status = "오류: \(error.localizedDescription)"
        }
    }

    /// 전체 화면 모드에서는 메뉴 막대(시계, 이 앱의 답 표시)를 빼고 캡처한다
    private func effectiveRegion() -> CaptureRegion? {
        if let region { return region }
        let mainID = CGMainDisplayID()
        guard let screen = NSScreen.screens.first(where: {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == mainID
        }) else { return nil }
        let menuBar = max(0, screen.frame.maxY - screen.visibleFrame.maxY)
        return CaptureRegion(displayID: mainID,
                             rect: CGRect(x: 0, y: menuBar, width: screen.frame.width, height: screen.frame.height - menuBar))
    }

    private func analyze(text: String, lines: [String]) {
        lastAnalyzedLines = lines
        retryAt = nil
        menuBarText = "…"
        status = "Claude 분석 중…"
        analysisTask = Task { [weak self] in
            var answer = "?"
            var errorMessage: String?
            do {
                let output = try await ClaudeRunner.ask(prompt: Prompt.make(ocrText: text))
                answer = AnswerParser.parse(output)
            } catch {
                errorMessage = error.localizedDescription
            }
            guard !Task.isCancelled, let self else { return }
            self.analysisTask = nil
            guard self.isRunning else { return }
            if let errorMessage {
                // "?"(판단 불가)와 구분되도록 실행 오류는 ⚠︎로 표시하고 잠시 뒤 재시도
                self.menuBarText = "⚠︎"
                self.status = "Claude 오류: \(errorMessage)"
                self.retryAt = Date().addingTimeInterval(Self.retryDelay)
            } else {
                self.menuBarText = answer
                self.status = "분석 완료: \(answer)"
            }
        }
    }
}
