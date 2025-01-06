import SwiftUI

public struct PreviewSafeArea<V: View>: View {
    public init(
        top: CGFloat = 100,
        leading: CGFloat = 44,
        bottom: CGFloat = 100,
        trailing: CGFloat = 44,
        containerIsBounds: Bool = true,
        view: @escaping (_ area: EdgeInsets) -> V
    ) {
        self.view = view
        self.containerIsBounds = containerIsBounds
        _top = .init(
            minimumDistance: 0, coordinateSpace: .local, wrappedValue: .init(width: leading, height: top)
        )
        _bottom = .init(
            minimumDistance: 0, coordinateSpace: .local,
            wrappedValue: .init(width: trailing, height: bottom)
        )
    }

    @DragMeasure var top: CGSize
    @DragMeasure var bottom: CGSize
    let containerIsBounds: Bool
    @ViewBuilder var view: (_ area: EdgeInsets) -> V
    var safeArea: EdgeInsets {
        .init(top: top.height, leading: top.width, bottom: bottom.height, trailing: bottom.width)
    }

    public var body: some View {
        GeometryReader { proxy in
            view(safeArea)
                .safeAreaPadding(safeArea)
                .ignoresSafeArea()
                .frame(maxWidth: containerIsBounds ? proxy.size.width : .infinity, maxHeight: containerIsBounds ? proxy.size.height : .infinity)
                .overlay {
                    GeometryReader { proxy in
                        Rectangle()
                            .fill(.clear)
                            .background {
                                ZStack {
                                    VStack {
                                        Stripes(background: .black.opacity(0.5), foreground: .yellow.opacity(0.9), degrees: -45)
                                            .frame(height: proxy.safeAreaInsets.top)
                                            .scaleEffect(x: 1.0, y: -1.0, anchor: .center)
                                        Spacer()
                                            .allowsHitTesting(false)
                                    }
                                    .ignoresSafeArea(.container)
                                    VStack {
                                        Spacer()
                                            .allowsHitTesting(false)
                                        Stripes(background: .black.opacity(0.5), foreground: .yellow.opacity(0.9), degrees: 45)
                                            .frame(height: proxy.safeAreaInsets.bottom)
                                    }
                                    .ignoresSafeArea(.container)
                                    HStack {
                                        Stripes(background: .black.opacity(0.5), foreground: .yellow.opacity(0.9), degrees: 45)
                                            .frame(width: proxy.safeAreaInsets.leading)
                                            .scaleEffect(x: -1.0, y: 1.0, anchor: .center)
                                        Spacer()
                                    }
                                    .ignoresSafeArea(.container)
                                    .allowsHitTesting(false)
                                    HStack {
                                        Spacer()
                                        Stripes(background: .black.opacity(0.5), foreground: .yellow.opacity(0.9), degrees: -45)
                                            .frame(width: proxy.safeAreaInsets.trailing)
                                    }
                                    .ignoresSafeArea(.container)
                                    .allowsHitTesting(false)
                                }
                            }
                            .overlay {
                                VStack(spacing: 0) {
                                    Rectangle()
                                        .fill(.clear)
                                        .overlay(alignment: .topLeading) {
                                            Circle()
                                                .fill(.ultraThinMaterial.opacity(0.9))
                                                .strokeBorder(.pink, lineWidth: 10)
                                                .strokeBorder(.black, lineWidth: 3)
                                                .frame(width: 44, height: 44)
                                                .offset(x: top.width - 44, y: top.height - 44)
                                                .shadow(color: .white, radius: 10)
                                                .draggable(updating: $top, smoothly: false, updateRatio: 1)
                                        }
                                        .ignoresSafeArea()
                                    Rectangle()
                                        .fill(.clear)
                                        .overlay(alignment: .bottomTrailing) {
                                            Circle()
                                                .fill(.ultraThinMaterial.opacity(0.9))
                                                .strokeBorder(.pink, lineWidth: 10)
                                                .strokeBorder(.black, lineWidth: 3)
                                                .frame(width: 44, height: 44)
                                                .offset(x: -bottom.width + 44, y: -bottom.height + 44)
                                                .shadow(color: .white, radius: 10)
                                                .draggable(updating: $bottom, smoothly: false, updateRatio: -1)
                                        }
                                        .ignoresSafeArea()
                                }
                            }
                    }
                    .safeAreaPadding(safeArea)
                    .ignoresSafeArea()
                }
        }
    }
}

#Preview("safe area") {
    PreviewSafeArea { _ in
        ZStack {
            HStack {
                Rectangle()
                    .fill(.cyan)
                    .overlay {
                        Text("This view ignores safe areas.")
                            .lineLimit(5)
                            .font(.footnote.monospaced())
                            .padding()
                            .background(RoundedRectangle(cornerRadius: 10).fill(.background))
                            .padding()
                    }
                    .border(.black, width: 5)
                    .ignoresSafeArea()
                Rectangle()
                    .fill(.pink)
                    .overlay {
                        Text("This view respects safe areas and has its own inset for the circle below it.")
                            .lineLimit(5)
                            .font(.footnote.monospaced())
                            .padding()
                            .background(RoundedRectangle(cornerRadius: 10).fill(.background))
                            .padding()
                    }
                    .border(.black, width: 5)
                    .safeAreaInset(edge: .bottom, alignment: .center) {
                        Stripes(
                            background: .red,
                            foreground: .black,
                            degrees: -45,
                            barWidth: 30,
                            barSpacing: 30
                        )
                        .aspectRatio(1, contentMode: .fit)
                        .clipShape(Circle())
                    }
                Rectangle()
                    .fill(.yellow)
                    .overlay {
                        Text("This view has 25 pts of safe area padding.")
                            .lineLimit(5)
                            .font(.footnote.monospaced())
                            .padding()
                            .background(RoundedRectangle(cornerRadius: 10).fill(.background))
                            .padding()
                    }
                    .border(.black, width: 5)
                    .safeAreaPadding(.init(top: 25, leading: 25, bottom: 25, trailing: 25))
            }
            .overlay {
                VStack {
                    VStack(spacing: 0) {
                        Text("Hello, World!")
                            .font(.largeTitle)
                        Text(
                            """
                            These views are in a 'PreviewSafeArea' — a wrapper that has adjustable safe areas.
                            Place your view in it and drag the corner circles around to see how it adjusts.
                            """
                        )
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .padding()
                    }
                    .padding()
                    .background {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(.background)
                            .strokeBorder(.black, lineWidth: 5)
                    }
                    .padding()
                    .padding()
                    Spacer()
                }
            }
        }
    }
}
