//
//  GestureGlyph.swift
//  Touch Up
//
//  The gesture pictures: a display with an abstract desktop on it (menu bar, wallpaper, windows, Dock), the fingers as
//  dots that land on the glass, do the gesture and lift, in a loop, and arrows as a quiet hint of the direction. What is on
//  the screen answers the fingers in step with them: a button presses, a menu opens, a page scrolls, windows spread out.
//
//  The fingers, their keyframes and timing come from the T650Native project's pictures
//  (native/SettingsApp/Sources/T650Settings/GestureGlyph.swift), so the two settings windows move alike; the pad is replaced
//  by a display, since a touchscreen is touched where things are. Reduce Motion gets the still picture.
//

import SwiftUI

struct Glyph: Equatable {
    // As the catalog names them.
    enum Motion: String { case tap, double, hold, doublehold, horizontal, vertical, up, down, edge, rotate, zoom, pinch, spread }
    enum Corner: String { case left, right }
    enum ScrollBar: String { case natural, standard }

    /// What the screen shows the gesture doing.
    enum Scene: String {
        case desktop, click, contextMenu, lookUp, drag, scroll, zoom, smartZoom, rotate, notificationCenter, pages, spaces,
             missionControl, appExpose, launchpad, showDesktop
    }

    var fingers: Int
    var motion: Motion
    var scene: Scene = .desktop
    var corner: Corner? = nil
    /// A second set of fingers taking turns with the first ("two or three-finger swipe", the scroll's up then down).
    var alt: Int? = nil
    var altReverse = false
    /// The scroll direction: whether the content goes with the fingers or against them.
    var scrollBar: ScrollBar? = nil

    /// The idle desktop: a gesture that is off.
    static let off = Glyph(fingers: 0, motion: .tap)
}

struct GestureGlyphView: View {
    let glyph: Glyph
    /// What VoiceOver says for the idle desktop (the catalog's Off).
    let offLabel: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            Canvas { context, size in
                let time = reduceMotion ? nil : timeline.date.timeIntervalSinceReferenceDate
                GlyphPainter(glyph: glyph, time: time).draw(in: &context, size: size)
            }
        }
        .aspectRatio(glyphWidth / glyphHeight, contentMode: .fit)
        .accessibilityLabel(glyph == .off ? offLabel : "\(glyph.fingers)-finger \(String(describing: glyph.motion))")
    }
}

// -- geometry ---------------------------------------------------------------------------------------

private let loop = 2.6                 // one pass of fingers landing, moving and lifting
private let loopLong = loop * 2        // two passes taking turns
// The picture, in its own units.
private let glyphWidth = 120.0
private let glyphHeight = 116.0
// The display: its frame, the glass, and the stand.
private let bezel = CGRect(x: 4, y: 4, width: 112, height: 84)
private let screen = CGRect(x: 8, y: 8, width: 104, height: 76)
private let menuBarHeight = 5.0
private let dockRect = CGRect(x: 36, y: 77, width: 48, height: 5)
// Where the fingers rest: the middle of the screen below the menu bar.
private let center = CGPoint(x: 60, y: 48)
private let cornerPoints: [Glyph.Corner: CGPoint] = [.left: CGPoint(x: 26, y: 72), .right: CGPoint(x: 94, y: 72)]
private let scrollTravel = 24.0
private let hand: [Int: [CGPoint]] = [
    2: [CGPoint(x: -12, y: 10), CGPoint(x: 12, y: -10)],
    4: [CGPoint(x: -20, y: 20), CGPoint(x: -10, y: -4), CGPoint(x: 6, y: -12), CGPoint(x: 22, y: -6)],
]

// The desktop's windows, at rest.
private let windowA = CGRect(x: 14, y: 18, width: 52, height: 38)
private let windowB = CGRect(x: 46, y: 28, width: 56, height: 42)
// A page that fills most of the screen (scrolling, zooming, pages).
private let pageWindow = CGRect(x: 13, y: 16, width: 94, height: 58)

private struct GlyphPainter {
    let glyph: Glyph
    let time: Double?   // nil: the still picture

    private var still: Bool { time == nil }

    private func phase(_ duration: Double) -> Double {
        guard let time else { return 0 }
        return time.truncatingRemainder(dividingBy: duration) / duration
    }

    func draw(in context: inout GraphicsContext, size: CGSize) {
        let scale = min(size.width / glyphWidth, size.height / glyphHeight)
        context.translateBy(x: (size.width - glyphWidth * scale) / 2, y: (size.height - glyphHeight * scale) / 2)
        context.scaleBy(x: scale, y: scale)

        drawDisplay(in: &context)

        var glass = context
        glass.clip(to: Path(roundedRect: screen, cornerRadius: 2))
        ScreenPainter(glyph: glyph, time: time).draw(in: &glass)

        let edge = glyph.motion == .edge
        let origin = glyph.corner.flatMap { cornerPoints[$0] } ?? CGPoint(x: edge ? 98 : center.x, y: center.y)

        if let alt = glyph.alt {
            drawFingers(in: &context, count: glyph.fingers, origin: origin, turn: .first, reverse: false)
            drawFingers(in: &context, count: alt, origin: origin, turn: .second, reverse: glyph.altReverse)
        } else {
            drawFingers(in: &context, count: glyph.fingers, origin: origin, turn: nil, reverse: false)
        }

        drawArrows(in: &context, origin: origin)
    }

    /// The monitor: a dark bezel around the glass, on a stand.
    private func drawDisplay(in context: inout GraphicsContext) {
        let frame = Color(nsColor: .separatorColor)
        let neck = Path(CGRect(x: 54, y: bezel.maxY, width: 12, height: 14))
        context.fill(neck, with: .color(frame.opacity(0.9)))
        let foot = Path(roundedRect: CGRect(x: 38, y: bezel.maxY + 13, width: 44, height: 5), cornerRadius: 2.5)
        context.fill(foot, with: .color(frame))

        let outline = Path(roundedRect: bezel, cornerRadius: 6)
        context.fill(outline, with: .color(Color(white: 0.12)))
        context.stroke(outline, with: .color(frame), lineWidth: 1)
    }

