import SwiftUI

/// Brand constants for baomi Pop: colors + microcopy.
/// Visual tone: warm, round, friendly, with clean lines.
/// Primary = corn yellow, accent = husk green, text = charcoal brown (not pure black).
enum Brand {
    // Corn yellow #FFD24A
    static let cornYellow = Color(red: 1.0, green: 0.823, blue: 0.290)
    // Husk green #3FA34D
    static let leafGreen = Color(red: 0.247, green: 0.639, blue: 0.302)
    // Charcoal brown #5A3A1E (body text / lines, replaces pure black)
    static let charcoal = Color(red: 0.353, green: 0.227, blue: 0.118)

    /// Microcopy system: the "corn = a cob, tool = a kernel" metaphor runs through the UI.
    enum Copy {
        static var saved: String { String(localized: "爆好了 🌽") }
    }
}
