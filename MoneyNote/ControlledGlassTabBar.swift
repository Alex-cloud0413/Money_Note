import SwiftUI

/// One fixed Liquid Glass surface with a separately moving selection fill.
/// The plate, buttons, symbols, and text never scale in response to selection.
struct ControlledGlassTabBar: View {
    @Binding private var selection: Int
    private let onSelectionFeedback: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var symbolSize: CGFloat = 20
    @ScaledMetric(relativeTo: .caption) private var labelSize: CGFloat = 11
    @ScaledMetric(relativeTo: .body) private var scaledItemHeight: CGFloat = 54

    // A fractional item index keeps dragging independent of page selection and
    // automatically follows the available width after a window-size change.
    @State private var lensPosition: CGFloat
    @State private var isDragging = false
    @GestureState private var dragGestureActive = false

    private static let inset: CGFloat = 5
    private static let items: [(title: String, symbol: String)] = [
        ("明细", "text.alignleft"),
        ("账本", "books.vertical"),
        ("统计", "chart.bar.xaxis"),
        ("预算", "circle.dashed")
    ]

    init(selection: Binding<Int>, onSelectionFeedback: @escaping () -> Void = {}) {
        _selection = selection
        self.onSelectionFeedback = onSelectionFeedback
        _lensPosition = State(initialValue: CGFloat(Self.validIndex(selection.wrappedValue)))
    }

    private var itemHeight: CGFloat { max(44, scaledItemHeight) }
    private var barHeight: CGFloat { itemHeight + Self.inset * 2 }
    private var selectedIndex: Int { Self.validIndex(selection) }

    var body: some View {
        GeometryReader { geometry in
            let slotWidth = max(0, geometry.size.width - Self.inset * 2)
                / CGFloat(Self.items.count)

            ZStack(alignment: .leading) {
                glassPlate

                selectionFill(slotWidth: slotWidth)

                HStack(spacing: 0) {
                    ForEach(Self.items.indices, id: \.self) { index in
                        tabButton(index)
                    }
                }
                .padding(Self.inset)
            }
            .frame(width: geometry.size.width, height: barHeight)
            .contentShape(Capsule())
            // A real drag takes precedence over button tracking. A stationary
            // touch remains an ordinary, independently accessible button tap.
            .highPriorityGesture(selectionDrag(slotWidth: slotWidth))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("mainTabBar")
        }
        .frame(height: barHeight)
        .frame(maxWidth: 600)
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .onChange(of: selection) { _, newValue in
            guard !isDragging else { return }
            lensPosition = CGFloat(Self.validIndex(newValue))
        }
        .onChange(of: dragGestureActive) { wasActive, isActive in
            // GestureState also resets after cancellation, which has no
            // onEnded callback (for example when a system gesture wins).
            guard wasActive, !isActive, isDragging else { return }
            isDragging = false
            lensPosition = CGFloat(selectedIndex)
        }
    }

    @ViewBuilder
    private var glassPlate: some View {
        if #available(iOS 26.0, *) {
            Color.clear
                .glassEffect(.regular.interactive(false), in: Capsule())
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        } else {
            Capsule()
                .fill(.regularMaterial)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private func selectionFill(slotWidth: CGFloat) -> some View {
        Capsule()
            .fill(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.075))
            .overlay {
                Capsule().strokeBorder(
                    LinearGradient(
                        colors: [
                            .white.opacity(colorScheme == .dark ? 0.20 : 0.60),
                            .white.opacity(colorScheme == .dark ? 0.05 : 0.14)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.6
                )
            }
            .frame(width: max(0, slotWidth - 4), height: itemHeight)
            .offset(x: Self.inset + 2 + lensPosition * slotWidth)
            // This is the only animated property in the navigation control.
            // In particular, no animation transaction wraps the page binding.
            .animation(
                isDragging || reduceMotion ? nil : .easeOut(duration: 0.10),
                value: lensPosition
            )
            .allowsHitTesting(false)
            .accessibilityIdentifier("selectionLens")
            .accessibilityHidden(true)
    }

    private func tabButton(_ index: Int) -> some View {
        let item = Self.items[index]
        let isSelected = selectedIndex == index

        return Button {
            select(index)
        } label: {
            VStack(spacing: 3) {
                Image(systemName: item.symbol)
                    .font(.system(size: symbolSize, weight: .medium))
                    .frame(height: symbolSize + 4)
                    .accessibilityHidden(true)
                Text(item.title)
                    .font(.system(size: labelSize, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            .frame(maxWidth: .infinity, minHeight: itemHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.title)
        .accessibilityIdentifier("mainTab-\(index)")
        .accessibilityValue(isSelected ? "已选中" : "未选中")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func selectionDrag(slotWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .local)
            .updating($dragGestureActive) { _, active, transaction in
                active = true
                transaction.animation = nil
            }
            .onChanged { value in
                guard slotWidth > 0 else { return }
                isDragging = true
                lensPosition = position(at: value.location.x, slotWidth: slotWidth)
            }
            .onEnded { value in
                guard slotWidth > 0 else {
                    isDragging = false
                    lensPosition = CGFloat(selectedIndex)
                    return
                }
                let target = Int(position(at: value.location.x, slotWidth: slotWidth).rounded())
                isDragging = false
                select(target)
                // Always update the visual position, even if the drag ends on
                // the original page. Its return still uses the local animation.
                lensPosition = CGFloat(target)
            }
    }

    private func select(_ index: Int) {
        let target = Self.validIndex(index)
        if selection != target {
            selection = target
            onSelectionFeedback()
        }
        lensPosition = CGFloat(target)
    }

    private func position(at x: CGFloat, slotWidth: CGFloat) -> CGFloat {
        let fractionalIndex = (x - Self.inset) / slotWidth - 0.5
        return min(max(fractionalIndex, 0), CGFloat(Self.items.count - 1))
    }

    private static func validIndex(_ index: Int) -> Int {
        min(max(index, 0), items.count - 1)
    }
}
