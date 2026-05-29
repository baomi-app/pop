import AppKit
import CoreGraphics

enum ImageSaver {
    /// 保存到 ~/Pictures/Pop/Pop-时间戳.png
    @discardableResult
    static func savePNG(_ cgImage: CGImage) throws -> URL {
        try savePNG(cgImage, to: try outputDirectory())
    }

    @discardableResult
    static func savePNG(_ cgImage: CGImage, to dir: URL) throws -> URL {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("Pop-\(timestamp()).png")
        let rep = NSBitmapImageRep(cgImage: cgImage)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw CaptureError.encodeFailed
        }
        try data.write(to: url)
        return url
    }

    static func outputDirectory() throws -> URL {
        let pictures = FileManager.default
            .urls(for: .picturesDirectory, in: .userDomainMask).first!
        let dir = pictures.appendingPathComponent("Pop", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss-SSS"
        return f.string(from: Date())
    }
}
