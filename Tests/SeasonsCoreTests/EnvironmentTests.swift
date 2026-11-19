import Testing
@testable import SeasonsCore

@Suite("Seasons, intensity, flowers")
struct EnvironmentTests {
    @Test("Months map to meteorological seasons",
          arguments: [(1, Season.winter), (3, .spring), (5, .spring), (6, .summer), (9, .autumn), (11, .autumn), (12, .winter)])
    func seasons(month: Int, expected: Season) {
        #expect(Season.of(month: month) == expected)
    }

    @Test("Southern hemisphere is shifted by half a year")
    func southern() {
        #expect(Season.of(month: 1, southernHemisphere: true) == .summer)
    }

    @Test("Automatic selection per season")
    func automaticSelection() {
        #expect(SceneSelection.automatic(for: .winter, rainInSummer: false) == SceneSelection(effect: .snow, flowers: false))
        #expect(SceneSelection.automatic(for: .spring, rainInSummer: false) == SceneSelection(effect: .blossoms, flowers: true))
        #expect(SceneSelection.automatic(for: .summer, rainInSummer: false).effect == nil)
        #expect(SceneSelection.automatic(for: .summer, rainInSummer: true).effect == .rain)
        #expect(SceneSelection.automatic(for: .autumn, rainInSummer: false).effect == .leaves)
    }

    @Test("Variable intensity stays within bounds and changes over time")
    func variableIntensity() {
        let values = stride(from: 0.0, to: 3600, by: 7).map { Intensity.variable.multiplier(at: $0) }
        #expect(values.allSatisfy { $0 >= 0.12 && $0 <= 2.1 })
        #expect((values.max() ?? 0) - (values.min() ?? 0) > 1)
        #expect(Intensity.off.multiplier(at: 0) == 0)
    }

    @Test("Flowers grow, can be wiped by a fast cursor and regrow")
    func flowers() {
        var g = FlowerGarden(seed: 1)
        g.setBase(GardenBase(minX: 0, maxX: 400, y: 50))
        #expect(g.flowers.count > 8)
        for i in 0..<(120 * 60) {
            g.step(dt: 1.0 / 60, time: Double(i) / 60, windSpeed: 10, mouse: nil, mouseVelocity: .zero) { _, _, _ in }
        }
        #expect(g.flowers.allSatisfy { $0.growth == 1 })
        let target = g.flowers[3]
        let head = g.tip(of: target, baseY: 50)
        var petals = 0
        g.step(dt: 1.0 / 60, time: 200, windSpeed: 0, mouse: head, mouseVelocity: Vec2(2000, 0)) { _, _, _ in petals += 1 }
        #expect(petals > 0)
        #expect(g.flowers.contains { $0.growth == 0 })
        for i in 0..<(120 * 60) {
            g.step(dt: 1.0 / 60, time: 201 + Double(i) / 60, windSpeed: 0, mouse: nil, mouseVelocity: .zero) { _, _, _ in }
        }
        #expect(g.flowers.allSatisfy { $0.growth == 1 })
    }

    @Test("A slow cursor bends flowers away instead of wiping them")
    func flowersBend() {
        var g = FlowerGarden(seed: 2)
        g.setBase(GardenBase(minX: 0, maxX: 200, y: 0))
        for i in 0..<(80 * 60) {
            g.step(dt: 1.0 / 60, time: Double(i) / 60, windSpeed: 0, mouse: nil, mouseVelocity: .zero) { _, _, _ in }
        }
        let f = g.flowers[2]
        let head = g.tip(of: f, baseY: 0)
        let mouse = Vec2(head.x - 10, head.y)
        for i in 0..<30 {
            g.step(dt: 1.0 / 60, time: 100 + Double(i) / 60, windSpeed: 0, mouse: mouse, mouseVelocity: .zero) { _, _, _ in }
        }
        #expect(g.flowers[2].bend > 0.2) // bent to the right, away from the cursor
        #expect(g.flowers[2].growth == 1)
    }
}
