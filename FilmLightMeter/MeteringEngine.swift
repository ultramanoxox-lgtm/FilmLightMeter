import Foundation

struct MeteringEngine {
    /// 计算曝光值 (EV at ISO 100)
    /// 公式: EV = log2(N^2 / t) - log2(ISO / 100)
    /// - Parameters:
    ///   - aperture: 光圈值 (f-number)
    ///   - shutterSpeed: 快门速度 (秒)
    ///   - iso: 感光度
    /// 计算曝光值 (EV at ISO 100)
    /// - Parameters:
    ///   - aperture: 光圈值
    ///   - shutterSpeed: 快门速度
    ///   - iso: 感光度
    ///   - offset: 曝光偏移量 (exposureTargetOffset)
    static func calculateEV100(aperture: Double, shutterSpeed: Double, iso: Double, offset: Double = 0, compensation: Double = 0) -> Double {
        // 基础 EV 计算
        let evBase = log2(pow(aperture, 2) / shutterSpeed) - log2(iso / 100.0)
        // 加入设备偏移补偿和用户自定义补偿
        return evBase + offset + compensation
    }
    
    /// 根据 EV100 和给定的胶片 ISO，计算快门速度（给定光圈）
    /// 公式: t = N^2 / (2^EV100 * (ISO_film / 100))
    static func calculateShutterSpeed(ev100: Double, filmISO: Double, aperture: Double) -> Double {
        let t = pow(aperture, 2) / (pow(2.0, ev100) * (filmISO / 100.0))
        return t
    }
    
    /// 根据 EV100 和给定的胶片 ISO，计算光圈值（给定快门速度）
    /// 公式: N = sqrt(t * 2^EV100 * (ISO_film / 100))
    static func calculateAperture(ev100: Double, filmISO: Double, shutterSpeed: Double) -> Double {
        let n = sqrt(shutterSpeed * pow(2.0, ev100) * (filmISO / 100.0))
        return n
    }
    
    /// 将快门速度转换为标准的分数形式字符串
    static func formatShutterSpeed(_ seconds: Double) -> String {
        if seconds >= 1 {
            return String(format: "%.1fs", seconds)
        } else {
            let reciprocal = Int(round(1.0 / seconds))
            return "1/\(reciprocal)"
        }
    }
}
