// Draws Tweetintosh's app icon and packages it as src/AppIcon.icns.
//
//   swift tools/make-app-icon.swift            writes src/AppIcon.icns
//   swift tools/make-app-icon.swift <dir>      also leaves the PNGs in <dir>, for looking at
//
// A pixel-art Macintosh showing a double-struck 𝕋, drawn as rectangles on a 4-pixel grid so it is sharp at full size, and
// drawn again at every size from scratch so small sizes stay clean. Nothing is typeset: the menu titles use the tiny pixel
// font below, because system fonts may not be used in a logo. The icon carries no Apple or X marks on purpose: the four
// coloured rows where the Apple logo would be, and at the start of the menu bar, are the app's own.

import AppKit

let sizes: [(points: Int, scale: Int)] = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
}

// A 5-pixel-high font with only the letters the menu bar needs. Most letters are 3 wide; M and W need 5, or W reads as H.
let pixelFont: [Character: [String]] = [
    "F": ["###", "#..", "##.", "#..", "#.."],
    "i": [".#.", "...", ".#.", ".#.", ".#."],
    "l": [".#.", ".#.", ".#.", ".#.", ".#."],
    "e": ["...", ".##", "###", "#..", ".##"],
    "E": ["###", "#..", "##.", "#..", "###"],
    "d": ["..#", "..#", ".##", "#.#", ".##"],
    "t": [".#.", "###", ".#.", ".#.", "..#"],
    "M": ["#...#", "##.##", "#.#.#", "#...#", "#...#"],
    "n": ["...", "##.", "#.#", "#.#", "#.#"],
    "u": ["...", "#.#", "#.#", "#.#", ".##"],
    "W": ["#...#", "#...#", "#.#.#", "##.##", "#...#"],
    "o": ["...", ".#.", "#.#", "#.#", ".#."],
    "w": [".....", "#...#", "#.#.#", "#.#.#", ".#.#."],
    "H": ["#.#", "#.#", "###", "#.#", "#.#"],
    "p": ["...", "##.", "#.#", "##.", "#.."],
]

// The app's mark, in place of the Apple logo: four rows of pixels, green, yellow, red and blue
let markColors: [UInt32] = [0x5EBD3E, 0xFFB900, 0xE23838, 0x009CDF]

