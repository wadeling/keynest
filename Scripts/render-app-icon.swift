#!/usr/bin/env swift

import AppKit
import CoreGraphics
import Foundation

let outputPath = CommandLine.arguments.dropFirst().first ?? "Assets/AppIcon.iconset"
let outputURL = URL(fileURLWithPath: outputPath)
let fileManager = FileManager.default

try? fileManager.removeItem(at: outputURL)
try fileManager.createDirectory(at: outputURL, withIntermediateDirectories: true)

struct IconSize {
    let filename: String
    let pixels: Int
}

let sizes = [
    IconSize(filename: "icon_16x16.png", pixels: 16),
    IconSize(filename: "icon_16x16@2x.png", pixels: 32),
    IconSize(filename: "icon_32x32.png", pixels: 32),
    IconSize(filename: "icon_32x32@2x.png", pixels: 64),
    IconSize(filename: "icon_128x128.png", pixels: 128),
    IconSize(filename: "icon_128x128@2x.png", pixels: 256),
    IconSize(filename: "icon_256x256.png", pixels: 256),
    IconSize(filename: "icon_256x256@2x.png", pixels: 512),
    IconSize(filename: "icon_512x512.png", pixels: 512),
    IconSize(filename: "icon_512x512@2x.png", pixels: 1024)
]

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(red: red / 255, green: green / 255, blue: blue / 255, alpha: alpha)
}

