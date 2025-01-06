import SwiftUI

struct StripesConfig: Sendable {
    var background: Color
    var foreground: Color
    var degrees: Double
    var barWidth: CGFloat
    var barSpacing: CGFloat

    init(
        background: Color,
        foreground: Color,
        degrees: Double = 30,
        barWidth: CGFloat = 20,
        barSpacing: CGFloat = 20
    ) {
        self.background = background
        self.foreground = foreground
        self.degrees = degrees
        self.barWidth = barWidth
        self.barSpacing = barSpacing
    }

    static let `default` = StripesConfig(
        background: Color.pink.opacity(0.5), foreground: Color.pink.opacity(0.8)
    )
}

struct Stripes: View {
    var config: StripesConfig

    init(
        background: Color,
        foreground: Color,
        degrees: Double = 30,
        barWidth: CGFloat = 20,
        barSpacing: CGFloat = 20
    ) {
        config = .init(
            background: background, foreground: foreground, degrees: degrees, barWidth: barWidth,
            barSpacing: barSpacing
        )
    }

    var body: some View {
        GeometryReader { geometry in
            let longSide = max(geometry.size.width, geometry.size.height)
            let itemWidth = config.barWidth + config.barSpacing
            let items = Int(2 * longSide / itemWidth)
            HStack(spacing: config.barSpacing) {
                ForEach(0 ..< items, id: \.self) { _ in
                    config.foreground
                        .frame(width: config.barWidth, height: 2 * longSide)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .rotationEffect(Angle(degrees: config.degrees), anchor: .center)
            .offset(x: -longSide / 2, y: -longSide / 2)
            .background(config.background)
        }
        .clipped()
    }

    static func color(_ color: Color) -> Self {
        Self(
            background: color.opacity(0.5), foreground: color.opacity(0.8), degrees: 50, barWidth: 30,
            barSpacing: 30
        )
    }
}
