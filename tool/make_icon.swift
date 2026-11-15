// Dastur ikonkasini yaratadi: swift tool/make_icon.swift <chiqish.png>
import AppKit

let S: CGFloat = 1024
let img = NSImage(size: NSSize(width: S, height: S))
img.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext

// macOS uslubidagi fon (squircle), atrofida bo'sh joy bilan
let inset: CGFloat = 100
let bg = NSBezierPath(roundedRect: NSRect(x: inset, y: inset, width: S - 2*inset, height: S - 2*inset), xRadius: 185, yRadius: 185)
ctx.saveGState()
let shadow = NSShadow(); shadow.shadowBlurRadius = 30; shadow.shadowOffset = NSSize(width: 0, height: -12)
shadow.shadowColor = NSColor.black.withAlphaComponent(0.35); shadow.set()
NSColor.black.setFill(); bg.fill()
ctx.restoreGState()
bg.addClip()
NSGradient(colors: [NSColor(red: 0.10, green: 0.12, blue: 0.22, alpha: 1),
                    NSColor(red: 0.20, green: 0.10, blue: 0.32, alpha: 1),
                    NSColor(red: 0.05, green: 0.30, blue: 0.40, alpha: 1)])!
  .draw(in: bg, angle: -60)

// Orolning nuri
let glow = NSGradient(colors: [NSColor(red: 0.2, green: 0.78, blue: 0.35, alpha: 0.45), NSColor.clear])!
glow.draw(fromCenter: NSPoint(x: S/2, y: 640), radius: 0, toCenter: NSPoint(x: S/2, y: 640), radius: 330, options: [])

// Orol (pill)
let pillW: CGFloat = 560, pillH: CGFloat = 170
let pill = NSBezierPath(roundedRect: NSRect(x: (S-pillW)/2, y: 560, width: pillW, height: pillH), xRadius: pillH/2, yRadius: pillH/2)
NSColor.black.setFill(); pill.fill()

// Chapda musiqa rasmi
let art = NSBezierPath(roundedRect: NSRect(x: (S-pillW)/2 + 40, y: 560 + 35, width: 100, height: 100), xRadius: 26, yRadius: 26)
NSGradient(colors: [NSColor(red: 1, green: 0.22, blue: 0.37, alpha: 1), NSColor(red: 0.75, green: 0.35, blue: 0.95, alpha: 1)])!.draw(in: art, angle: -45)

// O'ngda ekvalayzer
let heights: [CGFloat] = [60, 100, 44, 84]
NSColor(red: 0.2, green: 0.78, blue: 0.35, alpha: 1).setFill()
for (i, h) in heights.enumerated() {
  let x = (S+pillW)/2 - 160 + CGFloat(i) * 32
  NSBezierPath(roundedRect: NSRect(x: x, y: 645 - h/2, width: 18, height: h), xRadius: 9, yRadius: 9).fill()
}

// Pastda kichik kartalar (ochilgan orol ma'nosida)
NSColor.white.withAlphaComponent(0.12).setFill()
NSBezierPath(roundedRect: NSRect(x: 230, y: 250, width: 250, height: 230), xRadius: 48, yRadius: 48).fill()
NSBezierPath(roundedRect: NSRect(x: 544, y: 250, width: 250, height: 230), xRadius: 48, yRadius: 48).fill()
NSColor(red: 1, green: 0.62, blue: 0.04, alpha: 1).setStroke()
let ring = NSBezierPath(); ring.lineWidth = 22; ring.lineCapStyle = .round
ring.appendArc(withCenter: NSPoint(x: 355, y: 365), radius: 62, startAngle: 90, endAngle: -150, clockwise: true)
ring.stroke()
NSColor(red: 0.39, green: 0.82, blue: 1, alpha: 1).setFill()
NSBezierPath(ovalIn: NSRect(x: 619, y: 315, width: 100, height: 100)).fill()

img.unlockFocus()
let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