func drawIcon(size: Int) -> NSImage {
    let dimension = CGFloat(size)
    let image = NSImage(size: NSSize(width: dimension, height: dimension))

    image.lockFocus()
    guard let context = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }

    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)
    context.clear(CGRect(x: 0, y: 0, width: dimension, height: dimension))

    let inset = dimension * 0.055
    let rect = CGRect(x: inset, y: inset, width: dimension - inset * 2, height: dimension - inset * 2)
    let radius = dimension * 0.225
    let basePath = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

    context.saveGState()
    context.addPath(basePath)
    context.clip()

    let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [
            color(17, 28, 45).copy(alpha: 1)!,
            color(31, 51, 92).copy(alpha: 1)!,
            color(15, 118, 140).copy(alpha: 1)!
        ] as CFArray,
        locations: [0, 0.56, 1]
    )!
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: rect.minX, y: rect.maxY),
        end: CGPoint(x: rect.maxX, y: rect.minY),
        options: []
    )

    let glowGradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [color(80, 227, 194, 0.48), color(80, 227, 194, 0)] as CFArray,
        locations: [0, 1]
    )!
    context.drawRadialGradient(
        glowGradient,
        startCenter: CGPoint(x: dimension * 0.68, y: dimension * 0.28),
        startRadius: 0,
        endCenter: CGPoint(x: dimension * 0.68, y: dimension * 0.28),
        endRadius: dimension * 0.52,
        options: []
    )

    context.restoreGState()

    context.addPath(basePath)
    context.setStrokeColor(color(255, 255, 255, 0.16))
    context.setLineWidth(max(1, dimension * 0.012))
    context.strokePath()

    let center = CGPoint(x: dimension * 0.5, y: dimension * 0.49)
    let outerRadius = dimension * 0.255
    let innerRadius = dimension * 0.176
    let lineWidth = max(2, dimension * 0.035)

    context.setShadow(offset: CGSize(width: 0, height: -dimension * 0.018), blur: dimension * 0.04, color: color(0, 0, 0, 0.35))
    context.setStrokeColor(color(83, 232, 218))
    context.setLineWidth(lineWidth)
    context.strokeEllipse(in: CGRect(x: center.x - outerRadius, y: center.y - outerRadius, width: outerRadius * 2, height: outerRadius * 2))

    context.setShadow(offset: .zero, blur: 0, color: nil)
    context.setStrokeColor(color(176, 250, 241, 0.78))
    context.setLineWidth(max(1.25, dimension * 0.015))
    context.strokeEllipse(in: CGRect(x: center.x - innerRadius, y: center.y - innerRadius, width: innerRadius * 2, height: innerRadius * 2))

    let tickLength = dimension * 0.085
    let tickInset = outerRadius + dimension * 0.01
    context.setLineCap(.round)
    context.setStrokeColor(color(83, 232, 218))
    context.setLineWidth(max(2, dimension * 0.026))
    for angle in stride(from: 0.0, to: Double.pi * 2, by: Double.pi / 2) {
        let start = CGPoint(
            x: center.x + cos(angle) * (tickInset - tickLength),
            y: center.y + sin(angle) * (tickInset - tickLength)
        )
        let end = CGPoint(
            x: center.x + cos(angle) * tickInset,
            y: center.y + sin(angle) * tickInset
        )
        context.move(to: start)
        context.addLine(to: end)
        context.strokePath()
    }

    let keyholeTop = CGRect(
        x: center.x - dimension * 0.045,
        y: center.y - dimension * 0.02,
        width: dimension * 0.09,
        height: dimension * 0.09
    )
    let keyholeStem = CGRect(
        x: center.x - dimension * 0.028,
        y: center.y - dimension * 0.145,
        width: dimension * 0.056,
        height: dimension * 0.12
    )
    context.setFillColor(color(11, 21, 34, 0.95))
    context.fillEllipse(in: keyholeTop)
    let stemPath = CGPath(roundedRect: keyholeStem, cornerWidth: dimension * 0.018, cornerHeight: dimension * 0.018, transform: nil)
    context.addPath(stemPath)
    context.fillPath()

    let nodePoints = [
        CGPoint(x: dimension * 0.30, y: dimension * 0.31),
        CGPoint(x: dimension * 0.69, y: dimension * 0.33),
        CGPoint(x: dimension * 0.72, y: dimension * 0.66),
        CGPoint(x: dimension * 0.33, y: dimension * 0.68)
    ]

    context.setStrokeColor(color(130, 176, 255, 0.5))
    context.setLineWidth(max(1.2, dimension * 0.012))
    for point in nodePoints {
        context.move(to: center)
        context.addLine(to: point)
        context.strokePath()
    }

    for point in nodePoints {
        let nodeRadius = dimension * 0.033
        context.setFillColor(color(125, 155, 255))
        context.fillEllipse(in: CGRect(x: point.x - nodeRadius, y: point.y - nodeRadius, width: nodeRadius * 2, height: nodeRadius * 2))
        context.setStrokeColor(color(224, 242, 254, 0.72))
        context.setLineWidth(max(1, dimension * 0.008))
        context.strokeEllipse(in: CGRect(x: point.x - nodeRadius, y: point.y - nodeRadius, width: nodeRadius * 2, height: nodeRadius * 2))
    }

    context.setStrokeColor(color(255, 255, 255, 0.20))
    context.setLineWidth(max(1, dimension * 0.01))
    context.move(to: CGPoint(x: rect.minX + dimension * 0.14, y: rect.maxY - dimension * 0.12))
    context.addCurve(
        to: CGPoint(x: rect.maxX - dimension * 0.16, y: rect.maxY - dimension * 0.2),
        control1: CGPoint(x: dimension * 0.34, y: rect.maxY - dimension * 0.04),
        control2: CGPoint(x: dimension * 0.62, y: rect.maxY - dimension * 0.08)
    )
    context.strokePath()

    image.unlockFocus()
    return image
}

func savePNG(_ image: NSImage, to url: URL, pixels: Int) throws {
    guard let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let pngData = bitmap.representation(using: .png, properties: [:])
    else {
        throw NSError(domain: "LLMVaultIcon", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not render PNG at \(pixels)px"])
    }

    try pngData.write(to: url, options: [.atomic])
}

for size in sizes {
    let image = drawIcon(size: size.pixels)
    try savePNG(image, to: outputURL.appendingPathComponent(size.filename), pixels: size.pixels)
}

print("Rendered \(sizes.count) icon images to \(outputURL.path)")
