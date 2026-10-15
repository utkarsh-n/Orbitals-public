import AppKit
import CoreGraphics
let size = 1024
let bitmap = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:size,pixelsHigh:size,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep:bitmap)
let context = NSGraphicsContext.current!.cgContext
context.setFillColor(NSColor(red:0.025,green:0.055,blue:0.045,alpha:1).cgColor)
context.fill(CGRect(x:0,y:0,width:size,height:size))
let gradient = CGGradient(colorsSpace:CGColorSpaceCreateDeviceRGB(),colors:[NSColor(red:0.13,green:0.3,blue:0.2,alpha:1).cgColor,NSColor(red:0.02,green:0.035,blue:0.03,alpha:1).cgColor] as CFArray,locations:[0,1])!
context.drawRadialGradient(gradient,startCenter:CGPoint(x:440,y:580),startRadius:0,endCenter:CGPoint(x:512,y:512),endRadius:700,options:[])
let green = NSColor(red:0.4,green:0.96,blue:0.56,alpha:1)
let colors = [NSColor(red:1,green:0.75,blue:0.37,alpha:1),NSColor(red:1,green:0.4,blue:0.46,alpha:1),NSColor(red:0.78,green:0.61,blue:1,alpha:1)]
for index in 0..<3 {
    let path = CGMutablePath()
    for i in 0...240 {
        let a = Double(i)/240*Double.pi*2
        let rotation = Double(index)*Double.pi/3
        let x = cos(a)*310, y = sin(a)*142
        let point = CGPoint(x:512+x*cos(rotation)-y*sin(rotation),y:512+x*sin(rotation)+y*cos(rotation))
        if i == 0 { path.move(to:point) } else { path.addLine(to:point) }
    }
    context.saveGState()
    context.setShadow(offset:.zero,blur:26,color:green.withAlphaComponent(0.7).cgColor)
    context.setStrokeColor(green.withAlphaComponent(0.9).cgColor);context.setLineWidth(6);context.addPath(path);context.strokePath()
    context.restoreGState()
    let a = Double(index)*1.4 + 0.5, rotation = Double(index)*Double.pi/3
    let x = cos(a)*310, y = sin(a)*142
    let p = CGPoint(x:512+x*cos(rotation)-y*sin(rotation),y:512+x*sin(rotation)+y*cos(rotation))
    context.saveGState();context.setShadow(offset:.zero,blur:30,color:colors[index].cgColor)
    context.setFillColor(colors[index].cgColor);context.fillEllipse(in:CGRect(x:p.x-18,y:p.y-18,width:36,height:36));context.restoreGState()
}
context.setFillColor(green.cgColor);context.fillEllipse(in:CGRect(x:505,y:505,width:14,height:14))
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:CommandLine.arguments[1]))
