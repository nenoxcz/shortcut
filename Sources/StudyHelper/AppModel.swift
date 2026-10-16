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
    /// 마지막으로 Claude에 보낸 문제(정규화된 텍스트)
    private var lastAnalyzedText = ""

    private static let interval: Duration = .seconds(5)
    /// 이 값 이상 비슷하면 같은 문제로 간주 (OCR 잡음 흡수)
    private static let sameThreshold = 0.93
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
        lastAnalyzedText = ""
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
                self.lastAnalyzedText = ""
            }
        }
    }

    func resetRegion() {
        region = nil
        CaptureRegion.clear()
        lastAnalyzedText = ""
    }

    func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    private func tick() async {
        do {
            let image = try await ScreenCapturer.capture(region: region)
            let text = try await TextRecognizer.recognize(image)
            guard isRunning, !Task.isCancelled else { return }

            ocrPreview = String(text.replacingOccurrences(of: "\n", with: " ").prefix(40))
            // 분석 중에는 새 호출을 하지 않음. 끝난 뒤 다음 주기에 변화 여부를 다시 판단.
            guard analysisTask == nil else { return }

            let normalized = TextUtil.normalize(text)
            guard normalized.count >= Self.minQuestionLength else {
                status = "문제 텍스트 없음"
                return
            }
            if !lastAnalyzedText.isEmpty,
               TextUtil.similarity(normalized, lastAnalyzedText) >= Self.sameThreshold {
                status = "변화 없음"
                return
            }
            analyze(text: text, normalized: normalized)
        } catch {
            guard isRunning else { return }
            status = "오류: \(error.localizedDescription)"
        }
    }

    private func analyze(text: String, normalized: String) {
        lastAnalyzedText = normalized
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
            self.menuBarText = answer
            self.status = errorMessage.map { "Claude 오류: \($0)" } ?? "분석 완료: \(answer)"
        }
    }
}