    private enum Turn { case first, second }

    private func drawFingers(in context: inout GraphicsContext, count: Int, origin: CGPoint, turn: Turn?, reverse: Bool) {
        var layer = context
        let motion = glyph.motion
        if motion == .rotate {
            // The pair turns about the middle of the picture, fading in and out.
            let swing = still ? [0.0, 1.0] : Keyframes.swing.sample(phase(loop))
            layer.opacity = swing[1]
            layer.translateBy(x: origin.x, y: origin.y)
            layer.rotate(by: .degrees(swing[0]))
            layer.translateBy(x: -origin.x, y: -origin.y)
        }

        let spacing = count > 2 ? 14.0 : (motion == .rotate ? 40.0 : 18.0)
        let fingerHand = [.spread, .pinch, .zoom].contains(motion) ? hand[count] : nil

        for i in 0..<count {
            var base = CGPoint(x: origin.x + (Double(i) - Double(count - 1) / 2) * spacing, y: origin.y)
            var from = CGPoint.zero
            var to = CGPoint.zero
            if let fingerHand {
                // The finger rests at its place in the hand and moves along the line from the middle of the hand through it.
                let h = fingerHand[i]
                base = CGPoint(x: origin.x + h.x, y: origin.y + h.y)
                let closed = CGPoint(x: h.x * -0.65, y: h.y * -0.65)
                let open = CGPoint(x: h.x * 0.6, y: h.y * 0.6)
                (from, to) = motion == .pinch ? (open, closed) : (closed, open)
            } else if let travel = travel(motion, count: count, gap: spacing, origin: origin) {
                (from, to) = reverse ? (travel.1, travel.0) : travel
            }

            // [progress from `from` to `to`, scale, opacity]
            let finger: [Double]
            var ring: [Double]?   // [scale, opacity]
            if still {
                finger = [0, 1, 1]
                ring = [.tap, .double].contains(motion) ? [1, 0.6] : nil
            } else {
                switch (motion, turn) {
                case (_, .first?): finger = Keyframes.glideFirst.sample(phase(loopLong))
                case (_, .second?): finger = Keyframes.glideSecond.sample(phase(loopLong))
                case (.tap, nil):
                    finger = [0] + Keyframes.touch.sample(phase(loop))
                    ring = Keyframes.ripple.sample(phase(loop))
                case (.double, nil):
                    finger = [0] + Keyframes.touchTwice.sample(phase(loop))
                    ring = Keyframes.rippleTwice.sample(phase(loop))
                case (.zoom, nil): finger = Keyframes.zoomInOut.sample(phase(loop))
                case (.hold, nil): finger = Keyframes.pressAndMove.sample(phase(loop))
                case (.doublehold, nil): finger = Keyframes.doubleTapHoldMove.sample(phase(loop))
                case (.rotate, nil): finger = [0, 1, 1]
                default: finger = Keyframes.glide.sample(phase(loop))
                }
            }

            if let ring {
                let radius = 10 * ring[0]
                let circle = Path(ellipseIn: CGRect(x: base.x - radius, y: base.y - radius, width: radius * 2, height: radius * 2))
                layer.stroke(circle, with: .color(.white.opacity(ring[1])), lineWidth: 2)
            }

            let point = CGPoint(x: base.x + from.x + (to.x - from.x) * finger[0], y: base.y + from.y + (to.y - from.y) * finger[0])
            let radius = ([.hold, .doublehold].contains(motion) ? 7.0 : 5.0) * finger[1]
            let dot = Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
            // A fingertip on the glass: the accent colour with a light rim, so it reads over any wallpaper.
            layer.fill(dot, with: .color(.accentColor.opacity(finger[2] * 0.9)))
            layer.stroke(dot, with: .color(.white.opacity(finger[2] * 0.9)), lineWidth: 1.2)
        }
    }

    /// Where a moving finger starts and ends, relative to its place.
    private func travel(_ motion: Glyph.Motion, count: Int, gap: Double, origin: CGPoint) -> (CGPoint, CGPoint)? {
        switch motion {
        case .horizontal:
            // From a third of the way in, stopping short enough that the outermost finger stays on the screen.
            let half = Double(count - 1) / 2 * gap
            return (CGPoint(x: max(-18, 22 - (origin.x - half)), y: 0), CGPoint(x: min(30, 98 - (origin.x + half)), y: 0))
        case .vertical, .up: return (CGPoint(x: 0, y: scrollTravel * 0.85), CGPoint(x: 0, y: -scrollTravel * 0.85))
        case .down: return (CGPoint(x: 0, y: -scrollTravel * 0.85), CGPoint(x: 0, y: scrollTravel * 0.85))
        case .edge: return (.zero, CGPoint(x: -52, y: 0))
        case .hold, .doublehold: return (.zero, CGPoint(x: 26, y: 0))
        default: return nil
        }
    }

