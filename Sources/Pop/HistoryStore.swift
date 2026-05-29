import SwiftUI
import AppKit

/// Screenshot history. v1 keeps it in memory only (cleared on restart);
/// persistence + a thumbnail tray panel come later.
@MainActor
final class HistoryStore: ObservableObject {
    static let shared = HistoryStore()

    struct Pop: Identifiable {
        let id = UUID()
        let image: NSImage
        let fileURL: URL?
        let date: Date
    }

    @Published private(set) var pops: [Pop] = []

    /// How many kernels popped today.
    var todayCount: Int {
        pops.filter { Calendar.current.isDateInToday($0.date) }.count
    }

    func recordPop(image: NSImage, fileURL: URL?) {
        pops.insert(Pop(image: image, fileURL: fileURL, date: Date()), at: 0)
        if pops.count > 50 {
            pops.removeLast(pops.count - 50)
        }
    }
}
