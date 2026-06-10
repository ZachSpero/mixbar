// Draws the MixBar app icon: a deep-forest squircle with three gold mixer
// faders at different heights (the per-app volume metaphor). Flat colors,
// no gradients, subtle grain for texture. Writes a 1024x1024 PNG.
//
// Usage: swift tools/makeicon.swift out.png
import AppKit

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"
let S: CGFloat = 1024

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(S), pixelsHigh: Int(S),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!

let nsctx = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = nsctx
let ctx = nsctx.cgContext

func color(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat(r)/255, green: CGFloat(g)/255, blue: CGFloat(b)/255, alpha: a)
}

// Palette
let forest      = color(21, 57, 43)      // deep forest background
let forestDeep  = color(13, 38, 28)      // notch / shadow accents
let gold        = color(212, 168, 60)    // fader caps
let goldDim     = color(170, 134, 48)    // cap edge accent
let cream       = color(242, 233, 216)   // subtle track

// Squircle background
let margin: CGFloat = 96
let rect = CGRect(x: margin, y: margin, width: S - margin*2, height: S - margin*2)
let radius: CGFloat = (S - margin*2) * 0.2237
let squircle = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

ctx.addPath(squircle)
ctx.setFillColor(forest)
ctx.fillPath()

// Faders
let trackTop: CGFloat = 758
let trackBottom: CGFloat = 266
let trackRange = trackTop - trackBottom
let centersX: [CGFloat] = [330, 512, 694]
let levels:   [CGFloat] = [0.74, 0.30, 0.55]   // left high, middle low, right medium

func roundedRect(_ cx: CGFloat, _ cy: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> CGPath {
    CGPath(roundedRect: CGRect(x: cx - w/2, y: cy - h/2, width: w, height: h),
           cornerWidth: r, cornerHeight: r, transform: nil)
}

// Tracks (subtle cream channels)
for cx in centersX {
    ctx.addPath(roundedRect(cx, (trackTop + trackBottom)/2, 34, trackRange + 34, 17))
    ctx.setFillColor(cream.copy(alpha: 0.12)!)
    ctx.fillPath()
    // small end ticks
    for ty in [trackTop, trackBottom] {
        ctx.addPath(roundedRect(cx, ty, 64, 12, 6))
        ctx.setFillColor(cream.copy(alpha: 0.20)!)
        ctx.fillPath()
    }
}

// Caps
let capW: CGFloat = 158
let capH: CGFloat = 92
for (i, cx) in centersX.enumerated() {
    let cy = trackBottom + levels[i] * trackRange
    // edge accent (flat, slightly larger, behind)
    ctx.addPath(roundedRect(cx, cy - 4, capW + 8, capH + 8, 30))
    ctx.setFillColor(goldDim)
    ctx.fillPath()
    // main cap
    ctx.addPath(roundedRect(cx, cy, capW, capH, 28))
    ctx.setFillColor(gold)
    ctx.fillPath()
    // center grip line
    ctx.addPath(roundedRect(cx, cy, capW - 44, 12, 6))
    ctx.setFillColor(forestDeep)
    ctx.fillPath()
}

// Subtle grain, clipped to the squircle
ctx.saveGState()
ctx.addPath(squircle)
ctx.clip()
var seed: UInt64 = 0x9E3779B97F4A7C15
func rnd() -> CGFloat {
    seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
    return CGFloat(Double(seed % 10000) / 10000.0)
}
for _ in 0..<9000 {
    let x = rnd() * S
    let y = rnd() * S
    let bright = rnd() > 0.5
    ctx.setFillColor(bright ? color(255,255,255,0.025) : color(0,0,0,0.035))
    ctx.fill(CGRect(x: x, y: y, width: 2.2, height: 2.2))
}
ctx.restoreGState()

NSGraphicsContext.restoreGraphicsState()

guard let data = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("failed to encode PNG\n".utf8)); exit(1)
}
try! data.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath)")