    /// Each arrow is one shape, its line's outline joined to its head(s), filled once.
    private func drawArrows(in context: inout GraphicsContext, origin: CGPoint) {
        let cx = origin.x
        let cy = origin.y
        let style = GraphicsContext.Shading.color(.white.opacity(still ? 0.9 : 0.55))
        func fill(_ line: Path, width: Double, heads: [Path]) {
            let outline = heads.reduce(line.strokedPath(StrokeStyle(lineWidth: width, lineCap: .round)).cgPath) { $0.union($1.cgPath) }
            // A soft shadow keeps a white arrow visible over a white window.
            context.drawLayer { layer in
                layer.addFilter(.shadow(color: .black.opacity(0.45), radius: 1.2))
                layer.fill(Path(outline), with: style)
            }
        }
        func arrow(_ a: CGPoint, _ b: CGPoint, width: Double = 2.5, head: Double = 7, both: Bool = false) {
            let length = hypot(b.x - a.x, b.y - a.y)
            func along(_ d: Double) -> CGPoint { CGPoint(x: a.x + (b.x - a.x) * d / length, y: a.y + (b.y - a.y) * d / length) }
            var line = Path()
            line.move(to: both ? along(head * headInset) : a)
            line.addLine(to: along(length - head * headInset))
            fill(line, width: width, heads: [arrowHead(at: b, from: a, size: head)] + (both ? [arrowHead(at: a, from: b, size: head)] : []))
        }

        switch glyph.motion {
        case .horizontal: arrow(CGPoint(x: cx - 16, y: 69), CGPoint(x: cx + 28, y: 69))
        case .vertical: arrow(CGPoint(x: 104, y: 66), CGPoint(x: 104, y: 26), both: glyph.altReverse)
        case .up: arrow(CGPoint(x: 104, y: 68), CGPoint(x: 104, y: 24))
        case .down: arrow(CGPoint(x: 104, y: 24), CGPoint(x: 104, y: 68))
        case .edge: arrow(CGPoint(x: 104, y: 70), CGPoint(x: 52, y: 70))
        case .spread, .pinch, .zoom:
            // Along the thumb's and the farthest finger's way: outward for a spread, inward for a pinch, both ways for zoom.
            let points = glyph.fingers == 2 ? [hand[2]![0], hand[2]![1]] : [hand[4]![0], hand[4]![3]]
            for h in points {
                func at(_ k: Double) -> CGPoint { CGPoint(x: cx + h.x * k, y: cy + h.y * k) }
                switch glyph.motion {
                case .zoom: arrow(at(0.9), at(2.6), width: 2, head: 5, both: true)
                case .pinch: arrow(at(1.6), at(0.5))
                default: arrow(at(0.5), at(1.6))
                }
            }
        case .rotate:
            // An arc over the fingers, clockwise over the top.
            let r = 30.0
            let x0 = Double(cx)
            let top = Double(cy) - 14
            let centerY: Double = top + (r * r - 26 * 26).squareRoot()
            let start: Double = atan2(top - centerY, -26.0)
            let end: Double = atan2(top - centerY, 26.0)
            var arc = Path()
            let stop: Double = end - (end > start ? 1 : -1) * 7 * headInset / r
            for step in 0...24 {
                let a: Double = start + (stop - start) * Double(step) / 24
                let p = CGPoint(x: x0 + r * cos(a), y: centerY + r * sin(a))
                if step == 0 { arc.move(to: p) } else { arc.addLine(to: p) }
            }
            let tip = CGPoint(x: x0 + 26, y: top)
            let tangent = CGPoint(x: x0 + 26 + sin(end) * 4, y: top - cos(end) * 4)
            fill(arc, width: 2.5, heads: [arrowHead(at: tip, from: tangent, size: 7)])
        default:
            break
        }
    }

    /// How far inside its head a line ends, as a share of the head's size.
    private let headInset = 0.4

    private func arrowHead(at tip: CGPoint, from: CGPoint, size: Double) -> Path {
        let angle: Double = atan2(Double(tip.y - from.y), Double(tip.x - from.x))
        let (c, s): (Double, Double) = (cos(angle), sin(angle))
        let (cn, sn): (Double, Double) = (cos(angle + Double.pi / 2), sin(angle + Double.pi / 2))
        let point = CGPoint(x: Double(tip.x) + c * size * 0.25, y: Double(tip.y) + s * size * 0.25)
        func corner(_ side: Double) -> CGPoint {
            let x: Double = Double(point.x) - c * size + cn * size * 0.5 * side
            let y: Double = Double(point.y) - s * size + sn * size * 0.5 * side
            return CGPoint(x: x, y: y)
        }
        var head = Path()
        head.move(to: point)
        head.addLine(to: corner(1))
        head.addLine(to: corner(-1))
        head.closeSubpath()
        return head
    }
}


// -- the screen -------------------------------------------------------------------------------------
//
// Everything on the glass. Each scene samples its own keyframes on the same loop as the fingers, timed to the fingers'
// keyframes, so what moves on the screen moves with them.

private struct ScreenPainter {
    let glyph: Glyph
    let time: Double?

    private var still: Bool { time == nil }

    private func phase(_ duration: Double) -> Double {
        guard let time else { return 0 }
        return time.truncatingRemainder(dividingBy: duration) / duration
    }

    /// 0 at rest, 1 when the gesture is done; follows a gliding finger and eases back before the loop starts again.
    private var glide: Double { still ? 0 : Keyframes.screenGlide.sample(phase(loop))[0] }

    private let ink = Color.primary
    private let paper = Color(nsColor: .windowBackgroundColor)

