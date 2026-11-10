#!/usr/bin/env swift
// Renders Folio's app icon into Folio/Resources/Assets.xcassets/AppIcon.appiconset.
// Usage: swift scripts/make-icon.swift [output folder]
// A page with a speech bubble beside it, on the macOS 26 icon grid (824pt body on a 1024 canvas).
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let output = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "Folio/Resources/Assets.xcassets/AppIcon.appiconset"

let space = CGColorSpace(name: CGColorSpace.displayP3)!

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: space, components: [
        CGFloat((hex >> 16) & 0xFF) / 255, CGFloat((hex >> 8) & 0xFF) / 255, CGFloat(hex & 0xFF) / 255, alpha,
    ])!
}

/// The macOS 26 icon outline: an 824pt rounded square with a 185pt corner radius.
func squircle(_ rect: CGRect) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: 185, cornerHeight: 185, transform: nil)
}

func linear(_ ctx: CGContext, _ colors: [CGColor], from: CGPoint, to: CGPoint) {
    let gradient = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: nil)!
    ctx.drawLinearGradient(gradient, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}

/// Page with a folded top-right corner. Coordinates are in the 1024 grid, origin bottom-left.
func pagePath(_ r: CGRect, fold: CGFloat, radius: CGFloat) -> CGPath {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: r.minX + radius, y: r.minY))
    p.addArc(tangent1End: CGPoint(x: r.maxX, y: r.minY), tangent2End: CGPoint(x: r.maxX, y: r.maxY), radius: radius)
    p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - fold))
    p.addLine(to: CGPoint(x: r.maxX - fold, y: r.maxY))
    p.addArc(tangent1End: CGPoint(x: r.minX, y: r.maxY), tangent2End: CGPoint(x: r.minX, y: r.minY), radius: radius)
    p.addArc(tangent1End: CGPoint(x: r.minX, y: r.minY), tangent2End: CGPoint(x: r.maxX, y: r.minY), radius: radius)
    p.closeSubpath()
    return p
}

/// Rounded speech bubble with a short tail at the bottom left, as one outline.
func bubblePath(_ r: CGRect, radius: CGFloat) -> CGPath {
    let body = CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
    let tail = CGMutablePath()
    let tip = CGPoint(x: r.minX + 10, y: r.minY - 50)
    tail.move(to: CGPoint(x: r.minX + 40, y: r.minY + 60))
    tail.addCurve(to: tip, control1: CGPoint(x: r.minX + 52, y: r.minY + 10),
                  control2: CGPoint(x: r.minX + 36, y: r.minY - 30))
    tail.addCurve(to: CGPoint(x: r.minX + 150, y: r.minY + 2), control1: CGPoint(x: r.minX + 56, y: r.minY - 50),
                  control2: CGPoint(x: r.minX + 110, y: r.minY - 22))
    tail.closeSubpath()
    return body.union(tail)
}

