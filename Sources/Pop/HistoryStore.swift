import SwiftUI
import AppKit

/// 截图历史。v1 仅内存保留，重启清空；后续做持久化 + 托盘缩略图面板。
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

    /// 今天爆了几粒
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