    func draw(in context: inout GraphicsContext) {
        switch glyph.scene {
        case .desktop:
            drawWallpaper(in: &context)
            drawWindows(in: &context)
            drawChrome(in: &context)

        case .click:
            drawWallpaper(in: &context)
            drawWindow(windowA, in: &context)
            let pressed = still ? 0.0 : Keyframes.touch.sample(phase(loop))[1]
            var w = windowB
            w.origin = CGPoint(x: center.x - 26, y: center.y - 18)
            drawWindow(w, in: &context, lines: 2)
            let button = CGRect(x: center.x - 11, y: center.y - 4, width: 22, height: 8)
            context.fill(Path(roundedRect: button, cornerRadius: 3), with: .color(.accentColor.opacity(0.35 + 0.65 * pressed)))
            context.fill(Path(roundedRect: button.insetBy(dx: 6, dy: 3), cornerRadius: 1), with: .color(.white.opacity(0.8)))
            drawChrome(in: &context)

        case .contextMenu:
            drawWallpaper(in: &context)
            drawWindows(in: &context)
            drawChrome(in: &context)
            let shown = still ? 1.0 : Keyframes.menu.sample(phase(loop))[0]
            drawMenu(CGRect(x: center.x + 6, y: center.y - 22, width: 32, height: 34), rows: 5, opacity: shown, in: &context)

        case .lookUp:
            drawWallpaper(in: &context)
            drawPage(pageWindow, offset: .zero, in: &context)
            drawChrome(in: &context)
            let shown = still ? 1.0 : Keyframes.menu.sample(phase(loop))[0]
            // The word under the fingers is picked out, and its definition pops up above it.
            context.fill(Path(roundedRect: CGRect(x: center.x - 14, y: center.y - 2, width: 28, height: 5), cornerRadius: 1.5),
                         with: .color(.yellow.opacity(0.7 * shown)))
            drawPopover(CGRect(x: center.x - 28, y: 15, width: 56, height: 22), pointingAt: CGPoint(x: center.x, y: center.y - 3),
                        opacity: shown, in: &context)

        case .drag:
            drawWallpaper(in: &context)
            drawWindow(CGRect(x: 14, y: 18, width: 40, height: 30), in: &context, lines: 3)
            drawChrome(in: &context)
            // A folder to drop onto, and the file the finger carries to it.
            drawFolder(at: CGPoint(x: center.x + 32, y: center.y), in: &context)
            let p = still ? 0.0 : Keyframes.pressAndMove.sample(phase(loop))[0] * Keyframes.returnAtEnd.sample(phase(loop))[0]
            drawFile(at: CGPoint(x: center.x + 26 * p, y: center.y), lifted: p > 0.01, in: &context, scale: 1.7)

        case .scroll:
            drawWallpaper(in: &context)
            // Natural: the content goes with the fingers, so it stays under them; standard: the other way.
            let along = still ? 0.0 : Keyframes.scroll.sample(phase(loopLong))[0]
            let sign = glyph.scrollBar == .standard ? 1.0 : -1.0
            drawPage(pageWindow, offset: CGSize(width: 0, height: sign * along * scrollTravel * 1.7), scrollBar: along, in: &context)
            drawChrome(in: &context)

        case .zoom:
            drawWallpaper(in: &context)
            let p = still ? 0.0 : Keyframes.zoomInOut.sample(phase(loop))[0]
            drawPage(pageWindow, offset: .zero, zoom: 1 + 0.6 * p, in: &context)
            drawChrome(in: &context)

        case .smartZoom:
            drawWallpaper(in: &context)
            let zoom = still ? 1.0 : Keyframes.smartZoom.sample(phase(loop))[0]
            drawPage(pageWindow, offset: .zero, zoom: zoom, in: &context)
            drawChrome(in: &context)

        case .rotate:
            drawWallpaper(in: &context)
            drawWindow(CGRect(x: 14, y: 16, width: 92, height: 58), in: &context, lines: 0)
            let degrees = still ? 0.0 : Keyframes.photo.sample(phase(loop))[0]
            drawPhoto(at: center, degrees: degrees, in: &context)
            drawChrome(in: &context)

        case .notificationCenter:
            drawWallpaper(in: &context)
            drawWindows(in: &context)
            drawChrome(in: &context)
            drawNotificationCenter(shown: glide, in: &context)

        case .pages:
            drawWallpaper(in: &context)
            // The fingers move right: the previous page comes in from the left. Two turns go back two pages.
            let p: Double
            if still {
                p = 0
            } else if glyph.alt != nil {
                p = Keyframes.glideFirst.sample(phase(loopLong))[0] + Keyframes.glideSecond.sample(phase(loopLong))[0]
            } else {
                p = Keyframes.glide.sample(phase(loop))[0]
            }
            drawBrowser(pageWindow, slide: p, in: &context)
            drawChrome(in: &context)

        case .spaces:
            // The whole desktop slides: the one to the left comes in.
            let shift = glide * screen.width
            var left = context
            left.translateBy(x: shift - screen.width, y: 0)
            drawWallpaper(in: &left, hue: 0.08)
            drawWindow(CGRect(x: 20, y: 18, width: 80, height: 54), in: &left, lines: 6)
            var current = context
            current.translateBy(x: shift, y: 0)
            drawWallpaper(in: &current)
            drawWindows(in: &current)
            drawChrome(in: &context)

        case .missionControl:
            drawWallpaper(in: &context)
            context.fill(Path(screen), with: .color(.black.opacity(0.35 * glide)))
            // The windows shrink into a row of tiles; the Spaces bar comes down from the top.
            let tiles = [CGRect(x: 18, y: 38, width: 38, height: 28), CGRect(x: 64, y: 38, width: 38, height: 28)]
            for (window, tile) in zip([windowA, windowB], tiles) {
                drawWindow(lerp(window, tile, glide), in: &context, lines: 3)
            }
            for i in 0..<3 {
                let thumb = CGRect(x: 30 + Double(i) * 22, y: 10 + 12 * (glide - 1), width: 18, height: 10)
                context.fill(Path(roundedRect: thumb, cornerRadius: 1.5), with: .color(Color(hue: 0.58 + 0.06 * Double(i), saturation: 0.45, brightness: 0.85).opacity(glide)))
                context.stroke(Path(roundedRect: thumb, cornerRadius: 1.5), with: .color(.white.opacity((i == 1 ? 0.9 : 0.3) * glide)), lineWidth: 0.8)
            }
            drawDock(in: &context, opacity: 1 - glide)

        case .appExpose:
            drawWallpaper(in: &context)
            context.fill(Path(screen), with: .color(.black.opacity(0.35 * glide)))
            // The app's windows line up across the screen; the other app's window steps back.
            drawWindow(windowA, in: &context, opacity: 1 - glide)
            let row = [CGRect(x: 14, y: 22, width: 28, height: 22), CGRect(x: 46, y: 22, width: 28, height: 22), CGRect(x: 78, y: 22, width: 28, height: 22)]
            let rest = [windowB, windowB.offsetBy(dx: -6, dy: -4), windowB.offsetBy(dx: -12, dy: -8)]
            for (i, (from, to)) in zip(rest, row).enumerated().reversed() {
                drawWindow(lerp(from, to, glide), in: &context, lines: 2, opacity: i == 0 ? 1 : glide)
            }
            drawMenuBar(in: &context)
            drawDock(in: &context)

        case .launchpad:
            drawWallpaper(in: &context)
            drawWindows(in: &context, opacity: 1 - glide)
            context.fill(Path(screen), with: .color(.black.opacity(0.3 * glide)))
            // The app grid appears as the fingers close.
            let size = 9.0 * (0.8 + 0.2 * glide)
            for row in 0..<3 {
                for column in 0..<5 {
                    let c = CGPoint(x: 24 + Double(column) * 18, y: 26 + Double(row) * 17)
                    let icon = CGRect(x: c.x - size / 2, y: c.y - size / 2, width: size, height: size)
                    let hue = Double((row * 5 + column) % 7) / 7
                    context.fill(Path(roundedRect: icon, cornerRadius: 2.5),
                                 with: .color(Color(hue: hue, saturation: 0.55, brightness: 0.95).opacity(glide)))
                }
            }
            drawChrome(in: &context, dockOpacity: 1 - glide)

        case .showDesktop:
            drawWallpaper(in: &context)
            // The windows move off to the edges, showing the desktop.
            drawWindow(windowA.offsetBy(dx: -48 * glide, dy: -18 * glide), in: &context)
            drawWindow(windowB.offsetBy(dx: 52 * glide, dy: 20 * glide), in: &context)
            for i in 0..<2 {
                drawFile(at: CGPoint(x: 96, y: 24 + Double(i) * 16), lifted: false, in: &context, opacity: glide)
            }
            drawChrome(in: &context)
        }
    }