func render(pixels: Int) -> CGImage {
    let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let scale = CGFloat(pixels) / 1024
    ctx.scaleBy(x: scale, y: scale)
    ctx.interpolationQuality = .high
    let small = pixels <= 32      // drop fine detail where it would turn to mush
    let tiny = pixels <= 16

    // Body: 824 square, centered, with the system's soft drop shadow.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = squircle(body)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: color(0x000000, 0.28))
    ctx.addPath(shape); ctx.setFillColor(color(0x2F5BEA)); ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(shape); ctx.clip()
    linear(ctx, [color(0x5B8CFF), color(0x2E55E0), color(0x1F36B8)],
           from: CGPoint(x: 512, y: 924), to: CGPoint(x: 512, y: 100))
    // Gentle top light, as on the system icons.
    let glow = CGGradient(colorsSpace: space, colors: [color(0xFFFFFF, 0.22), color(0xFFFFFF, 0)] as CFArray, locations: nil)!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 400, y: 980), startRadius: 0,
                           endCenter: CGPoint(x: 400, y: 980), endRadius: 620, options: [])
    ctx.restoreGState()

    // Page, slightly left of center.
    let page = CGRect(x: 238, y: 214, width: 432, height: 560)
    let fold: CGFloat = small ? 0 : 108
    let pageShape = pagePath(page, fold: fold, radius: 34)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 36, color: color(0x0A1A66, 0.38))
    ctx.addPath(pageShape); ctx.setFillColor(color(0xFFFFFF)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(pageShape); ctx.clip()
    linear(ctx, [color(0xFFFFFF), color(0xEEF1F8)], from: CGPoint(x: 0, y: page.maxY), to: CGPoint(x: 0, y: page.minY))
    ctx.restoreGState()

    if fold > 0 {
        // The turned-down corner.
        let flap = CGMutablePath()
        flap.move(to: CGPoint(x: page.maxX - fold, y: page.maxY))
        flap.addLine(to: CGPoint(x: page.maxX - fold, y: page.maxY - fold + 22))
        flap.addArc(tangent1End: CGPoint(x: page.maxX - fold, y: page.maxY - fold),
                    tangent2End: CGPoint(x: page.maxX, y: page.maxY - fold), radius: 22)
        flap.addLine(to: CGPoint(x: page.maxX, y: page.maxY - fold))
        flap.closeSubpath()
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: -4, height: -6), blur: 12, color: color(0x0A1A66, 0.22))
        ctx.addPath(flap); ctx.setFillColor(color(0xD9DFEC)); ctx.fillPath()
        ctx.restoreGState()
    }

    // Text lines on the page.
    if !tiny {
        let lineHeight: CGFloat = small ? 40 : 26
        let gap: CGFloat = small ? 52 : 56
        let left = page.minX + 64
        var y = page.maxY - (small ? 96 : 132)
        let widths: [CGFloat] = small ? [0.62, 1, 0.8] : [0.55, 1, 1, 0.85, 1, 0.6]
        for (i, w) in widths.enumerated() {
            var full = page.width - 128
            if !small && i == 0 { full -= fold - 40 }
            let line = CGRect(x: left, y: y, width: full * w, height: lineHeight)
            ctx.addPath(CGPath(roundedRect: line, cornerWidth: lineHeight / 2, cornerHeight: lineHeight / 2, transform: nil))
            ctx.setFillColor(i == 0 ? color(0x2E55E0, 0.85) : color(0x8C96AD, 0.55))
            ctx.fillPath()
            y -= gap + (i == 0 ? 14 : 0)
        }
    }

    // Speech bubble overlapping the page's lower right.
    let bubble = CGRect(x: 488, y: 236, width: 330, height: 236)
    let bubbleShape = bubblePath(bubble, radius: 82)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 34, color: color(0x061048, 0.42))
    ctx.addPath(bubbleShape); ctx.setFillColor(color(0x10A37F)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(bubbleShape); ctx.clip()
    linear(ctx, [color(0x3DDC97), color(0x14B886), color(0x0C9A73)],
           from: CGPoint(x: 0, y: bubble.maxY), to: CGPoint(x: 0, y: bubble.minY - 60))
    ctx.restoreGState()
    // Thin light rim on the bubble.
    ctx.saveGState()
    ctx.addPath(bubbleShape); ctx.setStrokeColor(color(0xFFFFFF, 0.35)); ctx.setLineWidth(4)
    ctx.addPath(bubbleShape); ctx.clip(); ctx.addPath(bubbleShape); ctx.strokePath()
    ctx.restoreGState()

    // Three dots: a reply on its way. At 16px they'd merge into a bar, so the bubble stays plain.
    if tiny { return ctx.makeImage()! }
    let dot: CGFloat = small ? 52 : 44
    let spacing: CGFloat = small ? 76 : 72
    for i in -1...1 {
        let center = CGPoint(x: bubble.midX + CGFloat(i) * spacing, y: bubble.midY)
        ctx.addEllipse(in: CGRect(x: center.x - dot / 2, y: center.y - dot / 2, width: dot, height: dot))
    }
    ctx.setFillColor(color(0xFFFFFF)); ctx.fillPath()

    return ctx.makeImage()!
}

func write(_ image: CGImage, to path: String) {
    let url = URL(fileURLWithPath: path) as CFURL
    let dest = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("could not write \(path)") }
}

// The ten macOS slots: 16, 32, 128, 256, 512 points at 1x and 2x.
var entries: [String] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = points * scale
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        write(render(pixels: pixels), to: "\(output)/\(name)")
        entries.append(#"    { "filename" : "\#(name)", "idiom" : "mac", "scale" : "\#(scale)x", "size" : "\#(points)x\#(points)" }"#)
    }
}
let contents = "{\n  \"images\" : [\n" + entries.joined(separator: ",\n") + "\n  ],\n  \"info\" : { \"author\" : \"xcode\", \"version\" : 1 }\n}\n"
try! contents.write(toFile: "\(output)/Contents.json", atomically: true, encoding: .utf8)
print("wrote \(entries.count) icons to \(output)")
