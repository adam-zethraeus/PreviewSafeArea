import SwiftUI

@propertyWrapper
struct DragMeasure: DynamicProperty, @unchecked Sendable {
    struct SizeBounds: Sendable {
        static let unbounded: SizeBounds = .init(
            min: .init(width: -CGFloat.infinity, height: -CGFloat.infinity),
            max: .init(width: CGFloat.infinity, height: CGFloat.infinity)
        )
        static let nonNegative: SizeBounds = .init(
            min: .init(width: 0, height: 0),
            max: .init(width: CGFloat.infinity, height: CGFloat.infinity)
        )
        static let vertical: SizeBounds = .init(
            min: .init(width: 0, height: -CGFloat.infinity),
            max: .init(width: 0, height: CGFloat.infinity)
        )
        static let verticalNonNegative: SizeBounds = .init(
            min: .init(width: 0, height: 0),
            max: .init(width: 0, height: CGFloat.infinity)
        )
        static let horizontal: SizeBounds = .init(
            min: .init(width: -CGFloat.infinity, height: 0),
            max: .init(width: CGFloat.infinity, height: 0)
        )
        static let horizontalNonNegative: SizeBounds = .init(
            min: .init(width: 0, height: 0),
            max: .init(width: CGFloat.infinity, height: 0)
        )

        init(
            min: CGSize,
            max: CGSize
        ) {
            self.min = min
            self.max = max
        }

        var min: CGSize
        var max: CGSize

        func bounding(size: CGSize) -> CGSize {
            minSides(maxSides(size, min), max)
        }
    }

    init(
        minimumDistance: CGFloat = 0,
        coordinateSpace: CoordinateSpace = .local,
        wrappedValue: CGSize = .zero
    ) {
        self.minimumDistance = minimumDistance
        self.coordinateSpace = coordinateSpace
        posted = wrappedValue
        self.wrappedValue = wrappedValue
    }

    var projectedValue: Self { self }

    fileprivate let minimumDistance: CGFloat
    fileprivate let coordinateSpace: CoordinateSpace
    public var wrappedValue: CGSize

    mutating func update() {
        let drag = dragCGSize ?? .zero

        wrappedValue = CGSize(
            width: posted.width + drag.width,
            height: posted.height + drag.height
        )
    }

    @GestureState var dragCGSize: CGSize?
    @State var posted: CGSize
}

extension View {
    func draggable(
        updating measure: DragMeasure,
        smoothly: Bool = true,
        bounds: DragMeasure.SizeBounds = .unbounded,
        updateRatio: CGFloat = 1.0
    ) -> some View {
        gesture(
            DragGesture(
                minimumDistance: measure.minimumDistance, coordinateSpace: measure.coordinateSpace
            )
            .updating(
                measure.$dragCGSize,
                body: { value, state, _ in
                    state = .init(
                        width: value.translation.width * updateRatio,
                        height: value.translation.height * updateRatio
                    )
                }
            )
            .onEnded { value in
                let last = measure.posted
                let current = last + value.translation * updateRatio
                let next = last + value.predictedEndTranslation * updateRatio
                let fixedCurrent = bounds.bounding(size: current)
                measure.posted = fixedCurrent
                guard smoothly else { return }
                let fixedNext = bounds.bounding(size: next)
                let max = maxSides(last, maxSides(current, next))
                let remainder = fixedNext - fixedCurrent
                let distValue = remainder.width + remainder.height
                let availValue = max.width + max.height
                withAnimation(
                    .interpolatingSpring(
                        stiffness: 200, damping: 35, initialVelocity: distValue / availValue
                    )
                ) {
                    measure.posted = fixedNext
                }
            }
        )
    }
}

private func maxSides(_ lhs: CGSize, _ rhs: CGSize) -> CGSize {
    .init(
        width: max(lhs.width, rhs.width),
        height: max(lhs.height, rhs.height)
    )
}

private func minSides(_ lhs: CGSize, _ rhs: CGSize) -> CGSize {
    .init(
        width: min(lhs.width, rhs.width),
        height: min(lhs.height, rhs.height)
    )
}

private func + (lhs: CGSize, rhs: CGSize) -> CGSize {
    let sumWidth =
        if lhs.width.isFinite && rhs.width.isFinite {
            lhs.width + rhs.width
        } else if lhs.width.isFinite {
            rhs.width
        } else {
            lhs.width
        }
    let sumHeight =
        if lhs.height.isFinite && rhs.height.isFinite {
            lhs.height + rhs.height
        } else if lhs.height.isFinite {
            rhs.height
        } else {
            lhs.height
        }
    return .init(width: sumWidth, height: sumHeight)
}

private func - (lhs: CGSize, rhs: CGSize) -> CGSize {
    let sumWidth =
        if lhs.width.isFinite && rhs.width.isFinite {
            lhs.width - rhs.width
        } else if lhs.width.isFinite {
            rhs.width
        } else {
            lhs.width
        }
    let sumHeight =
        if lhs.height.isFinite && rhs.height.isFinite {
            lhs.height - rhs.height
        } else if lhs.height.isFinite {
            rhs.height
        } else {
            lhs.height
        }
    return .init(width: sumWidth, height: sumHeight)
}

private func * (lhs: CGSize, rhs: CGFloat) -> CGSize {
    .init(width: lhs.width * rhs, height: lhs.height * rhs)
}

private func * (lhs: CGFloat, rhs: CGSize) -> CGSize {
    rhs * lhs
}