    // -- pieces of the desktop

    private func drawWallpaper(in context: inout GraphicsContext, hue: Double = 0.6) {
        let gradient = Gradient(colors: [
            Color(hue: hue, saturation: 0.55, brightness: 0.75),
            Color(hue: hue + 0.12, saturation: 0.45, brightness: 0.95),
        ])
        context.fill(Path(screen), with: .linearGradient(gradient, startPoint: CGPoint(x: screen.minX, y: screen.minY),
                                                          endPoint: CGPoint(x: screen.maxX, y: screen.maxY)))
    }

    private func drawChrome(in context: inout GraphicsContext, dockOpacity: Double = 1) {
        drawMenuBar(in: &context)
        drawDock(in: &context, opacity: dockOpacity)
    }

    private func drawMenuBar(in context: inout GraphicsContext) {
        context.fill(Path(CGRect(x: screen.minX, y: screen.minY, width: screen.width, height: menuBarHeight)), with: .color(.white.opacity(0.55)))
        for (i, w) in [4.0, 6, 5, 7].enumerated() {
            let x = screen.minX + 4 + Double(i) * 9
            context.fill(Path(roundedRect: CGRect(x: x, y: screen.minY + 1.8, width: w, height: 1.4), cornerRadius: 0.7),
                         with: .color(.black.opacity(0.45)))
        }
        context.fill(Path(roundedRect: CGRect(x: screen.maxX - 14, y: screen.minY + 1.8, width: 10, height: 1.4), cornerRadius: 0.7),
                     with: .color(.black.opacity(0.45)))
    }

    private func drawDock(in context: inout GraphicsContext, opacity: Double = 1) {
        guard opacity > 0.01 else { return }
        context.fill(Path(roundedRect: dockRect, cornerRadius: 2.5), with: .color(.white.opacity(0.4 * opacity)))
        for i in 0..<6 {
            let icon = CGRect(x: dockRect.minX + 3 + Double(i) * 7.2, y: dockRect.minY + 0.8, width: 3.4, height: 3.4)
            context.fill(Path(roundedRect: icon, cornerRadius: 1),
                         with: .color(Color(hue: Double(i) / 6, saturation: 0.6, brightness: 0.95).opacity(opacity)))
        }
    }

    private func drawWindows(in context: inout GraphicsContext, opacity: Double = 1) {
        drawWindow(windowA, in: &context, opacity: opacity)
        drawWindow(windowB, in: &context, opacity: opacity)
    }

