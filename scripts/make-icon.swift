#!/usr/bin/env swift
// Sinh biểu tượng native macOS Sequoia (AppIcon.icns) cho BI Pro bằng CoreGraphics + iconutil.
// Không tải từ mạng, không dùng thư viện ngoài (Hiến pháp III & IV).
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

guard CommandLine.arguments.count >= 2 else {
    fputs("Usage: make-icon.swift <output-AppIcon.icns>\n", stderr)
    exit(2)
}

let outputICNS = URL(fileURLWithPath: CommandLine.arguments[1])
let parentDir = outputICNS.deletingLastPathComponent()
try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
let iconsetDir = parentDir.appendingPathComponent("AppIcon-\(UUID().uuidString).iconset", isDirectory: true)
try FileManager.default.createDirectory(at: iconsetDir, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: iconsetDir) }

func drawIcon(pixelSize: Int) -> CGImage {
    let s = CGFloat(pixelSize)
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(
        data: nil,
        width: pixelSize,
        height: pixelSize,
        bitsPerComponent: 8,
        bytesPerRow: pixelSize * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!

    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)
    ctx.clear(CGRect(x: 0, y: 0, width: s, height: s))

    // macOS app icon squircle margin (~9.7% each side)
    let inset = s * 0.097
    let box = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let corner = box.width * 0.225
    let squircle = CGPath(roundedRect: box, cornerWidth: corner, cornerHeight: corner, transform: nil)

    // Subtle drop shadow
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.015), blur: s * 0.03, color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.28))
    ctx.addPath(squircle)
    ctx.setFillColor(CGColor(red: 0.04, green: 0.52, blue: 1.0, alpha: 1))
    ctx.fillPath()
    ctx.restoreGState()

    // Gradient background (#0A84FF -> #5E5CE6)
    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.clip()
    let colors = [
        CGColor(red: 0.04, green: 0.52, blue: 1.0, alpha: 1),
        CGColor(red: 0.20, green: 0.43, blue: 0.96, alpha: 1),
        CGColor(red: 0.37, green: 0.36, blue: 0.90, alpha: 1),
    ] as CFArray
    let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0.0, 0.52, 1.0])!
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: box.minX, y: box.maxY),
        end: CGPoint(x: box.maxX, y: box.minY),
        options: []
    )

    // Soft glass highlight top-left
    let glowColors = [
        CGColor(red: 1, green: 1, blue: 1, alpha: 0.26),
        CGColor(red: 1, green: 1, blue: 1, alpha: 0.0),
    ] as CFArray
    let glow = CGGradient(colorsSpace: colorSpace, colors: glowColors, locations: [0, 1])!
    ctx.drawRadialGradient(
        glow,
        startCenter: CGPoint(x: box.minX + box.width * 0.28, y: box.maxY - box.height * 0.22),
        startRadius: 0,
        endCenter: CGPoint(x: box.minX + box.width * 0.28, y: box.maxY - box.height * 0.22),
        endRadius: box.width * 0.65,
        options: []
    )

    // 3 analytical bars (white translucent -> crisp white)
    let barY = box.minY + box.height * 0.20
    let barW = box.width * 0.165
    let barGap = box.width * 0.085
    let totalW = barW * 3 + barGap * 2
    let startX = box.midX - totalW / 2
    let heights: [CGFloat] = [0.30, 0.46, 0.62]
    let alphas: [CGFloat] = [0.72, 0.86, 0.98]

    for i in 0..<3 {
        let bx = startX + CGFloat(i) * (barW + barGap)
        let bh = box.height * heights[i]
        let rect = CGRect(x: bx, y: barY, width: barW, height: bh)
        let barPath = CGPath(roundedRect: rect, cornerWidth: barW * 0.26, cornerHeight: barW * 0.26, transform: nil)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.008), blur: s * 0.018, color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.18))
        ctx.addPath(barPath)
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: alphas[i]))
        ctx.fillPath()
        ctx.restoreGState()
    }

    // Accent sparkline / trend line above bars
    if pixelSize >= 32 {
        let p0 = CGPoint(x: startX + barW * 0.5, y: barY + box.height * 0.36)
        let p1 = CGPoint(x: startX + barW * 1.5 + barGap, y: barY + box.height * 0.54)
        let p2 = CGPoint(x: startX + barW * 2.5 + barGap * 2, y: barY + box.height * 0.72)

        ctx.saveGState()
        ctx.setStrokeColor(CGColor(red: 1.0, green: 0.84, blue: 0.22, alpha: 0.95))
        ctx.setLineWidth(max(1.5, box.width * 0.042))
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.move(to: p0)
        ctx.addLine(to: p1)
        ctx.addLine(to: p2)
        ctx.strokePath()

        let dotR = max(2, box.width * 0.045)
        for p in [p0, p1, p2] {
            ctx.setFillColor(CGColor(red: 1.0, green: 0.88, blue: 0.35, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: p.x - dotR, y: p.y - dotR, width: dotR * 2, height: dotR * 2))
        }
        ctx.restoreGState()
    }

    // Subtle inner rim highlight
    ctx.addPath(squircle)
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.22))
    ctx.setLineWidth(max(1, s * 0.006))
    ctx.strokePath()
    ctx.restoreGState()

    return ctx.makeImage()!
}

let specs: [(name: String, size: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

for spec in specs {
    let img = drawIcon(pixelSize: spec.size)
    let destURL = iconsetDir.appendingPathComponent(spec.name)
    guard let dest = CGImageDestinationCreateWithURL(destURL as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        fputs("Failed to create PNG destination for \(spec.name)\n", stderr)
        exit(1)
    }
    CGImageDestinationAddImage(dest, img, nil)
    guard CGImageDestinationFinalize(dest) else {
        fputs("Failed to write \(spec.name)\n", stderr)
        exit(1)
    }
}

// Ghi .icns trực tiếp bằng iconutil; nếu iconutil bị giới hạn môi trường, tự đóng gói container 'icns' chuẩn Apple (PNG chunks icp4..ic14).
let proc = Process()
proc.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
proc.arguments = ["-c", "icns", iconsetDir.path, "-o", outputICNS.path]
try? proc.run()
proc.waitUntilExit()

if proc.terminationStatus != 0 || !FileManager.default.fileExists(atPath: outputICNS.path) {
    // Chuẩn Apple ICNS với payload PNG (macOS 10.7+..15+): mỗi mục gồm 4-byte OSType + 4-byte UInt32 big-endian length (8 + png.count) + png bytes
    let icnsChunks: [(tag: String, file: String)] = [
        ("icp4", "icon_16x16.png"),
        ("ic11", "icon_16x16@2x.png"),
        ("icp5", "icon_32x32.png"),
        ("ic12", "icon_32x32@2x.png"),
        ("ic07", "icon_128x128.png"),
        ("ic13", "icon_128x128@2x.png"),
        ("ic08", "icon_256x256.png"),
        ("ic14", "icon_256x256@2x.png"),
        ("ic09", "icon_512x512.png"),
        ("ic10", "icon_512x512@2x.png"),
    ]
    var body = Data()
    for item in icnsChunks {
        let png = try Data(contentsOf: iconsetDir.appendingPathComponent(item.file))
        var len = UInt32(8 + png.count).bigEndian
        body.append(contentsOf: item.tag.utf8)
        body.append(Data(bytes: &len, count: 4))
        body.append(png)
    }
    var out = Data("icns".utf8)
    var total = UInt32(8 + body.count).bigEndian
    out.append(Data(bytes: &total, count: 4))
    out.append(body)
    try out.write(to: outputICNS, options: .atomic)
}
print("Generated \(outputICNS.path)")
