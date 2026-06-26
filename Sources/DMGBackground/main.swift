import AppKit
import Foundation

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    fputs("Usage: DMGBackground <icon-png> <output-png>\n", stderr)
    exit(1)
}

_ = URL(fileURLWithPath: arguments[1])
let outputURL = URL(fileURLWithPath: arguments[2])

let canvasSize = NSSize(width: 640, height: 420)
let image = NSImage(size: canvasSize)

func drawCentered(_ text: String, in rect: NSRect, font: NSFont, color: NSColor, paragraphStyle: NSMutableParagraphStyle? = nil) {
    let style = paragraphStyle ?? NSMutableParagraphStyle()
    style.alignment = .center
    style.lineBreakMode = .byWordWrapping

    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: color,
        .paragraphStyle: style
    ]
    (text as NSString).draw(in: rect, withAttributes: attributes)
}

image.lockFocus()

let bounds = NSRect(origin: .zero, size: canvasSize)
NSColor(calibratedRed: 0.78, green: 0.90, blue: 0.98, alpha: 1).setFill()
bounds.fill()

let gradient = NSGradient(
    starting: NSColor(calibratedRed: 0.86, green: 0.95, blue: 1.0, alpha: 1),
    ending: NSColor(calibratedRed: 0.58, green: 0.78, blue: 0.92, alpha: 1)
)
gradient?.draw(in: bounds, angle: 90)

let titleColor = NSColor(calibratedWhite: 0.10, alpha: 1)
let bodyColor = NSColor(calibratedWhite: 0.18, alpha: 1)
let blue = NSColor(calibratedRed: 0.15, green: 0.40, blue: 0.62, alpha: 1)
let finderAppIconCenter = NSPoint(x: 174, y: 196)
let finderApplicationsIconCenter = NSPoint(x: 464, y: 196)
let iconSize: CGFloat = 96
let arrowMargin: CGFloat = 18

func backgroundY(forFinderY finderY: CGFloat) -> CGFloat {
    canvasSize.height - finderY
}

drawCentered(
    "JazzSON",
    in: NSRect(x: 40, y: 354, width: 560, height: 40),
    font: .systemFont(ofSize: 30, weight: .bold),
    color: titleColor
)

drawCentered(
    "Drag JazzSON into Applications to install.",
    in: NSRect(x: 80, y: 318, width: 480, height: 28),
    font: .systemFont(ofSize: 16, weight: .semibold),
    color: bodyColor
)

let arrowY = backgroundY(forFinderY: finderAppIconCenter.y)
let arrowStartX = finderAppIconCenter.x + (iconSize / 2) + arrowMargin
let arrowTipX = finderApplicationsIconCenter.x - (iconSize / 2) - arrowMargin
let arrowHeadWidth: CGFloat = 26
let arrowHeadHeight: CGFloat = 18
let arrowPath = NSBezierPath()
arrowPath.move(to: NSPoint(x: arrowStartX, y: arrowY))
arrowPath.line(to: NSPoint(x: arrowTipX - arrowHeadWidth + 2, y: arrowY))
arrowPath.lineWidth = 7
arrowPath.lineCapStyle = .round
blue.setStroke()
arrowPath.stroke()

let arrowHead = NSBezierPath()
arrowHead.move(to: NSPoint(x: arrowTipX, y: arrowY))
arrowHead.line(to: NSPoint(x: arrowTipX - arrowHeadWidth, y: arrowY + arrowHeadHeight))
arrowHead.line(to: NSPoint(x: arrowTipX - arrowHeadWidth, y: arrowY - arrowHeadHeight))
arrowHead.close()
blue.setFill()
arrowHead.fill()

let advisoryStyle = NSMutableParagraphStyle()
advisoryStyle.alignment = .center
advisoryStyle.lineSpacing = 2
drawCentered(
    "First launch: if macOS blocks JazzSON, go to System Settings > Privacy & Security, click Open Anyway, then confirm.",
    in: NSRect(x: 58, y: 50, width: 524, height: 52),
    font: .systemFont(ofSize: 12, weight: .regular),
    color: NSColor(calibratedWhite: 0.22, alpha: 1),
    paragraphStyle: advisoryStyle
)

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    fputs("Could not render background PNG.\n", stderr)
    exit(1)
}

try png.write(to: outputURL)