    /// A window: a light rectangle with a title bar, its three buttons and some lines of text.
    private func drawWindow(_ rect: CGRect, in context: inout GraphicsContext, lines: Int = 4, opacity: Double = 1) {
        guard opacity > 0.01 else { return }
        var layer = context
        layer.opacity = opacity
        let shape = Path(roundedRect: rect, cornerRadius: 2.5)
        layer.drawLayer { shadow in
            shadow.addFilter(.shadow(color: .black.opacity(0.25), radius: 1.5, y: 0.8))
            shadow.fill(shape, with: .color(paper))
        }
        layer.stroke(shape, with: .color(.black.opacity(0.15)), lineWidth: 0.5)
        let bar = min(5, rect.height * 0.18)
        for (i, color) in [Color.red, .yellow, .green].enumerated() {
            let r = bar * 0.22
            let c = CGPoint(x: rect.minX + 3 + Double(i) * r * 3, y: rect.minY + bar / 2)
            layer.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .color(color.opacity(0.8)))
        }
        guard lines > 0 else { return }
        let gap = (rect.height - bar - 3) / Double(max(lines, 1))
        for i in 0..<lines {
            let y = rect.minY + bar + 3 + Double(i) * gap
            let width = (rect.width - 8) * [0.9, 0.7, 0.8, 0.55, 0.75, 0.6][i % 6]
            layer.fill(Path(roundedRect: CGRect(x: rect.minX + 4, y: y, width: width, height: min(2, gap * 0.45)), cornerRadius: 1),
                       with: .color(ink.opacity(0.25)))
        }
    }

    /// A page of text with a picture, in a window: moved by `offset`, magnified by `zoom` about the fingers.
    private func drawPage(_ rect: CGRect, offset: CGSize, zoom: Double = 1, scrollBar: Double? = nil, in context: inout GraphicsContext) {
        drawWindow(rect, in: &context, lines: 0)
        var content = context
        let inner = CGRect(x: rect.minX + 2, y: rect.minY + 6, width: rect.width - 4, height: rect.height - 8)
        content.clip(to: Path(inner))
        content.translateBy(x: center.x, y: center.y)
        content.scaleBy(x: zoom, y: zoom)
        content.translateBy(x: -center.x + offset.width, y: -center.y + offset.height)

        var y = inner.minY - 40
        var i = 0
        while y < inner.maxY + 50 {
            if i % 6 == 2 {
                let picture = CGRect(x: inner.minX + 6, y: y, width: 34, height: 14)
                content.fill(Path(roundedRect: picture, cornerRadius: 1.5),
                             with: .linearGradient(Gradient(colors: [Color(hue: 0.08, saturation: 0.5, brightness: 0.95), Color(hue: 0.95, saturation: 0.4, brightness: 0.85)]),
                                                   startPoint: picture.origin, endPoint: CGPoint(x: picture.maxX, y: picture.maxY)))
                y += 18
            } else {
                let width = (inner.width - 14) * [0.95, 0.8, 0.9, 0.7, 0.85][i % 5]
                content.fill(Path(roundedRect: CGRect(x: inner.minX + 6, y: y, width: width, height: 2), cornerRadius: 1),
                             with: .color(ink.opacity(0.28)))
                y += 5.5
            }
            i += 1
        }

        if let scrollBar {
            let track = CGRect(x: inner.maxX - 3, y: inner.minY + 1, width: 1.6, height: inner.height - 2)
            let thumbHeight = track.height * 0.35
            let thumbY = track.minY + (track.height - thumbHeight) * (glyph.scrollBar == .standard ? 1 - scrollBar : scrollBar)
            context.fill(Path(roundedRect: CGRect(x: track.minX, y: thumbY, width: track.width, height: thumbHeight), cornerRadius: 0.8),
                         with: .color(ink.opacity(0.45)))
        }
    }

    /// A browser window whose pages slide sideways: `slide` 1 is one page back.
    private func drawBrowser(_ rect: CGRect, slide: Double, in context: inout GraphicsContext) {
        drawWindow(rect, in: &context, lines: 0)
        let address = CGRect(x: rect.minX + 18, y: rect.minY + 1.2, width: rect.width - 30, height: 2.6)
        context.fill(Path(roundedRect: address, cornerRadius: 1.3), with: .color(ink.opacity(0.12)))
        var content = context
        let inner = CGRect(x: rect.minX + 2, y: rect.minY + 6, width: rect.width - 4, height: rect.height - 8)
        content.clip(to: Path(inner))
        // Pages look alike, so the loop starting again (two pages back to none) does not show.
        for page in -1...3 {
            let x = inner.minX + (Double(page) * -1 + slide) * inner.width
            let hero = CGRect(x: x + 6, y: inner.minY + 4, width: inner.width - 12, height: 16)
            content.fill(Path(roundedRect: hero, cornerRadius: 1.5), with: .color(Color(hue: 0.58, saturation: 0.35, brightness: 0.9)))
            for row in 0..<5 {
                content.fill(Path(roundedRect: CGRect(x: x + 6, y: inner.minY + 24 + Double(row) * 5.5, width: (inner.width - 12) * [0.9, 0.7, 0.85, 0.6, 0.8][row], height: 2), cornerRadius: 1),
                             with: .color(ink.opacity(0.28)))
            }
        }
    }

    private func drawMenu(_ rect: CGRect, rows: Int, opacity: Double, in context: inout GraphicsContext) {
        guard opacity > 0.01 else { return }
        var layer = context
        layer.opacity = opacity
        let shape = Path(roundedRect: rect, cornerRadius: 2.5)
        layer.drawLayer { shadow in
            shadow.addFilter(.shadow(color: .black.opacity(0.35), radius: 2, y: 1))
            shadow.fill(shape, with: .color(paper))
        }
        let rowHeight = (rect.height - 4) / Double(rows)
        for i in 0..<rows {
            let y = rect.minY + 2 + Double(i) * rowHeight
            if i == 1 {
                layer.fill(Path(roundedRect: CGRect(x: rect.minX + 1.5, y: y, width: rect.width - 3, height: rowHeight), cornerRadius: 1.5),
                           with: .color(.accentColor.opacity(0.85)))
            }
            layer.fill(Path(roundedRect: CGRect(x: rect.minX + 4, y: y + rowHeight / 2 - 0.8, width: rect.width * [0.6, 0.5, 0.7, 0.45, 0.55][i % 5], height: 1.6), cornerRadius: 0.8),
                       with: .color(i == 1 ? .white : ink.opacity(0.45)))
        }
    }

    private func drawPopover(_ rect: CGRect, pointingAt tip: CGPoint, opacity: Double, in context: inout GraphicsContext) {
        guard opacity > 0.01 else { return }
        var layer = context
        layer.opacity = opacity
        var shape = Path(roundedRect: rect, cornerRadius: 3)
        shape.move(to: CGPoint(x: tip.x - 4, y: rect.maxY))
        shape.addLine(to: CGPoint(x: tip.x, y: rect.maxY + 4))
        shape.addLine(to: CGPoint(x: tip.x + 4, y: rect.maxY))
        layer.drawLayer { shadow in
            shadow.addFilter(.shadow(color: .black.opacity(0.35), radius: 2, y: 1))
            shadow.fill(shape, with: .color(paper))
        }
        layer.fill(Path(roundedRect: CGRect(x: rect.minX + 4, y: rect.minY + 3, width: 20, height: 2.4), cornerRadius: 1.2), with: .color(ink.opacity(0.6)))
        for i in 0..<3 {
            layer.fill(Path(roundedRect: CGRect(x: rect.minX + 4, y: rect.minY + 8 + Double(i) * 4, width: (rect.width - 8) * [0.9, 0.75, 0.5][i], height: 1.6), cornerRadius: 0.8),
                       with: .color(ink.opacity(0.3)))
        }
    }

    private func drawFolder(at c: CGPoint, in context: inout GraphicsContext) {
        let body = CGRect(x: c.x - 8, y: c.y - 5, width: 16, height: 11)
        let tab = CGRect(x: c.x - 8, y: c.y - 7, width: 7, height: 3)
        let blue = Color(hue: 0.57, saturation: 0.55, brightness: 0.95)
        context.fill(Path(roundedRect: tab, cornerRadius: 1), with: .color(blue))
        context.fill(Path(roundedRect: body, cornerRadius: 1.5), with: .color(blue))
    }

    private func drawFile(at c: CGPoint, lifted: Bool, in context: inout GraphicsContext, opacity: Double = 1, scale: Double = 1) {
        guard opacity > 0.01 else { return }
        var layer = context
        layer.opacity = opacity
        layer.translateBy(x: c.x, y: c.y)
        layer.scaleBy(x: scale, y: scale)
        let rect = CGRect(x: -5, y: -6.5, width: 10, height: 13)
        var page = Path()
        page.move(to: CGPoint(x: rect.minX, y: rect.minY))
        page.addLine(to: CGPoint(x: rect.maxX - 3, y: rect.minY))
        page.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + 3))
        page.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        page.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        page.closeSubpath()
        layer.drawLayer { shadow in
            shadow.addFilter(.shadow(color: .black.opacity(lifted ? 0.45 : 0.2), radius: lifted ? 2.5 : 1, y: lifted ? 1.5 : 0.5))
            shadow.fill(page, with: .color(.white))
        }
        for i in 0..<3 {
            layer.fill(Path(CGRect(x: rect.minX + 2, y: rect.minY + 4 + Double(i) * 2.5, width: 6, height: 1)), with: .color(.black.opacity(0.3)))
        }
    }

    private func drawPhoto(at c: CGPoint, degrees: Double, in context: inout GraphicsContext) {
        var layer = context
        layer.translateBy(x: c.x, y: c.y)
        layer.rotate(by: .degrees(degrees))
        let frame = CGRect(x: -22, y: -15, width: 44, height: 30)
        layer.drawLayer { shadow in
            shadow.addFilter(.shadow(color: .black.opacity(0.3), radius: 1.5, y: 0.8))
            shadow.fill(Path(frame), with: .color(.white))
        }
        let picture = frame.insetBy(dx: 2, dy: 2)
        layer.fill(Path(picture), with: .linearGradient(Gradient(colors: [Color(hue: 0.55, saturation: 0.5, brightness: 0.95), Color(hue: 0.12, saturation: 0.6, brightness: 0.95)]),
                                                         startPoint: CGPoint(x: 0, y: picture.minY), endPoint: CGPoint(x: 0, y: picture.maxY)))
        var hills = Path()
        hills.move(to: CGPoint(x: picture.minX, y: picture.maxY))
        hills.addLine(to: CGPoint(x: picture.minX + 12, y: picture.minY + 12))
        hills.addLine(to: CGPoint(x: picture.minX + 22, y: picture.minY + 18))
        hills.addLine(to: CGPoint(x: picture.minX + 30, y: picture.minY + 10))
        hills.addLine(to: CGPoint(x: picture.maxX, y: picture.maxY))
        hills.closeSubpath()
        layer.fill(hills, with: .color(Color(hue: 0.35, saturation: 0.5, brightness: 0.6)))
        layer.fill(Path(ellipseIn: CGRect(x: picture.maxX - 10, y: picture.minY + 3, width: 6, height: 6)), with: .color(.yellow.opacity(0.9)))
    }

    private func drawNotificationCenter(shown: Double, in context: inout GraphicsContext) {
        guard shown > 0.01 else { return }
        let width = 36.0
        let x = screen.maxX - width * shown
        let panel = CGRect(x: x, y: screen.minY + menuBarHeight, width: width, height: screen.height - menuBarHeight)
        context.fill(Path(panel), with: .color(.black.opacity(0.25 * shown)))
        for i in 0..<3 {
            let card = CGRect(x: x + 3, y: panel.minY + 4 + Double(i) * 15, width: width - 6, height: 12)
            context.fill(Path(roundedRect: card, cornerRadius: 2.5), with: .color(.white.opacity(0.85)))
            context.fill(Path(roundedRect: CGRect(x: card.minX + 2, y: card.minY + 2, width: 5, height: 5), cornerRadius: 1.2),
                         with: .color(Color(hue: Double(i) * 0.3, saturation: 0.6, brightness: 0.95)))
            context.fill(Path(roundedRect: CGRect(x: card.minX + 9, y: card.minY + 3, width: card.width - 12, height: 1.6), cornerRadius: 0.8),
                         with: .color(.black.opacity(0.45)))
            context.fill(Path(roundedRect: CGRect(x: card.minX + 9, y: card.minY + 7, width: card.width - 16, height: 1.4), cornerRadius: 0.7),
                         with: .color(.black.opacity(0.25)))
        }
    }

    private func lerp(_ a: CGRect, _ b: CGRect, _ t: Double) -> CGRect {
        CGRect(x: a.minX + (b.minX - a.minX) * t, y: a.minY + (b.minY - a.minY) * t,
               width: a.width + (b.width - a.width) * t, height: a.height + (b.height - a.height) * t)
    }
}


