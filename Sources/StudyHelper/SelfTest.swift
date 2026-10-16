import Foundation
import ImageIO

/// `--ocr-test <이미지>`: GUI 없이 OCR과 답 파싱 경로를 검증한다.
enum SelfTest {
    static func runOCR(path: String) -> Never {
        let url = URL(fileURLWithPath: path) as CFURL
        guard let source = CGImageSourceCreateWithURL(url, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            FileHandle.standardError.write(Data("이미지 로드 실패: \(path)\n".utf8))
            exit(1)
        }
        do {
            let text = try TextRecognizer.recognizeSync(image)
            print(text)
            exit(text.isEmpty ? 1 : 0)
        } catch {
            FileHandle.standardError.write(Data("OCR 실패: \(error)\n".utf8))
            exit(1)
        }
    }
}
