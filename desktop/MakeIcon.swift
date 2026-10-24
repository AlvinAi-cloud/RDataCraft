import Cocoa
let size = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
NSColor.clear.setFill(); NSRect(x: 0, y: 0, width: size, height: size).fill()
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
image.unlockFocus()
let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