// -- keyframes ---------------------------------------------------------------------------------------
//
// Each is a list of (time 0-1, values), eased between keys with CSS's ease-in-out. The fingers' keyframes are T650Native's;
// the screen's are timed to them.

private struct Keyframes {
    let keys: [(Double, [Double])]

    func sample(_ t: Double) -> [Double] {
        guard let next = keys.firstIndex(where: { $0.0 >= t }), next > 0 else { return keys.first!.1 }
        let (t0, v0) = keys[next - 1]
        let (t1, v1) = keys[next]
        let f = t1 > t0 ? easeInOut((t - t0) / (t1 - t0)) : 1
        return zip(v0, v1).map { $0 + ($1 - $0) * f }
    }

    // cubic-bezier(0.42, 0, 0.58, 1): find the curve's x for t by Newton's method, then its y.
    private func easeInOut(_ x: Double) -> Double {
        func bezier(_ t: Double, _ p1: Double, _ p2: Double) -> Double {
            let u = 1 - t
            return 3 * u * u * t * p1 + 3 * u * t * t * p2 + t * t * t
        }

        var t = x
        for _ in 0..<8 {
            let dx = bezier(t, 0.42, 0.58) - x
            let slope = 3 * (1 - t) * (1 - t) * 0.42 + 6 * (1 - t) * t * (0.58 - 0.42) + 3 * t * t * (1 - 0.58)
            if abs(dx) < 1e-5 || slope == 0 { break }
            t = min(1, max(0, t - dx / slope))
        }

        return bezier(t, 0, 1)
    }

