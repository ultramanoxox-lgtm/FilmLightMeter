import SwiftUI
import Foundation
import Combine

struct ContentView: View {
    @StateObject private var cameraManager = CameraManager()
    
    // 参数选项
    let isoOptions: [Double] = [25, 50, 100, 160, 200, 400, 800, 1600, 3200, 6400]
    let apertureOptions: [Double] = [1.0, 1.2, 1.4, 1.6, 1.8, 2.0, 2.2, 2.5, 2.8, 3.2, 3.5, 4.0, 4.5, 5.0, 5.6 ,6.3 ,7.1,  8.0,9.0, 10, 11,13, 14,  16,18, 20, 22, 25, 29, 32]
    // 参考哈苏 CF 镜头挡位，并补充更多低速档位
    let shutterOptions: [Double] = [
        1.0/4000.0, 1.0/2000.0, 1.0/1000.0, 1.0/500.0,
        1.0/250.0, 1.0/125.0, 1.0/60.0, 1.0/30.0,
        1.0/15.0, 1.0/8.0, 1.0/4.0, 1.0/2.0,
        1.0, 2.0, 4.0, 8.0, 15.0, 30.0
    ]
    // 徕卡风格曝光补偿档位：-3EV 到 +3EV（每 1/3 EV）
    let exposureCompSteps: [Int] = Array(-9...9)
    
    // 状态索引
    @State private var isoIndex: Int = 5 // 400
    @State private var apertureIndex: Int = 4 // 2.8
    @State private var shutterIndex: Int = 7 // 1/125
    @State private var previewSize: CGSize = .zero
    @State private var exposureCompIndex: Int = 9
    @State private var autoMode: AutoMode = .manual
    @State private var isApplyingAuto: Bool = false
    @State private var smoothedEV: Double = 0.0
    @State private var hasSmoothedEV: Bool = false
    @State private var pendingAutoResult: AutoResult? = nil
    @State private var isSettingsPresented: Bool = false
    @State private var limitsInitialized: Bool = false
    @State private var isoMinIndex: Int = 0
    @State private var isoMaxIndex: Int = 0
    @State private var apertureMinIndex: Int = 0
    @State private var apertureMaxIndex: Int = 0
    @State private var shutterMinIndex: Int = 0
    @State private var shutterMaxIndex: Int = 0

    // 现代高级配色
    let accentOrange = Color(red: 1.0, green: 0.35, blue: 0.1)
    let accentBlue = Color(red: 0.2, green: 0.6, blue: 1.0)
    let bgBlack = Color(red: 0.02, green: 0.02, blue: 0.02)
    private let autoTimer = Timer.publish(every: 0.75, on: .main, in: .common).autoconnect()
    private let autoEVAlpha: Double = 0.12
    
    var body: some View {
        ZStack {
            bgBlack.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // 顶部状态栏 - 极简
                headerView
                
                // 实时预览区域
                ZStack {
                    CameraPreview(session: cameraManager.session)
                        .clipped()
                        .onTapGesture { location in
                            let size = effectivePreviewSize
                            let x = location.y / size.height
                            let y = 1.0 - (location.x / size.width)
                            cameraManager.setExposurePoint(CGPoint(x: x, y: y), visualPoint: location)
                        }
                    
                if cameraManager.meteringMode == "SPOT" {
                    MeteringReticle(isLocked: cameraManager.isLocked)
                        .position(cameraManager.visualPoint)
                }
                
                // 悬浮 EV/DIST 读数（两行，尺寸保持一致）
                VStack {
                    HStack {
                        Spacer()
                        VStack(alignment: .trailing, spacing: 6) {
                            HStack(spacing: 8) {
                                Text("EV")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.black)
                                    .padding(.horizontal, 4)
                                    .background(Color.white)
                                Text(String(format: "%.1f", cameraManager.ev100))
                                    .font(.system(size: 20, weight: .light, design: .monospaced))
                                    .foregroundColor(.white)
                            }
                            HStack(spacing: 8) {
                                Text("DIST")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.black)
                                    .padding(.horizontal, 4)
                                    .background(Color.white)
                                Text(distanceFromCameraText)
                                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                                    .foregroundColor(.white)
                            }
                        }
                        .padding(8)
                        .background(Color.black.opacity(0.4))
                        .cornerRadius(4)
                    }
                    .padding(16)
                    Spacer()
                }
            }
            .frame(height: 380)
            .background(
                GeometryReader { geo in
                    Color.clear
                            .onAppear { previewSize = geo.size }
                            .onChange(of: geo.size) { previewSize = $0 }
                    }
                )

