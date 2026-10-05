// Screenshot replay check for the top artwork region on the user's portrait Settings page.
// A nonblank result still needs visual confirmation that both earbuds and the case are shown.
import AppKit
guard CommandLine.arguments.count >= 2,
      let image = NSImage(contentsOfFile: CommandLine.arguments[1]),
      let data = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: data) else {
    fputs("Supply the unscrolled, portrait AirPods Settings screenshot.\n", stderr)
    exit(2)
}
let width = bitmap.pixelsWide, height = bitmap.pixelsHigh
guard height > width else { fputs("Expected portrait screenshot.\n", stderr); exit(2) }
var bright = 0, total = 0
for y in stride(from: Int(Double(height) * 0.14), to: Int(Double(height) * 0.33), by: 4) {
    for x in stride(from: Int(Double(width) * 0.15), to: Int(Double(width) * 0.85), by: 4) {
        guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
        if max(color.redComponent, color.greenComponent, color.blueComponent) > 0.25 { bright += 1 }
        total += 1
    }
}
guard total > 0 else { exit(2) }
let fraction = Double(bright) / Double(total)
print(String(format: "Artwork-region bright pixels: %.4f%% (%d/%d)", fraction * 100, bright, total))
if fraction < 0.001 {
    print("FAIL: the earbud/case artwork region is blank.")
    exit(1)
}
if CommandLine.arguments.contains("--visually-confirmed") {
    print("PASS: region is populated and earbuds/case were visually confirmed.")
} else {
    print("NEEDS_VISUAL_CHECK: region changed; confirm actual earbud and case images before declaring fixed.")
    exit(2)
}
