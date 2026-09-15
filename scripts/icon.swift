import AppKit
import Foundation

let destination = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let side = base * scale
        let image = NSImage(size: NSSize(width: side, height: side))
        image.lockFocus()
        let s = CGFloat(side)
        NSColor(red: 0.08, green: 0.12, blue: 0.15, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: s * 0.06, y: s * 0.06, width: s * 0.88, height: s * 0.88), xRadius: s * 0.2, yRadius: s * 0.2).fill()
        let center = NSPoint(x: s / 2, y: s / 2)
        let track = NSBezierPath()
        track.appendArc(withCenter: center, radius: s * 0.28, startAngle: 0, endAngle: 360)
        track.lineWidth = s * 0.09
        NSColor.white.withAlphaComponent(0.15).setStroke(); track.stroke()
        let arc = NSBezierPath()
        arc.appendArc(withCenter: center, radius: s * 0.28, startAngle: 90, endAngle: 305, clockwise: false)
        arc.lineWidth = s * 0.09; arc.lineCapStyle = .round
        NSColor(red: 0.23, green: 0.75, blue: 0.62, alpha: 1).setStroke(); arc.stroke()
        let needle = NSBezierPath()
        needle.move(to: center); needle.line(to: NSPoint(x: s * 0.65, y: s * 0.65))
        needle.lineWidth = s * 0.055; needle.lineCapStyle = .round
        NSColor.white.setStroke(); needle.stroke()
        image.unlockFocus()
        let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let name = "icon_\(base)x\(base)\(scale == 2 ? "@2x" : "").png"
        try rep.representation(using: .png, properties: [:])!.write(to: destination.appendingPathComponent(name))
    }
}
