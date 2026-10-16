// CI용: 한국어 객관식 문제 이미지를 생성한다. 사용법: swift scripts/make_test_image.swift out.png
import AppKit

let text = "1. 다음 중 대한민국의 수도는 어디인가?\n① 부산   ② 서울   ③ 대구   ④ 광주   ⑤ 인천"
let size = NSSize(width: 1400, height: 320)
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSColor.white.setFill()
NSRect(origin: .zero, size: size).fill()
(text as NSString).draw(in: NSRect(x: 40, y: 40, width: 1320, height: 240),
                        withAttributes: [.font: NSFont.systemFont(ofSize: 40), .foregroundColor: NSColor.black])
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
