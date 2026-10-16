import AppKit
import SwiftUI

@main
@MainActor
struct StudyHelperApp: App {
    @StateObject private var model = AppModel()

    init() {
        // CI/디버그용: StudyHelper --ocr-test <이미지> → OCR 결과 출력 후 종료
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--ocr-test"), i + 1 < args.count {
            SelfTest.runOCR(path: args[i + 1])
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: model)
        } label: {
            MenuLabel(model: model)
        }
        .menuBarExtraStyle(.menu)
    }
}

struct MenuLabel: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Text(model.menuBarText)
    }
}

struct MenuContent: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Text("상태: \(model.status)")
        if !model.ocrPreview.isEmpty {
            Text("인식: \(model.ocrPreview)")
        }
        Divider()
        Button(model.isRunning ? "중지" : "시작") { model.toggle() }
            .keyboardShortcut("s")
        Button("캡처 영역 선택…") { model.selectRegion() }
            .keyboardShortcut("r")
        Button("전체 화면으로 초기화") { model.resetRegion() }
            .disabled(model.region == nil)
        Text(model.regionDescription)
        Divider()
        Button("화면 기록 권한 설정 열기") { model.openScreenRecordingSettings() }
        Button("종료") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }
}
