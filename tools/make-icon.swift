// Turns a generated icon (a mint tile on a white background) into Spruce's app icon:
// finds the tile, crops it, and masks it onto Apple's macOS icon grid (an 824 px rounded tile
// centered on a transparent 1024 px canvas). Then builds art/Spruce.icns with sips + iconutil.
//
//   swift tools/make-icon.swift art/icon-options/option-4.png
//   then: sips to an .iconset (16–512 @1x/@2x) and `iconutil -c icns -o art/Spruce.icns <iconset>`
import AppKit
import CoreGraphics
import ImageIO

let args = CommandLine.arguments
guard args.count == 2, let source = CGImageSourceCreateWithURL(URL(filePath: args[1]) as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    print("usage: swift tools/make-icon.swift <source.png>"); exit(2)
}

// Read pixels as RGBA.
let w = image.width, h = image.height
var pixels = [UInt8](repeating: 0, count: w * h * 4)
let rgb = CGColorSpace(name: CGColorSpace.sRGB)!
let reader = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                       space: rgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
reader.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

// The tile is mint (green clearly above red); the background and its shadow are neutral grays.
var minX = w, minY = h, maxX = 0, maxY = 0
for y in 0..<h {
    for x in 0..<w {
        let i = (y * w + x) * 4
        if Int(pixels[i + 1]) - Int(pixels[i]) > 10 {
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        }
    }
}
guard maxX > minX, maxY > minY else { print("couldn't find the tile"); exit(1) }
// Inset a few pixels to drop the tile's own rim and any background bleed at the corners.
let inset = 6
let bitmapRect = CGRect(x: minX + inset, y: minY + inset, width: maxX - minX - 2 * inset, height: maxY - minY - 2 * inset)
// CGImage cropping uses top-left origin; the bitmap context above is bottom-left.
let cropRect = CGRect(x: bitmapRect.minX, y: CGFloat(h) - bitmapRect.maxY, width: bitmapRect.width, height: bitmapRect.height)
let tile = image.cropping(to: cropRect)!

// Apple's macOS icon grid: 1024 canvas, 824 tile, ~22.4% corner radius.
let canvas = 1024, size: CGFloat = 824, origin = (CGFloat(canvas) - size) / 2
let out = CGContext(data: nil, width: canvas, height: canvas, bitsPerComponent: 8, bytesPerRow: 0,
                    space: rgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
let frame = CGRect(x: origin, y: origin, width: size, height: size)
out.addPath(CGPath(roundedRect: frame, cornerWidth: size * 0.2237, cornerHeight: size * 0.2237, transform: nil))
out.clip()
out.interpolationQuality = .high
out.draw(tile, in: frame)

let png = URL(filePath: "art/Spruce-1024.png")
let dest = CGImageDestinationCreateWithURL(png as CFURL, "public.png" as CFString, 1, nil)!
CGImageDestinationAddImage(dest, out.makeImage()!, nil)
guard CGImageDestinationFinalize(dest) else { print("couldn't write \(png.path)"); exit(1) }
print("tile found at \(bitmapRect), wrote \(png.path)")
