import CoreGraphics
import Foundation
import ScreenCaptureKit

enum CaptureError: LocalizedError {
    case noDisplay
    case cropFailed

    var errorDescription: String? {
        switch self {
        case .noDisplay: return "캡처할 디스플레이 없음"
        case .cropFailed: return "선택 영역 자르기 실패 (영역을 다시 선택하세요)"
        }
    }
}

enum ScreenCapturer {
    static func capture(region: CaptureRegion?) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let targetID = region?.displayID ?? CGMainDisplayID()
        guard let display = content.displays.first(where: { $0.displayID == targetID }) ?? content.displays.first else {
            throw CaptureError.noDisplay
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        // Retina 해상도 그대로 캡처해야 OCR 정확도가 높다
        let pixelWidth = CGDisplayCopyDisplayMode(display.displayID)?.pixelWidth ?? display.width * 2
        let scale = max(1, CGFloat(pixelWidth) / CGFloat(display.width))
        config.width = Int(CGFloat(display.width) * scale)
        config.height = Int(CGFloat(display.height) * scale)
        config.showsCursor = false

        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        guard let region, region.displayID == display.displayID else { return image }

        let sx = CGFloat(image.width) / CGFloat(display.width)
        let sy = CGFloat(image.height) / CGFloat(display.height)
        let crop = CGRect(x: region.rect.minX * sx, y: region.rect.minY * sy,
                          width: region.rect.width * sx, height: region.rect.height * sy)
            .integral
            .intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard !crop.isNull, crop.width >= 1, crop.height >= 1, let cropped = image.cropping(to: crop) else {
            throw CaptureError.cropFailed
        }
        return cropped
    }
}
