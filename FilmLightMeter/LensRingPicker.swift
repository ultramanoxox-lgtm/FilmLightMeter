import SwiftUI
import UIKit

// MARK: - PreferenceKey：收集每个 item 的 midX
private struct ItemMidXKey: PreferenceKey {
    static var defaultValue: [Int: CGFloat] = [:]
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

struct LensRingPicker: View {
    let label: String
    let options: [String]
    @Binding var selectionIndex: Int
    var accentColor: Color = .white
    var isEnabled: Bool = true

    // ✅ 你要更小字、更密集：这几个参数可调
    var fontSize: CGFloat = 13
    var itemWidth: CGFloat = 46
    var controlHeight: CGFloat = 44

    @State private var closestIndex: Int = 0
    @GestureState private var isDragging: Bool = false
    @State private var lastHapticIndex: Int = -1
    private let haptic = UIImpactFeedbackGenerator(style: .light)
    private let hapticIntensity: CGFloat = 0.7

    private let tickWidth: CGFloat = 2
    private let majorTickHeight: CGFloat = 16
    private let minorTickHeight: CGFloat = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.gray.opacity(0.85))
                .padding(.horizontal, 22)

            GeometryReader { outerGeo in
                let centerX = outerGeo.size.width / 2
                let sidePadding = (outerGeo.size.width - itemWidth) / 2

                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 0) {
                            ForEach(options.indices, id: \.self) { i in
                                itemView(index: i)
                                    .frame(width: itemWidth, height: controlHeight)
                                    .id(i)
                                    // 记录每个 item 在“scroll”坐标系里的 midX
                                    .background(
                                        GeometryReader { geo in
                                            Color.clear.preference(
                                                key: ItemMidXKey.self,
                                                value: [i: geo.frame(in: .named("scroll")).midX]
                                            )
                                        }
                                    )
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        // ✅ 点击：直接滚到中心并更新选中
                                        withAnimation(.snappy) {
                                            proxy.scrollTo(i, anchor: .center)
                                        }
                                        selectionIndex = i
                                        closestIndex = i
                                    }
                            }
                        }
                        .padding(.horizontal, sidePadding)
                    }
                    .coordinateSpace(name: "scroll")
                    .allowsHitTesting(isEnabled)

                    // ✅ 实时拿到所有 midX，算“离中心最近”的那个
                    .onPreferenceChange(ItemMidXKey.self) { values in
                        if let newClosest = nearestIndex(to: centerX, in: values), newClosest != closestIndex {
                            closestIndex = newClosest
                            // ✅ 关键：滑动过程中也自动选中中心最近档位
                            selectionIndex = newClosest

                            if isEnabled && isDragging && newClosest != lastHapticIndex {
                                haptic.impactOccurred(intensity: hapticIntensity)
                                haptic.prepare()
                                lastHapticIndex = newClosest
                            }
                        }
                    }

                    // ✅ 松手后：把最近档位吸附到中心（避免“乱飘”）
                    .simultaneousGesture(
                        DragGesture()
                            .updating($isDragging) { _, state, _ in state = true }
                            .onEnded { _ in
                                // ScrollView 还有惯性，所以做两段“收尾吸附”
                                snap(proxy: proxy, index: closestIndex)
                            }
                    )

                    .onAppear {
                        closestIndex = selectionIndex
                        lastHapticIndex = selectionIndex
                        haptic.prepare()
                        DispatchQueue.main.async {
                            proxy.scrollTo(selectionIndex, anchor: .center)
                        }
                    }
                    .onChange(of: selectionIndex) { newValue in
                        // 外部改 selectionIndex（比如初始化/逻辑）也保证居中
                        guard !isDragging else { return }
                        closestIndex = newValue
                        lastHapticIndex = newValue
                        DispatchQueue.main.async {
                            withAnimation(.snappy) {
                                proxy.scrollTo(newValue, anchor: .center)
                            }
                        }
                    }
                }
                // 两侧渐隐（镜头环质感）
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.00),
                            .init(color: .black, location: 0.16),
                            .init(color: .black, location: 0.84),
                            .init(color: .clear, location: 1.00)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                // 中心指示线（不吃手势）
                .overlay(alignment: .center) {
                    Rectangle()
                        .fill(accentColor)
                        .frame(width: 3, height: 26)
                        .opacity(0.95)
                        .allowsHitTesting(false)
                }
            }
            .frame(height: controlHeight)
        }
        .opacity(isEnabled ? 1.0 : 0.35)
    }

    // MARK: - 单个档位：上标尺 + 下数字 + 两档之间小刻度更丰富
    private func itemView(index i: Int) -> some View {
        let isSelected = (i == selectionIndex)

        return VStack(spacing: 6) {
            ZStack {
                // 两档之间更丰富：左右各一个小刻度
                HStack {
                    Rectangle()
                        .fill(Color.white.opacity(0.18))
                        .frame(width: tickWidth, height: minorTickHeight)
                        .offset(x: itemWidth * 0.18)

                    Spacer(minLength: 0)

                    Rectangle()
                        .fill(Color.white.opacity(0.18))
                        .frame(width: tickWidth, height: minorTickHeight)
                        .offset(x: -itemWidth * 0.18)
                }

                // 当前档位主刻度
                Rectangle()
                    .fill(Color.white.opacity(isSelected ? 0.85 : 0.25))
                    .frame(width: tickWidth, height: isSelected ? majorTickHeight : minorTickHeight)
            }
            .frame(height: majorTickHeight)

            Text(options[i])
                .font(.system(size: fontSize,
                              weight: isSelected ? .bold : .regular,
                              design: .monospaced))
                .foregroundColor(isSelected ? .white : .gray.opacity(0.55))
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Spacer(minLength: 0)
        }
    }

    // MARK: - 计算离中心最近的 index
    private func nearestIndex(to centerX: CGFloat, in values: [Int: CGFloat]) -> Int? {
        values.min(by: { abs($0.value - centerX) < abs($1.value - centerX) })?.key
    }

    // MARK: - 吸附：两段收尾，解决惯性导致的“吸不到”
    private func snap(proxy: ScrollViewProxy, index: Int) {
        withAnimation(.snappy) {
            proxy.scrollTo(index, anchor: .center)
        }
        // 再来一次收尾，吃掉 deceleration 的尾巴
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            withAnimation(.snappy) {
                proxy.scrollTo(index, anchor: .center)
            }
        }
    }
}
