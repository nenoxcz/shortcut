import CoreGraphics
import Foundation

/// 캡처 영역. rect는 해당 디스플레이 기준 좌상단 원점의 포인트 좌표.
struct CaptureRegion: Codable, Equatable {
    var displayID: CGDirectDisplayID
    var rect: CGRect

    private static let key = "captureRegion"

    static func load() -> CaptureRegion? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(CaptureRegion.self, from: data)
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
