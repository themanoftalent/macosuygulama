import AppKit
import CoreGraphics

let outputDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let iconsetPath = "\(outputDir)/AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

func renderIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    guard let ctx = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }

    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    let inset = size * 0.08
    let iconRect = rect.insetBy(dx: inset, dy: inset)
    let cornerRadius = iconRect.width * 0.225

    // Background rounded square with blue-indigo gradient
    let bgPath = CGPath(roundedRect: iconRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
    ctx.saveGState()
    ctx.addPath(bgPath)
    ctx.clip()

    let colors = [
        NSColor(calibratedRed: 0.06, green: 0.56, blue: 1.00, alpha: 1.0).cgColor,
        NSColor(calibratedRed: 0.36, green: 0.42, blue: 0.96, alpha: 1.0).cgColor,
        NSColor(calibratedRed: 0.46, green: 0.36, blue: 0.94, alpha: 1.0).cgColor
    ] as CFArray
    let locations: [CGFloat] = [0.0, 0.55, 1.0]
    if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: locations) {
        ctx.drawLinearGradient(
            grad,
            start: CGPoint(x: iconRect.midX, y: iconRect.minY),
            end: CGPoint(x: iconRect.midX, y: iconRect.maxY),
            options: []
        )
    }
    ctx.restoreGState()

    // Subtle border highlight
    ctx.saveGState()
    ctx.addPath(bgPath)
    ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.28).cgColor)
    ctx.setLineWidth(size * 0.01)
    ctx.strokePath()
    ctx.restoreGState()

    // Folder back tab shape
    let folderX = size * 0.20
    let folderY = size * 0.28
    let folderW = size * 0.54
    let folderH = size * 0.42
    let tabW = folderW * 0.40
    let tabH = folderH * 0.18
    let r = size * 0.045

    let folderPath = CGMutablePath()
    folderPath.move(to: CGPoint(x: folderX + r, y: folderY))
    folderPath.addLine(to: CGPoint(x: folderX + folderW - r, y: folderY))
    folderPath.addQuadCurve(to: CGPoint(x: folderX + folderW, y: folderY + r), control: CGPoint(x: folderX + folderW, y: folderY))
    folderPath.addLine(to: CGPoint(x: folderX + folderW, y: folderY + folderH - tabH - r))
    folderPath.addQuadCurve(to: CGPoint(x: folderX + folderW - r, y: folderY + folderH - tabH), control: CGPoint(x: folderX + folderW, y: folderY + folderH - tabH))
    folderPath.addLine(to: CGPoint(x: folderX + tabW + r * 0.6, y: folderY + folderH - tabH))
    folderPath.addLine(to: CGPoint(x: folderX + tabW - r * 0.4, y: folderY + folderH))
    folderPath.addLine(to: CGPoint(x: folderX + r, y: folderY + folderH))
    folderPath.addQuadCurve(to: CGPoint(x: folderX, y: folderY + folderH - r), control: CGPoint(x: folderX, y: folderY + folderH))
    folderPath.addLine(to: CGPoint(x: folderX, y: folderY + r))
    folderPath.addQuadCurve(to: CGPoint(x: folderX + r, y: folderY), control: CGPoint(x: folderX, y: folderY))
    folderPath.closeSubpath()

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.02), blur: size * 0.04, color: NSColor.black.withAlphaComponent(0.22).cgColor)
    ctx.addPath(folderPath)
    ctx.setFillColor(NSColor.white.withAlphaComponent(0.92).cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    // Folder front light sheen
    let frontRect = CGRect(x: folderX, y: folderY, width: folderW, height: folderH * 0.72)
    let frontPath = CGPath(roundedRect: frontRect, cornerWidth: r, cornerHeight: r, transform: nil)
    ctx.saveGState()
    ctx.addPath(frontPath)
    ctx.clip()
    let folderColors = [
        NSColor(calibratedRed: 0.78, green: 0.90, blue: 1.0, alpha: 0.95).cgColor,
        NSColor(calibratedRed: 0.96, green: 0.98, blue: 1.0, alpha: 0.98).cgColor
    ] as CFArray
    if let fGrad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: folderColors, locations: [0.0, 1.0]) {
        ctx.drawLinearGradient(
            fGrad,
            start: CGPoint(x: frontRect.midX, y: frontRect.minY),
            end: CGPoint(x: frontRect.midX, y: frontRect.maxY),
            options: []
        )
    }
    ctx.restoreGState()

    // Up-arrow circular badge on upper-right of folder
    let badgeRadius = size * 0.145
    let badgeCenter = CGPoint(x: folderX + folderW - size * 0.02, y: folderY + folderH - size * 0.08)
    let badgeRect = CGRect(
        x: badgeCenter.x - badgeRadius,
        y: badgeCenter.y - badgeRadius,
        width: badgeRadius * 2,
        height: badgeRadius * 2
    )

    // Blue cutout ring around badge
    ctx.saveGState()
    let ringRect = badgeRect.insetBy(dx: -size * 0.022, dy: -size * 0.022)
    ctx.setFillColor(NSColor(calibratedRed: 0.25, green: 0.45, blue: 0.96, alpha: 1.0).cgColor)
    ctx.fillEllipse(in: ringRect)

    ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.01), blur: size * 0.025, color: NSColor.black.withAlphaComponent(0.18).cgColor)
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.fillEllipse(in: badgeRect)
    ctx.restoreGState()

    // Up arrow inside badge
    let arrowColor = NSColor(calibratedRed: 0.22, green: 0.42, blue: 0.94, alpha: 1.0).cgColor
    ctx.saveGState()
    ctx.setFillColor(arrowColor)
    let stemW = badgeRadius * 0.34
    let stemH = badgeRadius * 0.62
    let headW = badgeRadius * 0.92
    let headH = badgeRadius * 0.56
    let arrowBottom = badgeCenter.y - badgeRadius * 0.52

    let arrowPath = CGMutablePath()
    arrowPath.move(to: CGPoint(x: badgeCenter.x - stemW / 2, y: arrowBottom))
    arrowPath.addLine(to: CGPoint(x: badgeCenter.x + stemW / 2, y: arrowBottom))
    arrowPath.addLine(to: CGPoint(x: badgeCenter.x + stemW / 2, y: arrowBottom + stemH))
    arrowPath.addLine(to: CGPoint(x: badgeCenter.x + headW / 2, y: arrowBottom + stemH))
    arrowPath.addLine(to: CGPoint(x: badgeCenter.x, y: arrowBottom + stemH + headH))
    arrowPath.addLine(to: CGPoint(x: badgeCenter.x - headW / 2, y: arrowBottom + stemH))
    arrowPath.addLine(to: CGPoint(x: badgeCenter.x - stemW / 2, y: arrowBottom + stemH))
    arrowPath.closeSubpath()
    ctx.addPath(arrowPath)
    ctx.fillPath()
    ctx.restoreGState()

    image.unlockFocus()
    return image
}

let sizes: [(Int, String)] = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png")
]

for (px, name) in sizes {
    let img = renderIcon(size: CGFloat(px))
    if let tiff = img.tiffRepresentation,
       let rep = NSBitmapImageRep(data: tiff),
       let png = rep.representation(using: .png, properties: [:]) {
        try? png.write(to: URL(fileURLWithPath: "\(iconsetPath)/\(name)"))
    }
}
