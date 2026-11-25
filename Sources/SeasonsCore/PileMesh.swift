import Foundation

/// Turns ledge height fields into renderable geometry. Decoration is derived from stable
/// hashes of (ledge, cell, layer) so it does not flicker from frame to frame.
enum PileMesh {
    /// Soft fringe above the blanket for anti-aliasing, in points.
    static let fringe: Float = 1.2

    static func append(ledges: [Ledge], params: EffectParameters, into batch: inout RenderBatch) {
        let pile = params.pile
        for ledge in ledges where ledge.totalMass > 0 {
            switch pile.style {
            case .blanket:
                appendBlanket(ledge, scale: 1, top: pile.colorTop, bottom: pile.colorBottom, into: &batch)
            case .scatter:
                appendBlanket(ledge, scale: 0.75, top: pile.colorTop, bottom: pile.colorBottom, into: &batch)
                appendScatter(ledge, params: params, into: &batch)
            case .water:
                appendBlanket(ledge, scale: 1, top: pile.colorTop, bottom: pile.colorBottom, into: &batch)
                appendBeads(ledge, into: &batch)
            }
        }
    }

    private static func appendBlanket(_ l: Ledge, scale: Float, top: RGBA, bottom: RGBA,
                                      into batch: inout RenderBatch) {
        let n = l.count
        guard n > 1 else { return }
        let clearTop = top.withAlpha(0)
        let maxH = max(l.heights.max() ?? 1, 1)
        for i in 0..<(n - 1) where l.visible[i] && l.visible[i + 1] {
            // A window in front that hangs into the pile hides everything above its lower edge.
            let h0 = min(l.heights[i] * scale, l.ceiling[i])
            let h1 = min(l.heights[i + 1] * scale, l.ceiling[i + 1])
            let clipped = l.heights[i] * scale > l.ceiling[i] || l.heights[i + 1] * scale > l.ceiling[i + 1]
            guard h0 > 0.05 || h1 > 0.05 else { continue }
            let x0 = l.cellCenterX(i)
            let x1 = l.cellCenterX(i + 1)
            // Shade by depth: the top is bright, deeper parts take the bottom color.
            let top0 = blend(bottom, top, min(1, 0.35 + h0 / maxH))
            let top1 = blend(bottom, top, min(1, 0.35 + h1 / maxH))
            let topColor = blend(top0, top1, 0.5)
            let r0 = l.restY(i)
            let r1 = l.restY(i + 1)
            batch.appendQuad(x0: x0, x1: x1, bottom0: r0, top0: r0 + h0, bottom1: r1, top1: r1 + h1,
                             colorBottom: bottom, colorTop: topColor)
            if !clipped { // no soft fringe along a cut that a window edge covers
                batch.appendQuad(x0: x0, x1: x1, bottom0: r0 + h0, top0: r0 + h0 + fringe,
                                 bottom1: r1 + h1, top1: r1 + h1 + fringe,
                                 colorBottom: topColor, colorTop: clearTop)
            }
        }
    }

    private static func appendScatter(_ l: Ledge, params: EffectParameters, into batch: inout RenderBatch) {
        let spacing = params.pile.scatterSpacing
        let avgSize = (params.size.lowerBound + params.size.upperBound) * 0.5
        let probability = min(1, l.cellWidth * 1.7 / avgSize)
        let seed = UInt32(truncatingIfNeeded: l.id &* 2_654_435_761)
        for i in 0..<l.count where l.visible[i] && l.heights[i] > 0.3 {
            let h = l.heights[i]
            let layers = Int(h / spacing) + 1
            for k in 0..<layers {
                let key = UInt32(i) &* 131 &+ UInt32(k)
                guard unitHash(seed, key) < probability else { continue }
                let layerY = Float(k) * spacing
                let fade = clamp((h - layerY) / spacing, 0, 1)
                guard fade > 0.05, layerY < l.ceiling[i] else { continue }
                let jx = (unitHash(seed ^ 0x51, key) - 0.5) * l.cellWidth * 3
                let jy = unitHash(seed ^ 0x77, key) * spacing * 0.8
                let size = mix(params.size.lowerBound, params.size.upperBound, unitHash(seed ^ 0x13, key)) * 0.9
                let angle = (unitHash(seed ^ 0x29, key) - 0.5) * 2.6 + .pi / 2
                var color = params.colors[Int(hash32(seed ^ 0x3, key) % UInt32(params.colors.count))]
                let shade = 0.72 + 0.28 * min(1, layerY / max(h, 1) + 0.3)
                color = RGBA(color.r * shade, color.g * shade, color.b * shade, color.a * fade)
                batch.sprites.append(SpriteInstance(
                    x: l.cellCenterX(i) + jx, y: l.restY(i) + layerY + jy + size * 0.2,
                    width: size, height: size * params.aspect * 0.8, rotation: angle,
                    shape: params.shape, param: Float(hash32(seed, key) & 1), color: color))
            }
        }
    }

    private static func appendBeads(_ l: Ledge, into batch: inout RenderBatch) {
        let seed = UInt32(truncatingIfNeeded: l.id &* 40_503)
        let chance: Float = l.kind == .floor ? 0.05 : 0.14
        for i in 0..<l.count where l.visible[i] && l.heights[i] > 0.45 {
            let key = UInt32(i)
            guard unitHash(seed, key) < chance else { continue }
            let h = l.heights[i]
            guard h < l.ceiling[i] else { continue }
            let r = min(l.kind == .floor ? 3.5 : 5, 1.6 + h * 0.9) * (0.7 + 0.3 * unitHash(seed ^ 0x9, key))
            batch.sprites.append(SpriteInstance(
                x: l.cellCenterX(i), y: l.restY(i) + h + r * 0.35, width: r * 2, height: r * 1.7, rotation: 0,
                shape: .bead, color: RGBA(0.85, 0.92, 1, 0.8)))
        }
    }

    @inline(__always)
    private static func blend(_ a: RGBA, _ b: RGBA, _ t: Float) -> RGBA {
        RGBA(mix(a.r, b.r, t), mix(a.g, b.g, t), mix(a.b, b.b, t), mix(a.a, b.a, t))
    }
}