            exposureDeviationView
                
                // 测光模式切换 - 放大并修复变形
                HStack(spacing: 10) {
                    modeButton(title: "SPOT", isSelected: cameraManager.meteringMode == "SPOT")
                    modeButton(title: "AVERAGE", isSelected: cameraManager.meteringMode == "AVERAGE")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                
                // 控制面板 - 扁平化滑动环
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        autoModePicker

                        LensRingPicker(
                            label: "ISO",
                            options: isoOptions.map { "\(Int($0))" },
                            selectionIndex: $isoIndex,
                            accentColor: .white,
                            isEnabled: isISOEnabled,
                            fontSize: 16,
                            itemWidth: 70,
                            controlHeight: 48
                        )

                        LensRingPicker(
                            label: "APERTURE",
                            options: apertureOptions.map { String(format: "f/%.1f", $0) },
                            selectionIndex: $apertureIndex,
                            accentColor: accentBlue,
                            isEnabled: isApertureEnabled,
                            fontSize: 15,
                            itemWidth: 56,      // ✅ 更密
                            controlHeight: 46
                        )

                        LensRingPicker(
                            label: "SHUTTER",
                            options: shutterOptions.map { MeteringEngine.formatShutterSpeed($0) },
                            selectionIndex: $shutterIndex,
                            accentColor: accentOrange,
                            isEnabled: isShutterEnabled,
                            fontSize: 15,
                            itemWidth: 54,      // ✅ 更密
                            controlHeight: 46
                        )


                        exposureCompensationRing
                    }
                    .padding(.vertical, 20)
                }
            }
        }
        // ✅ 在 ContentView 的 body 结束前添加（放在 onChange 之前）
        .onAppear {
            // 初始化测光点到屏幕中心
            let size = effectivePreviewSize
            cameraManager.visualPoint = CGPoint(x: size.width / 2, y: size.height / 2)
            cameraManager.exposurePoint = CGPoint(x: 0.5, y: 0.5)

            if !limitsInitialized {
                isoMaxIndex = max(0, isoOptions.count - 1)
                apertureMaxIndex = max(0, apertureOptions.count - 1)
                shutterMaxIndex = max(0, shutterOptions.count - 1)
                limitsInitialized = true
            }
            if exposureCompIndex < 0 || exposureCompIndex >= exposureCompSteps.count {
                exposureCompIndex = exposureCompSteps.firstIndex(of: 0) ?? 0
            }
            applyLimits()
        }
        .onChange(of: isoIndex) { _ in
            let clamped = clampIndex(isoIndex, min: isoMinIndex, max: isoMaxIndex)
            if clamped != isoIndex {
                isoIndex = clamped
                return
            }
            updatePreview()
        }
        .onChange(of: apertureIndex) { _ in
            let clamped = clampIndex(apertureIndex, min: apertureMinIndex, max: apertureMaxIndex)
            if clamped != apertureIndex {
                apertureIndex = clamped
                return
            }
            updatePreview()
        }
        .onChange(of: shutterIndex) { _ in
            let clamped = clampIndex(shutterIndex, min: shutterMinIndex, max: shutterMaxIndex)
            if clamped != shutterIndex {
                shutterIndex = clamped
                return
            }
            updatePreview()
        }
        .onChange(of: exposureCompIndex) { _ in
            pendingAutoResult = nil
        }
        .onChange(of: autoMode) { _ in
            pendingAutoResult = nil
        }
        .onChange(of: isoMinIndex) { _ in
            normalizeISOMin()
            applyLimits()
        }
        .onChange(of: isoMaxIndex) { _ in
            normalizeISOMax()
            applyLimits()
        }
        .onChange(of: apertureMinIndex) { _ in
            normalizeApertureMin()
            applyLimits()
        }
        .onChange(of: apertureMaxIndex) { _ in
            normalizeApertureMax()
            applyLimits()
        }
        .onChange(of: shutterMinIndex) { _ in
            normalizeShutterMin()
            applyLimits()
        }
        .onChange(of: shutterMaxIndex) { _ in
            normalizeShutterMax()
            applyLimits()
        }
        .onChange(of: cameraManager.ev100) { newValue in
            if !hasSmoothedEV {
                smoothedEV = newValue
                hasSmoothedEV = true
            } else {
                smoothedEV = smoothedEV + (newValue - smoothedEV) * autoEVAlpha
            }
        }
        .onReceive(autoTimer) { _ in
            applyAutoMode()
        }
        .sheet(isPresented: $isSettingsPresented) {
            settingsSheet
        }
    }
    
    private var headerView: some View {
        HStack {
            Text("ULTRAOXOX METER")
                .font(.system(size: 14, weight: .bold))
                .tracking(4)
                .foregroundColor(.white)
            Spacer()
            Button(action: { isSettingsPresented = true }) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 26, height: 26)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Circle())
            }
            Circle()
                .fill(accentOrange)
                .frame(width: 6, height: 6)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
    
    private func modeButton(title: String, isSelected: Bool) -> some View {
        Button(action: { if !isSelected { cameraManager.toggleMeteringMode() } }) {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(isSelected ? .black : .white)
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .background(isSelected ? Color.white : Color.white.opacity(0.08))
                .clipShape(Capsule())
        }
    }

    
    private var exposureDeviationView: some View {
        let currentISO = isoOptions[isoIndex]
        let currentAperture = apertureOptions[apertureIndex]
        let currentShutter = shutterOptions[shutterIndex]
        
        let currentSettingsEV = MeteringEngine.calculateEV100(
            aperture: currentAperture,
            shutterSpeed: currentShutter,
            iso: currentISO
        )
        let targetEV = cameraManager.ev100 - exposureCompensation
        let diff = currentSettingsEV - targetEV
        
        return HStack(spacing: 15) {
            Text("DEVIATION")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.gray)
            
            Text(String(format: "%+.1f EV", diff))
                .font(.system(size: 22, weight: .light, design: .monospaced))
                .foregroundColor(abs(diff) < 0.5 ? .green : (diff > 0 ? accentOrange : accentBlue))
            
            Spacer()
            
            Text(abs(diff) < 0.5 ? "MATCHED" : (diff > 0 ? "OVER" : "UNDER"))
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.gray)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .border(Color.gray, width: 1)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 15)
        .background(Color.white.opacity(0.03))
        .cornerRadius(4)
        .padding(.horizontal, 10)
    }

    private var exposureCompensationRing: some View {
        LensRingPicker(
            label: "COMP",
            options: exposureCompLabels,
            selectionIndex: $exposureCompIndex,
            accentColor: accentOrange,
            fontSize: 14,
            itemWidth: 58,
            controlHeight: 46
        )
        .padding(.horizontal, 6)
    }

    private var autoModePicker: some View {
        HStack(spacing: 8) {
            ForEach(AutoMode.allCases, id: \.self) { mode in
                Button(action: { autoMode = mode }) {
                    Text(mode.label)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(autoMode == mode ? .black : .white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 30)
                        .background(autoMode == mode ? accentOrange : Color.white.opacity(0.06))
                        .clipShape(Capsule())
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private var isoLabels: [String] {
        isoOptions.map { "\(Int($0))" }
    }

    private var apertureLabels: [String] {
        apertureOptions.map { String(format: "f/%.1f", $0) }
    }

    private var shutterLabels: [String] {
        shutterOptions.map { MeteringEngine.formatShutterSpeed($0) }
    }

    private var exposureCompLabels: [String] {
        exposureCompSteps.map { formatExposureCompStep($0) }
    }

    private var exposureCompensation: Double {
        Double(exposureCompSteps[exposureCompIndex]) / 3.0
    }

    private func formatExposureCompStep(_ step: Int) -> String {
        if step == 0 { return "0" }
        let sign = step > 0 ? "+" : "-"
        let absStep = abs(step)
        let whole = absStep / 3
        let remainder = absStep % 3

        var parts: [String] = []
        if whole > 0 { parts.append(String(whole)) }
        if remainder > 0 { parts.append("\(remainder)/3") }

        return sign + parts.joined(separator: " ")
    }

    private var settingsSheet: some View {
        NavigationView {
            Form {
                Section(header: Text("ISO Range")) {
                    limitPicker(title: "Min", options: isoLabels, selection: $isoMinIndex)
                    limitPicker(title: "Max", options: isoLabels, selection: $isoMaxIndex)
                }
                Section(header: Text("Aperture Range")) {
                    limitPicker(title: "Min", options: apertureLabels, selection: $apertureMinIndex)
                    limitPicker(title: "Max", options: apertureLabels, selection: $apertureMaxIndex)
                }
                Section(header: Text("Shutter Range")) {
                    limitPicker(title: "Min (Fast)", options: shutterLabels, selection: $shutterMinIndex)
                    limitPicker(title: "Max (Slow)", options: shutterLabels, selection: $shutterMaxIndex)
                }
            }
            .navigationTitle("Limits")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { isSettingsPresented = false }
                }
            }
        }
    }

    private func limitPicker(title: String, options: [String], selection: Binding<Int>) -> some View {
        Picker(title, selection: selection) {
            ForEach(options.indices, id: \.self) { i in
                Text(options[i]).tag(i)
            }
        }
        .pickerStyle(.menu)
    }
    
    private func updatePreview() {
        cameraManager.updateManualExposure(
            iso: isoOptions[isoIndex],
            shutterSpeed: shutterOptions[shutterIndex],
            aperture: apertureOptions[apertureIndex]
        )
    }

    private var effectivePreviewSize: CGSize {
        previewSize == .zero ? CGSize(width: UIScreen.main.bounds.width, height: 380) : previewSize
    }

    private var distanceFromCameraText: String {
        guard let meters = cameraManager.distanceMeters, meters.isFinite, meters > 0 else {
            return "--"
        }
        if meters < 1 {
            return String(format: "%.0f cm", meters * 100.0)
        }
        return String(format: "%.2f m", meters)
    }

    private var isISOEnabled: Bool {
        autoMode == .manual || autoMode == .isoPriority
    }

    private var isApertureEnabled: Bool {
        autoMode == .manual || autoMode == .aperturePriority
    }

    private var isShutterEnabled: Bool {
        autoMode == .manual || autoMode == .shutterPriority
    }

    private func normalizeISOMin() {
        if isoMinIndex > isoMaxIndex {
            isoMaxIndex = isoMinIndex
        }
    }

    private func normalizeISOMax() {
        if isoMaxIndex < isoMinIndex {
            isoMinIndex = isoMaxIndex
        }
    }

    private func normalizeApertureMin() {
        if apertureMinIndex > apertureMaxIndex {
            apertureMaxIndex = apertureMinIndex
        }
    }

    private func normalizeApertureMax() {
        if apertureMaxIndex < apertureMinIndex {
            apertureMinIndex = apertureMaxIndex
        }
    }

    private func normalizeShutterMin() {
        if shutterMinIndex > shutterMaxIndex {
            shutterMaxIndex = shutterMinIndex
        }
    }

    private func normalizeShutterMax() {
        if shutterMaxIndex < shutterMinIndex {
            shutterMinIndex = shutterMaxIndex
        }
    }

    private func applyLimits() {
        isoMinIndex = clampIndex(isoMinIndex, min: 0, max: max(0, isoOptions.count - 1))
        isoMaxIndex = clampIndex(isoMaxIndex, min: isoMinIndex, max: max(0, isoOptions.count - 1))
        apertureMinIndex = clampIndex(apertureMinIndex, min: 0, max: max(0, apertureOptions.count - 1))
        apertureMaxIndex = clampIndex(apertureMaxIndex, min: apertureMinIndex, max: max(0, apertureOptions.count - 1))
        shutterMinIndex = clampIndex(shutterMinIndex, min: 0, max: max(0, shutterOptions.count - 1))
        shutterMaxIndex = clampIndex(shutterMaxIndex, min: shutterMinIndex, max: max(0, shutterOptions.count - 1))

        isoIndex = clampIndex(isoIndex, min: isoMinIndex, max: isoMaxIndex)
        apertureIndex = clampIndex(apertureIndex, min: apertureMinIndex, max: apertureMaxIndex)
        shutterIndex = clampIndex(shutterIndex, min: shutterMinIndex, max: shutterMaxIndex)
        pendingAutoResult = nil
    }

    private var isoRange: ClosedRange<Int> {
        isoMinIndex...isoMaxIndex
    }

    private var apertureRange: ClosedRange<Int> {
        apertureMinIndex...apertureMaxIndex
    }

    private var shutterRange: ClosedRange<Int> {
        shutterMinIndex...shutterMaxIndex
    }

    private func applyAutoMode() {
        guard autoMode != .manual, !isApplyingAuto else { return }
        isApplyingAuto = true
        defer { isApplyingAuto = false }

        let baseEV = hasSmoothedEV ? smoothedEV : cameraManager.ev100
        let targetEV = baseEV - exposureCompensation

        let current = AutoResult(isoIndex: isoIndex, apertureIndex: apertureIndex, shutterIndex: shutterIndex)
        let candidate: AutoResult

        switch autoMode {
        case .aperturePriority:
            let fixedAperture = apertureOptions[apertureIndex]
            candidate = solveAperturePriority(targetEV: targetEV, fixedAperture: fixedAperture)
        case .shutterPriority:
            let fixedShutter = shutterOptions[shutterIndex]
            candidate = solveShutterPriority(targetEV: targetEV, fixedShutter: fixedShutter)
        case .isoPriority:
            let fixedISO = isoOptions[isoIndex]
            candidate = solveISOPriority(targetEV: targetEV, fixedISO: fixedISO)
        case .manual:
            return
        }

        if candidate == current {
            pendingAutoResult = nil
            return
        }

        if pendingAutoResult == candidate {
            isoIndex = candidate.isoIndex
            apertureIndex = candidate.apertureIndex
            shutterIndex = candidate.shutterIndex
            pendingAutoResult = nil
        } else {
            pendingAutoResult = candidate
        }
    }

    private func solveAperturePriority(targetEV: Double, fixedAperture: Double) -> AutoResult {
        let isoSeedIndex = clampIndex(isoIndex, min: isoMinIndex, max: isoMaxIndex)
        let isoSeed = isoOptions[isoSeedIndex]

        let idealShutter = MeteringEngine.calculateShutterSpeed(ev100: targetEV, filmISO: isoSeed, aperture: fixedAperture)
        var shutterIndexResult = nearestIndex(to: idealShutter, in: shutterOptions, range: shutterRange)
        let shutterResult = shutterOptions[shutterIndexResult]

        let idealISO = calculateISO(ev100: targetEV, aperture: fixedAperture, shutterSpeed: shutterResult)
        var isoIndexResult = nearestIndex(to: idealISO, in: isoOptions, range: isoRange)

        if isoIndexResult != isoSeedIndex {
            let iso = isoOptions[isoIndexResult]
            let idealShutter2 = MeteringEngine.calculateShutterSpeed(ev100: targetEV, filmISO: iso, aperture: fixedAperture)
            shutterIndexResult = nearestIndex(to: idealShutter2, in: shutterOptions, range: shutterRange)
        }

        return AutoResult(isoIndex: isoIndexResult, apertureIndex: apertureIndex, shutterIndex: shutterIndexResult)
    }

    private func solveShutterPriority(targetEV: Double, fixedShutter: Double) -> AutoResult {
        let isoSeedIndex = clampIndex(isoIndex, min: isoMinIndex, max: isoMaxIndex)
        let isoSeed = isoOptions[isoSeedIndex]

        let idealAperture = MeteringEngine.calculateAperture(ev100: targetEV, filmISO: isoSeed, shutterSpeed: fixedShutter)
        var apertureIndexResult = nearestIndex(to: idealAperture, in: apertureOptions, range: apertureRange)
        let apertureResult = apertureOptions[apertureIndexResult]

        let idealISO = calculateISO(ev100: targetEV, aperture: apertureResult, shutterSpeed: fixedShutter)
        var isoIndexResult = nearestIndex(to: idealISO, in: isoOptions, range: isoRange)

        if isoIndexResult != isoSeedIndex {
            let iso = isoOptions[isoIndexResult]
            let idealAperture2 = MeteringEngine.calculateAperture(ev100: targetEV, filmISO: iso, shutterSpeed: fixedShutter)
            apertureIndexResult = nearestIndex(to: idealAperture2, in: apertureOptions, range: apertureRange)
        }

        return AutoResult(isoIndex: isoIndexResult, apertureIndex: apertureIndexResult, shutterIndex: shutterIndex)
    }

    private func solveISOPriority(targetEV: Double, fixedISO: Double) -> AutoResult {
        let apertureSeedIndex = clampIndex(apertureIndex, min: apertureMinIndex, max: apertureMaxIndex)
        let apertureSeed = apertureOptions[apertureSeedIndex]

        let idealShutter = MeteringEngine.calculateShutterSpeed(ev100: targetEV, filmISO: fixedISO, aperture: apertureSeed)
        var shutterIndexResult = nearestIndex(to: idealShutter, in: shutterOptions, range: shutterRange)
        let shutterResult = shutterOptions[shutterIndexResult]

        let idealAperture = MeteringEngine.calculateAperture(ev100: targetEV, filmISO: fixedISO, shutterSpeed: shutterResult)
        var apertureIndexResult = nearestIndex(to: idealAperture, in: apertureOptions, range: apertureRange)

        if apertureIndexResult != apertureSeedIndex {
            let aperture = apertureOptions[apertureIndexResult]
            let idealShutter2 = MeteringEngine.calculateShutterSpeed(ev100: targetEV, filmISO: fixedISO, aperture: aperture)
            shutterIndexResult = nearestIndex(to: idealShutter2, in: shutterOptions, range: shutterRange)
        }

        return AutoResult(isoIndex: isoIndex, apertureIndex: apertureIndexResult, shutterIndex: shutterIndexResult)
    }

    private func nearestIndex(to value: Double, in options: [Double], range: ClosedRange<Int>) -> Int {
        var bestIndex = range.lowerBound
        var bestDistance = Double.greatestFiniteMagnitude
        for i in range {
            let option = options[i]
            let distance = stopDistance(value, option)
            if distance < bestDistance {
                bestDistance = distance
                bestIndex = i
            }
        }
        return bestIndex
    }

    private func calculateISO(ev100: Double, aperture: Double, shutterSpeed: Double) -> Double {
        guard shutterSpeed > 0 else { return 100.0 }
        return 100.0 * pow(aperture, 2) / (shutterSpeed * pow(2.0, ev100))
    }

    private func stopDistance(_ a: Double, _ b: Double) -> Double {
        guard a > 0, b > 0 else { return Double.greatestFiniteMagnitude }
        return abs(log2(a) - log2(b))
    }

    private func clampIndex(_ value: Int, min: Int, max: Int) -> Int {
        if value < min { return min }
        if value > max { return max }
        return value
    }
}

private struct AutoResult: Equatable {
    let isoIndex: Int
    let apertureIndex: Int
    let shutterIndex: Int
}

private enum AutoMode: CaseIterable {
    case manual
    case aperturePriority
    case shutterPriority
    case isoPriority

    var label: String {
        switch self {
        case .manual: return "MANUAL"
        case .aperturePriority: return "A-PRI"
        case .shutterPriority: return "S-PRI"
        case .isoPriority: return "ISO-PRI"
        }
    }
}

struct MeteringReticle: View {
    let isLocked: Bool
    
    var body: some View {
        ZStack {
            // 中心点
            Circle()
                .fill(isLocked ? Color.white : Color.yellow)
                .frame(width: 4, height: 4)
            
            // 外圈
            Circle()
                .stroke(isLocked ? Color.white : Color.yellow, lineWidth: 1)
                .frame(width: 60, height: 60)
            
            // 四个刻度线
            ForEach(0..<4) { i in
                Rectangle()
                    .fill(isLocked ? Color.white : Color.yellow)
                    .frame(width: 1, height: 10)
                    .offset(y: -30)
                    .rotationEffect(.degrees(Double(i) * 90))
            }
            
            // 锁定图标
            if isLocked {
                Image(systemName: "lock.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.white)
                    .offset(x: 25, y: -25)
            }
        }
        .opacity(0.8)
    }
}