    // The fingers. [progress, scale, opacity]
    static let glide = Keyframes(keys: [(0, [0, 0.6, 0]), (0.12, [0, 1, 1]), (0.68, [1, 1, 1]), (0.82, [1, 1, 1]), (0.96, [1, 0.6, 0]), (1, [1, 0.6, 0])])
    static let zoomInOut = Keyframes(keys: [(0, [0, 0.6, 0]), (0.10, [0, 1, 1]), (0.42, [1, 1, 1]), (0.52, [1, 1, 1]), (0.84, [0, 1, 1]), (0.96, [0, 0.6, 0]), (1, [0, 0.6, 0])])
    static let doubleTapHoldMove = Keyframes(keys: [
        (0, [0, 0.5, 0]), (0.04, [0, 1, 1]), (0.11, [0, 0.85, 1]), (0.16, [0, 0.5, 0]), (0.24, [0, 0.5, 0]), (0.30, [0, 1, 1]),
        (0.42, [0, 1.35, 1]), (0.52, [0, 1.35, 1]), (0.78, [1, 1.35, 1]), (0.88, [1, 1.35, 1]), (1, [1, 0.6, 0]),
    ])
    static let glideFirst = Keyframes(keys: [(0, [0, 0.6, 0]), (0.06, [0, 1, 1]), (0.34, [1, 1, 1]), (0.40, [1, 1, 1]), (0.48, [1, 0.6, 0]), (1, [1, 0.6, 0])])
    static let glideSecond = Keyframes(keys: [(0, [0, 0.6, 0]), (0.50, [0, 0.6, 0]), (0.56, [0, 1, 1]), (0.84, [1, 1, 1]), (0.90, [1, 1, 1]), (0.98, [1, 0.6, 0]), (1, [1, 0.6, 0])])
    static let pressAndMove = Keyframes(keys: [(0, [0, 0.5, 0]), (0.10, [0, 1, 1]), (0.30, [0, 1.35, 1]), (0.48, [0, 1.35, 1]), (0.78, [1, 1.35, 1]), (0.88, [1, 1.35, 1]), (1, [1, 0.6, 0])])

    // [scale, opacity]
    static let touch = Keyframes(keys: [(0, [0.5, 0]), (0.10, [1, 1]), (0.30, [0.85, 1]), (0.45, [0.5, 0]), (1, [0.5, 0])])
    static let ripple = Keyframes(keys: [(0, [0.6, 0]), (0.08, [0.6, 0]), (0.14, [0.7, 0.8]), (0.45, [1.5, 0]), (1, [1.5, 0])])
    static let touchTwice = Keyframes(keys: [
        (0, [0.5, 0]), (0.06, [1, 1]), (0.16, [0.85, 1]), (0.24, [0.5, 0]), (0.32, [0.5, 0]), (0.38, [1, 1]), (0.48, [0.85, 1]),
        (0.56, [0.5, 0]), (1, [0.5, 0]),
    ])
    static let rippleTwice = Keyframes(keys: [
        (0, [0.6, 0]), (0.04, [0.6, 0]), (0.08, [0.7, 0.8]), (0.24, [1.5, 0]), (0.32, [0.6, 0]), (0.36, [0.6, 0]), (0.40, [0.7, 0.8]),
        (0.56, [1.5, 0]), (1, [1.5, 0]),
    ])

    // [degrees, opacity]
    static let swing = Keyframes(keys: [(0, [-35, 0]), (0.14, [-35, 1]), (0.70, [35, 1]), (0.82, [35, 1]), (0.96, [35, 0]), (1, [35, 0])])

    // [how far along: 0 at rest, 1 at the far end] for the scroll, over the long loop
    static let scroll = Keyframes(keys: [(0, [0]), (0.06, [0]), (0.34, [1]), (0.56, [1]), (0.84, [0]), (1, [0])])

    // The screen, timed to the fingers above.
    // [done]: with the gliding fingers (0.12-0.68), held, then eased back before the loop starts again.
    static let screenGlide = Keyframes(keys: [(0, [0]), (0.12, [0]), (0.68, [1]), (0.88, [1]), (1, [0])])
    // [shown]: a menu or popover opening after the tap lifts (0.30-0.45), closing before the next.
    static let menu = Keyframes(keys: [(0, [0]), (0.30, [0]), (0.36, [1]), (0.86, [1]), (0.94, [0]), (1, [0])])
    // [zoom]: in after the second tap (0.48), back out before the loop starts again.
    static let smartZoom = Keyframes(keys: [(0, [1]), (0.46, [1]), (0.58, [1.5]), (0.86, [1.5]), (0.98, [1]), (1, [1])])
    // [degrees]: the photo turns with the fingers' swing (0.14-0.70), from upright, and back before the loop restarts.
    static let photo = Keyframes(keys: [(0, [0]), (0.14, [0]), (0.70, [70]), (0.86, [70]), (1, [0])])
    // [kept]: the dragged file goes back to its place while the finger fades.
    static let returnAtEnd = Keyframes(keys: [(0, [1]), (0.90, [1]), (1, [0])])
}
