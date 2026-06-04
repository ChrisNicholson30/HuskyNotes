// Flattens a (possibly transparent) source PNG onto an opaque background and
// writes a 1024×1024 PNG with NO alpha channel — required for iOS app icons.
// Uses CoreGraphics/ImageIO only (headless-safe; no AppKit/window server).
//
// Usage: xcrun swift flatten-icon.swift <source.png> <out.png> <hexBackground>

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count >= 4 else {
    FileHandle.standardError.write(Data("usage: flatten-icon.swift <src> <out> <hex>\n".utf8))
    exit(1)
}
let srcPath = args[1], outPath = args[2], hex = args[3]

func rgb(_ hex: String) -> (CGFloat, CGFloat, CGFloat) {
    var s = hex
    if s.hasPrefix("#") { s.removeFirst() }
    let v = UInt32(s, radix: 16) ?? 0
    return (CGFloat((v >> 16) & 0xFF) / 255, CGFloat((v >> 8) & 0xFF) / 255, CGFloat(v & 0xFF) / 255)
}

guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: srcPath) as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    FileHandle.standardError.write(Data("Could not read source: \(srcPath)\n".utf8))
    exit(1)
}

let dim = 1024
let space = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(data: nil, width: dim, height: dim, bitsPerComponent: 8,
                          bytesPerRow: 0, space: space,
                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { exit(1) }

let (r, g, b) = rgb(hex)
ctx.setFillColor(red: r, green: g, blue: b, alpha: 1)
ctx.fill(CGRect(x: 0, y: 0, width: dim, height: dim))

// Aspect-fit the artwork centered, so non-square art isn't distorted.
let iw = CGFloat(image.width), ih = CGFloat(image.height)
let scale = min(CGFloat(dim) / iw, CGFloat(dim) / ih)
let w = iw * scale, h = ih * scale
ctx.interpolationQuality = .high
ctx.draw(image, in: CGRect(x: (CGFloat(dim) - w) / 2, y: (CGFloat(dim) - h) / 2, width: w, height: h))

guard let out = ctx.makeImage(),
      let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: outPath) as CFURL,
                                                 UTType.png.identifier as CFString, 1, nil) else { exit(1) }
CGImageDestinationAddImage(dest, out, nil)
if CGImageDestinationFinalize(dest) {
    print("Flattened opaque master → \(outPath)")
} else {
    FileHandle.standardError.write(Data("Write failed\n".utf8))
    exit(1)
}
