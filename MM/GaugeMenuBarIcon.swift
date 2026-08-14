import AppKit
import SwiftUI

/// Animated Phosphor-derived "Gauge" glyph used as the menu bar extra icon.
///
/// The dial geometry is converted offline from the icon's SVG path (256x256
/// viewBox, elliptical arcs pre-converted to cubic curves). The needle is not
/// drawn: it is a 16x152 rounded-bar slot punched through the dial with
/// `.destinationOut`, rotating about the hub at (128, 192) — the same mask
/// trick as the source glyph. Frames are rendered as template NSImages and
/// swapped on a timer, mirroring the source CSS keyframes (lg-needle, 0.94s,
/// looped).
struct GaugeMenuBarIcon: View {
    @StateObject private var driver = GaugeIconDriver()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Image(nsImage: driver.image)
            .accessibilityLabel("MM")
            .onAppear { driver.setPaused(reduceMotion) }
            .onChange(of: reduceMotion) { driver.setPaused($0) }
    }
}

@MainActor
private final class GaugeIconDriver: ObservableObject {
    @Published var image = GaugeIconRenderer.image(angle: 0)

    private var timer: Timer?
    private var startDate = Date()
    private var paused = false

    func setPaused(_ paused: Bool) {
        guard paused != self.paused || timer == nil else { return }
        self.paused = paused
        timer?.invalidate()
        timer = nil
        guard !paused else {
            image = GaugeIconRenderer.image(angle: 0)
            return
        }
        startDate = Date()
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) {
            [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let t = Date().timeIntervalSince(self.startDate)
                self.image = GaugeIconRenderer.image(
                    angle: GaugeNeedleAnimation.angle(at: t)
                )
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    deinit {
        timer?.invalidate()
    }
}

private enum GaugeIconRenderer {
    static let size = NSSize(width: 18, height: 18)

    static func image(angle: Double) -> NSImage {
        let image = NSImage(size: size, flipped: false) { rect in
            let scale = rect.width / 256
            // Flip to SVG's top-left origin, then draw in 256x256 viewBox units.
            var toSVGSpace = AffineTransform()
            toSVGSpace.translate(x: 0, y: rect.height)
            toSVGSpace.scale(x: scale, y: -scale)
            (toSVGSpace as NSAffineTransform).concat()

            NSColor.black.setFill()
            dial.fill()

            var rotate = AffineTransform()
            rotate.translate(x: 128, y: 192)
            rotate.rotate(byDegrees: angle)
            rotate.translate(x: -128, y: -192)
            let slot = needle.copy() as! NSBezierPath
            slot.transform(using: rotate)
            NSGraphicsContext.current?.compositingOperation = .destinationOut
            slot.fill()

            return true
        }
        image.isTemplate = true
        return image
    }

    /// Phosphor Gauge dial, 256x256 viewBox (SVG arcs expanded to cubics).
    private static let dial: NSBezierPath = {
        let p = NSBezierPath()
        p.move(to: NSPoint(x: 240, y: 152))
        p.line(to: NSPoint(x: 240, y: 176))
        p.curve(to: NSPoint(x: 224, y: 192), controlPoint1: NSPoint(x: 240, y: 184.84), controlPoint2: NSPoint(x: 232.84, y: 192))
        p.line(to: NSPoint(x: 32, y: 192))
        p.curve(to: NSPoint(x: 16, y: 176), controlPoint1: NSPoint(x: 23.16, y: 192), controlPoint2: NSPoint(x: 16, y: 184.84))
        p.line(to: NSPoint(x: 16, y: 153.13))
        p.curve(to: NSPoint(x: 16.13, y: 147.8), controlPoint1: NSPoint(x: 16, y: 151.34), controlPoint2: NSPoint(x: 16, y: 149.56))
        p.curve(to: NSPoint(x: 20.13, y: 144), controlPoint1: NSPoint(x: 16.24, y: 145.67), controlPoint2: NSPoint(x: 18, y: 144))
        p.line(to: NSPoint(x: 48, y: 144))
        p.curve(to: NSPoint(x: 53.85, y: 141.47), controlPoint1: NSPoint(x: 50.22, y: 144), controlPoint2: NSPoint(x: 52.34, y: 143.09))
        p.curve(to: NSPoint(x: 56, y: 135.47), controlPoint1: NSPoint(x: 55.37, y: 139.86), controlPoint2: NSPoint(x: 56.15, y: 137.68))
        p.curve(to: NSPoint(x: 47.73, y: 128), controlPoint1: NSPoint(x: 55.63, y: 131.19), controlPoint2: NSPoint(x: 52.02, y: 127.93))
        p.line(to: NSPoint(x: 23.92, y: 128))
        p.curve(to: NSPoint(x: 20.76, y: 126.45), controlPoint1: NSPoint(x: 22.68, y: 128), controlPoint2: NSPoint(x: 21.52, y: 127.43))
        p.curve(to: NSPoint(x: 20.05, y: 123), controlPoint1: NSPoint(x: 20, y: 125.47), controlPoint2: NSPoint(x: 19.74, y: 124.2))
        p.curve(to: NSPoint(x: 115.57, y: 40.72), controlPoint1: NSPoint(x: 32.05, y: 79.16), controlPoint2: NSPoint(x: 69.71, y: 45.87))
        p.curve(to: NSPoint(x: 118.68, y: 41.73), controlPoint1: NSPoint(x: 116.7, y: 40.6), controlPoint2: NSPoint(x: 117.83, y: 40.96))
        p.curve(to: NSPoint(x: 120, y: 44.72), controlPoint1: NSPoint(x: 119.53, y: 42.49), controlPoint2: NSPoint(x: 120.01, y: 43.58))
        p.line(to: NSPoint(x: 120, y: 72))
        p.curve(to: NSPoint(x: 122.53, y: 77.85), controlPoint1: NSPoint(x: 120, y: 74.22), controlPoint2: NSPoint(x: 120.91, y: 76.34))
        p.curve(to: NSPoint(x: 128.53, y: 80), controlPoint1: NSPoint(x: 124.14, y: 79.37), controlPoint2: NSPoint(x: 126.32, y: 80.15))
        p.curve(to: NSPoint(x: 136, y: 71.73), controlPoint1: NSPoint(x: 132.81, y: 79.63), controlPoint2: NSPoint(x: 136.07, y: 76.02))
        p.line(to: NSPoint(x: 136, y: 44.67))
        p.curve(to: NSPoint(x: 137.32, y: 41.68), controlPoint1: NSPoint(x: 135.99, y: 43.53), controlPoint2: NSPoint(x: 136.47, y: 42.44))
        p.curve(to: NSPoint(x: 140.43, y: 40.67), controlPoint1: NSPoint(x: 138.17, y: 40.91), controlPoint2: NSPoint(x: 139.3, y: 40.55))
        p.curve(to: NSPoint(x: 236.23, y: 123), controlPoint1: NSPoint(x: 186.25, y: 45.82), controlPoint2: NSPoint(x: 224.25, y: 78.48))
        p.curve(to: NSPoint(x: 235.52, y: 126.45), controlPoint1: NSPoint(x: 236.54, y: 124.2), controlPoint2: NSPoint(x: 236.28, y: 125.47))
        p.curve(to: NSPoint(x: 232.35, y: 128), controlPoint1: NSPoint(x: 234.76, y: 127.43), controlPoint2: NSPoint(x: 233.59, y: 128))
        p.line(to: NSPoint(x: 208.27, y: 128))
        p.curve(to: NSPoint(x: 200.02, y: 135.47), controlPoint1: NSPoint(x: 203.99, y: 127.94), controlPoint2: NSPoint(x: 200.39, y: 131.2))
        p.curve(to: NSPoint(x: 202.17, y: 141.47), controlPoint1: NSPoint(x: 199.87, y: 137.68), controlPoint2: NSPoint(x: 200.65, y: 139.86))
        p.curve(to: NSPoint(x: 208.02, y: 144), controlPoint1: NSPoint(x: 203.68, y: 143.09), controlPoint2: NSPoint(x: 205.8, y: 144))
        p.line(to: NSPoint(x: 235.94, y: 144))
        p.curve(to: NSPoint(x: 239.94, y: 147.86), controlPoint1: NSPoint(x: 238.1, y: 144), controlPoint2: NSPoint(x: 239.86, y: 145.71))
        p.curve(to: NSPoint(x: 240, y: 152), controlPoint1: NSPoint(x: 240, y: 149.23), controlPoint2: NSPoint(x: 240, y: 150.61))
        p.close()
        return p
    }()

    /// Needle slot: parked straight up, tail hanging below the hub (128, 192)
    /// so it never detaches mid-sweep; the dial clips the overhang.
    private static let needle = NSBezierPath(
        roundedRect: NSRect(x: 120, y: 88, width: 16, height: 152),
        xRadius: 8,
        yRadius: 8
    )
}

private enum GaugeNeedleAnimation {
    static let duration = 0.94

    private struct Segment {
        let fromTime, toTime, fromAngle, toAngle: Double
        let x1, y1, x2, y2: Double
    }

    /// Same segments as the lg-needle CSS keyframes: slam to the left peg,
    /// sweep across with overshoot, ring down onto centre.
    private static let segments: [Segment] = [
        Segment(fromTime: 0.00, toTime: 0.15, fromAngle: 0, toAngle: -56, x1: 0.40, y1: 0, x2: 0.30, y2: 1),
        Segment(fromTime: 0.15, toTime: 0.23, fromAngle: -56, toAngle: -56, x1: 0.45, y1: 0, x2: 0.25, y2: 1),
        Segment(fromTime: 0.23, toTime: 0.52, fromAngle: -56, toAngle: 52, x1: 0.45, y1: 0, x2: 0.25, y2: 1),
        Segment(fromTime: 0.52, toTime: 0.68, fromAngle: 52, toAngle: -24, x1: 0.40, y1: 0, x2: 0.40, y2: 1),
        Segment(fromTime: 0.68, toTime: 0.81, fromAngle: -24, toAngle: 11, x1: 0.40, y1: 0, x2: 0.40, y2: 1),
        Segment(fromTime: 0.81, toTime: 0.91, fromAngle: 11, toAngle: -4, x1: 0.40, y1: 0, x2: 0.40, y2: 1),
        Segment(fromTime: 0.91, toTime: 1.00, fromAngle: -4, toAngle: 0, x1: 0.33, y1: 1, x2: 0.68, y2: 1),
    ]

    static func angle(at time: TimeInterval) -> Double {
        let t = time.truncatingRemainder(dividingBy: duration) / duration
        guard let segment = segments.first(where: { t <= $0.toTime }) else {
            return 0
        }
        let span = segment.toTime - segment.fromTime
        let local = min(max((t - segment.fromTime) / span, 0), 1)
        let eased = cubicBezierEase(
            x: local,
            x1: segment.x1, y1: segment.y1,
            x2: segment.x2, y2: segment.y2
        )
        return segment.fromAngle
            + (segment.toAngle - segment.fromAngle) * eased
    }

    /// y for a given x on cubic-bezier(0,0)-(x1,y1)-(x2,y2)-(1,1),
    /// matching CSS easing (Newton–Raphson with bisection fallback).
    private static func cubicBezierEase(
        x: Double, x1: Double, y1: Double, x2: Double, y2: Double
    ) -> Double {
        let ax = 3 * x1, bx = 3 * (x2 - x1) - ax, cx = 1 - ax - bx
        let ay = 3 * y1, by = 3 * (y2 - y1) - ay, cy = 1 - ay - by
        func sampleX(_ t: Double) -> Double { ((cx * t + bx) * t + ax) * t }
        func sampleY(_ t: Double) -> Double { ((cy * t + by) * t + ay) * t }
        func derivX(_ t: Double) -> Double { (3 * cx * t + 2 * bx) * t + ax }

        var t = x
        for _ in 0 ..< 8 {
            let err = sampleX(t) - x
            if abs(err) < 1e-6 { return sampleY(t) }
            let d = derivX(t)
            if abs(d) < 1e-6 { break }
            t -= err / d
            if t < 0 || t > 1 { break }
        }
        if t < 0 || t > 1 || abs(sampleX(t) - x) >= 1e-6 {
            var lo = 0.0, hi = 1.0
            t = x
            for _ in 0 ..< 32 {
                let v = sampleX(t)
                if abs(v - x) < 1e-6 { break }
                if v < x { lo = t } else { hi = t }
                t = (lo + hi) / 2
            }
        }
        return sampleY(t)
    }
}
