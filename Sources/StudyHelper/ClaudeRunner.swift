import Foundation

enum ClaudeError: LocalizedError {
    case notFound
    case failed(Int32, String)
    case killed

    var errorDescription: String? {
        switch self {
        case .notFound: return "claude CLI를 찾을 수 없음"
        case .failed(let code, let message): return "claude 종료 코드 \(code): \(message.prefix(150))"
        case .killed: return "claude 응답 시간 초과/중단"
        }
    }
}

/// `claude -p`를 실행한다. API 키 없이 기존 Claude Code 로그인 세션을 사용.
enum ClaudeRunner {
    private struct Resolved {
        let executable: String
        let path: String
    }

    private static let answerTimeout: TimeInterval = 120
    private static let resolved: Resolved? = resolve()

    static func ask(prompt: String) async throws -> String {
        guard let resolved else { throw ClaudeError.notFound }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: resolved.executable)
        // 시스템 프롬프트를 답 전용으로 교체하고 도구를 꺼서 한 번에 답만 받는다
        process.arguments = ["-p", prompt, "--system-prompt", Prompt.system, "--tools", ""]
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = resolved.path
        // API 키가 환경에 있으면 그쪽이 우선되므로 제거 → 로그인 세션 사용
        environment.removeValue(forKey: "ANTHROPIC_API_KEY")
        process.environment = environment
        process.currentDirectoryURL = FileManager.default.temporaryDirectory
        process.standardInput = FileHandle.nullDevice

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    continuation.resume(with: Result { try runToEnd(process, timeout: answerTimeout) })
                }
            }
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
    }

    private final class DataBox {
        var data = Data()
    }

    /// 동기 실행. stdout/stderr를 동시에 읽어 파이프가 가득 차 멈추는 일을 막는다.
    private static func runToEnd(_ process: Process, timeout: TimeInterval) throws -> String {
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()

        let killer = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)

        let errBox = DataBox()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            errBox.data = stderr.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        process.waitUntilExit()
        killer.cancel()

        if process.terminationReason == .uncaughtSignal { throw ClaudeError.killed }
        let out = String(decoding: outData, as: UTF8.self)
        guard process.terminationStatus == 0 else {
            let err = String(decoding: errBox.data, as: UTF8.self)
            throw ClaudeError.failed(process.terminationStatus, err.isEmpty ? out : err)
        }
        return out
    }

    /// GUI 앱은 셸 PATH를 물려받지 않으므로 로그인 셸에서 claude 위치와 PATH를 알아낸다.
    private static func resolve() -> Resolved? {
        var pathParts: [String] = []
        var executable: String?

        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let probe = Process()
        probe.executableURL = URL(fileURLWithPath: shell)
        probe.arguments = ["-l", "-i", "-c", "echo __PATH__$PATH; echo __CLAUDE__$(command -v claude)"]
        probe.standardInput = FileHandle.nullDevice
        if let output = try? runToEnd(probe, timeout: 10) {
            for line in output.split(whereSeparator: \.isNewline) {
                if line.hasPrefix("__PATH__") {
                    pathParts = line.dropFirst("__PATH__".count).split(separator: ":").map(String.init)
                } else if line.hasPrefix("__CLAUDE__") {
                    let candidate = line.dropFirst("__CLAUDE__".count).trimmingCharacters(in: .whitespaces)
                    // alias 출력 등은 무시하고 실제 경로만 사용
                    if candidate.hasPrefix("/") { executable = candidate }
                }
            }
        }

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "\(home)/.local/bin/claude",
            "\(home)/.claude/local/claude",
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            "\(home)/.npm-global/bin/claude",
            "\(home)/.bun/bin/claude",
        ]
        if executable == nil || !FileManager.default.isExecutableFile(atPath: executable!) {
            executable = candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
        }
        guard let exe = executable else { return nil }

        // npm 설치본은 node가 PATH에 있어야 실행된다
        let extra = [(exe as NSString).deletingLastPathComponent,
                     "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        for p in extra where !pathParts.contains(p) { pathParts.append(p) }
        return Resolved(executable: exe, path: pathParts.joined(separator: ":"))
    }
}
