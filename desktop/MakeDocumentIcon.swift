import Cocoa

// Original document artwork, shared by macOS ICNS and Windows ICO assets.
let bitmap = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:1024,pixelsHigh:1024,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep:bitmap)
NSColor.clear.setFill(); NSRect(x:0,y:0,width:1024,height:1024).fill()
let green = NSColor(red:0.14,green:0.47,blue:0.39,alpha:1)
let paper = NSBezierPath()
paper.move(to:NSPoint(x:194,y:78));paper.line(to:NSPoint(x:830,y:78));paper.line(to:NSPoint(x:830,y:797));paper.line(to:NSPoint(x:678,y:949));paper.line(to:NSPoint(x:194,y:949));paper.close()
NSColor.white.setFill();paper.fill()
NSColor(red:0.77,green:0.84,blue:0.79,alpha:1).setStroke();paper.lineWidth=7;paper.stroke()
let fold = NSBezierPath();fold.move(to:NSPoint(x:678,y:949));fold.line(to:NSPoint(x:678,y:797));fold.line(to:NSPoint(x:830,y:797));fold.close()
NSColor(red:0.87,green:0.93,blue:0.89,alpha:1).setFill();fold.fill()
green.setFill();NSBezierPath(roundedRect:NSRect(x:255,y:338,width:514,height:420),xRadius:35,yRadius:35).fill()
NSColor.white.withAlphaComponent(0.93).setStroke()
let axes=NSBezierPath();axes.lineWidth=15;axes.lineCapStyle = .round
axes.move(to:NSPoint(x:315,y:700));axes.line(to:NSPoint(x:315,y:398));axes.line(to:NSPoint(x:715,y:398));axes.stroke()
let curve=NSBezierPath();curve.lineWidth=16;curve.lineCapStyle = .round;curve.lineJoinStyle = .round
curve.move(to:NSPoint(x:357,y:444));curve.curve(to:NSPoint(x:690,y:684),controlPoint1:NSPoint(x:515,y:447),controlPoint2:NSPoint(x:502,y:679));curve.stroke()
for p in [NSPoint(x:370,y:448),NSPoint(x:478,y:497),NSPoint(x:568,y:632),NSPoint(x:684,y:681)] {
    NSColor.white.setFill();NSBezierPath(ovalIn:NSRect(x:p.x-12,y:p.y-12,width:24,height:24)).fill()
}
let label="RDC" as NSString
let attributes:[NSAttributedString.Key:Any]=[.font:NSFont.systemFont(ofSize:122,weight:.semibold),.foregroundColor:green]
let size=label.size(withAttributes:attributes)
label.draw(at:NSPoint(x:(1024-size.width)/2,y:150),withAttributes:attributes)
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:CommandLine.arguments[1]))
