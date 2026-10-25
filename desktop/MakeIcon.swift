import Cocoa
let size = 1024
// Explicit pixel bitmap avoids display scale affecting 1x icon representations.
let bitmap = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:size,pixelsHigh:size,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep:bitmap)
NSColor.clear.setFill(); NSRect(x: 0, y: 0, width: size, height: size).fill()
// Match the visible footprint of the current companion app at every resolution.
let transform=NSAffineTransform()
transform.translateX(by:512,yBy:512)
transform.scale(by:1024.0/876.0)
transform.translateX(by:-512,yBy:-512)
transform.concat()
let tile = NSBezierPath(roundedRect: NSRect(x: 74, y: 74, width: 876, height: 876), xRadius: 185, yRadius: 185)
NSColor(red: 0.14, green: 0.47, blue: 0.39, alpha: 1).setFill(); tile.fill()
NSColor.white.withAlphaComponent(0.85).setStroke()
let axes = NSBezierPath(); axes.lineWidth = 26; axes.lineCapStyle = .round
axes.move(to: NSPoint(x: 263, y: 751)); axes.line(to: NSPoint(x: 263, y: 280)); axes.line(to: NSPoint(x: 772, y: 280)); axes.stroke()
let line = NSBezierPath(); line.lineWidth = 24; line.lineJoinStyle = .round; line.lineCapStyle = .round
line.move(to: NSPoint(x: 341, y: 379)); line.line(to: NSPoint(x: 468, y: 550)); line.line(to: NSPoint(x: 597, y: 484)); line.line(to: NSPoint(x: 744, y: 715)); line.stroke()
for point in [NSPoint(x: 341, y: 379), NSPoint(x: 468, y: 550), NSPoint(x: 597, y: 484), NSPoint(x: 744, y: 715)] {
    NSColor(red: 0.89, green: 0.95, blue: 0.91, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: point.x - 30, y: point.y - 30, width: 60, height: 60)).fill()
}
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