// All coordinates are on Apple's 1024-point icon grid, top-left origin
func draw(in ctx: CGContext, pixels: Int) {
    let s = CGFloat(pixels) / 1024
    ctx.scaleBy(x: s, y: s)
    ctx.translateBy(x: 0, y: 1024)
    ctx.scaleBy(x: 1, y: -1)
    let space = CGColorSpace(name: CGColorSpace.sRGB)!

    func box(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ c: UInt32) {
        ctx.setFillColor(color(c)); ctx.fill(CGRect(x: x, y: y, width: w, height: h))
    }
    // A black outline drawn inside the rectangle, like a 1-bit frame
    func frame(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ t: CGFloat, _ c: UInt32 = 0x1E1E1C) {
        box(x, y, w, t, c); box(x, y + h - t, w, t, c); box(x, y, t, h, c); box(x + w - t, y, t, h, c)
    }
    func checker(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, cell: CGFloat = 4) {
        box(x, y, w, h, 0xE6E9E4)
        var row: CGFloat = 0
        while row * cell < h {
            var col: CGFloat = 0
            while col * cell < w {
                if (Int(row) + Int(col)) % 2 == 0 {
                    box(x + col * cell, y + row * cell, min(cell, w - col * cell), min(cell, h - row * cell), 0x3A3A38)
                }
                col += 1
            }
            row += 1
        }
    }
    func text(_ string: String, x: CGFloat, y: CGFloat, dot: CGFloat) {
        var cursor = x
        for character in string {
            if let rows = pixelFont[character] {
                for (r, line) in rows.enumerated() {
                    for (c, bit) in line.enumerated() where bit == "#" {
                        box(cursor + CGFloat(c) * dot, y + CGFloat(r) * dot, dot, dot, 0x1E1E1C)
                    }
                }
            }
            cursor += CGFloat((pixelFont[character]?.first?.count ?? 3) + 1) * dot
        }
    }
    // Four coloured rows with their corners cut by one pixel, which is how pixel art rounds a shape
    func mark(x: CGFloat, y: CGFloat, width: CGFloat, row: CGFloat, notch: CGFloat) {
        for (i, c) in markColors.enumerated() {
            let inset: CGFloat = (i == 0 || i == markColors.count - 1) ? notch : 0
            box(x + inset, y + CGFloat(i) * row, width - 2 * inset, row, c)
        }
    }

    // Background: the standard macOS icon shape, with the standard soft shadow, and nothing around it
    let tile = CGPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824), cornerWidth: 185, cornerHeight: 185, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10 * s), blur: 22 * s, color: color(0x000000, 0.26))
    ctx.addPath(tile); ctx.setFillColor(color(0xE3CEAA)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState(); ctx.addPath(tile); ctx.clip()
    let g = CGGradient(colorsSpace: space, colors: [color(0xE9D6B4), color(0xDDC59E)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: 100), end: CGPoint(x: 0, y: 924), options: [])
    ctx.restoreGState()

    // The computer: a shadow, the foot, the case with its bevels, and a black outline
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12 * s), blur: 20 * s, color: color(0x5A4630, 0.28))
    box(244, 200, 536, 616, 0xA8977A)
    ctx.restoreGState()
    box(256, 796, 512, 20, 0xA8977A)
    box(240, 196, 544, 604, 0xE9DFC6)
    box(240, 196, 544, 28, 0xF4EEDF)            // top face
    box(240, 196, 12, 604, 0xF4EEDF)            // left bevel, catching the light
    box(772, 196, 12, 604, 0xCFC2A3)            // right bevel, in shade
    box(240, 760, 544, 40, 0xD3C6A8)            // chin
    box(240, 756, 544, 4, 0xBFB08F)
    frame(240, 196, 544, 604, 6)
    box(256, 816, 512, 4, 0x8E7F64)

    // Screen: a window filling it, with the menu bar above
    box(290, 250, 444, 336, 0x1E1E1C)
    box(294, 254, 436, 28, 0xF4F4F0)
    box(294, 282, 436, 4, 0x1E1E1C)
    box(294, 286, 436, 296, 0xE6E9E4)
    mark(x: 306, y: 259, width: 16, row: 4.5, notch: 3)
    text("File Edit Menu Window Help", x: 336, y: 261, dot: 3)

    // Scroll bars, dithered as on a 1-bit screen, with their arrow boxes
    checker(710, 286, 20, 256)
    checker(314, 562, 376, 20)
    box(706, 286, 4, 296, 0x1E1E1C)
    box(294, 558, 436, 4, 0x1E1E1C)
    for (x, y) in [(294.0, 562.0), (690.0, 562.0), (710.0, 542.0), (710.0, 562.0)] {
        box(x, y, 20, 20, 0xF4F4F0); frame(x, y, 20, 20, 3)
    }
    // Left and right arrows, and the resize box
    for i in 0..<4 { box(300 + CGFloat(i) * 2, 571 - CGFloat(i) * 2, 2, 2 + CGFloat(i) * 4, 0x1E1E1C) }
    for i in 0..<4 { box(702 - CGFloat(i) * 2, 571 - CGFloat(i) * 2, 2, 2 + CGFloat(i) * 4, 0x1E1E1C) }
    for i in 0..<4 { box(714 + CGFloat(i) * 3, 554 - CGFloat(i) * 2, 3, 2 + CGFloat(i) * 2, 0x1E1E1C) }
    frame(715, 567, 10, 10, 2)

    // 𝕋, double-struck: a solid crossbar over an outlined stem
    box(430, 334, 164, 12, 0x1E1E1C)
    frame(494, 344, 34, 178, 6)

    // The app's mark, where the Apple logo was
    mark(x: 292, y: 690, width: 40, row: 12, notch: 4)

    // Floppy drive and grille
    box(512, 650, 218, 50, 0xDDD2B8)
    frame(512, 650, 218, 50, 3, 0xA99A7E)
    box(528, 670, 188, 14, 0x1E1E1C)
    box(660, 660, 56, 32, 0x1E1E1C)
    box(668, 668, 40, 8, 0x3E3C38)
    box(722, 680, 4, 4, 0x1E1E1C)
    for i in 0..<14 { box(570 + CGFloat(i) * 11.5, 772, 6, 28, 0x1E1E1C) }
}

let fm = FileManager.default
let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let keep = CommandLine.arguments.count > 1 ? URL(fileURLWithPath: CommandLine.arguments[1]) : nil
let iconset = fm.temporaryDirectory.appendingPathComponent("AppIcon-\(UUID().uuidString).iconset")
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)

for (points, scale) in sizes {
    let pixels = points * scale
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high
    draw(in: ctx, pixels: pixels)
    let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
    try rep.representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent(name))
}

if let keep = keep {
    try? fm.removeItem(at: keep)
    try fm.copyItem(at: iconset, to: keep)
}
let output = root.appendingPathComponent("src/AppIcon.icns")
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try task.run()
task.waitUntilExit()
try? fm.removeItem(at: iconset)
print(task.terminationStatus == 0 ? "wrote \(output.path)" : "iconutil failed")
