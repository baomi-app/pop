import SwiftUI

/// 苞米 Pop 的品牌常量：配色 + 微文案。
/// 视觉调性：暖、圆、憨，线条干净。主色苞米黄，点睛苞叶绿，文字炭棕（非纯黑）。
enum Brand {
    // 苞米黄 #FFD24A
    static let cornYellow = Color(red: 1.0, green: 0.823, blue: 0.290)
    // 苞叶绿 #3FA34D
    static let leafGreen = Color(red: 0.247, green: 0.639, blue: 0.302)
    // 炭棕 #5A3A1E（正文/线条，替代纯黑）
    static let charcoal = Color(red: 0.353, green: 0.227, blue: 0.118)

    /// 微文案体系："苞米=一根、工具=一粒" 贯穿使用细节。
    enum Copy {
        static var saved: String { String(localized: "爆好了 🌽") }
        static func todayCount(_ n: Int) -> String { String(localized: "今天爆了 \(n) 粒") }
    }
}
