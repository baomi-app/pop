import Cocoa
import UniformTypeIdentifiers

// Struct to represent a window's basic info
struct WindowInfo {
    let id: CGWindowID
    let owner: String
    let name: String
    let bounds: CGRect
}

// 1. Get all active windows on screen
func getWindows() -> [WindowInfo] {
    var list: [WindowInfo] = []
    guard let windowList = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] else {
        return []
    }
    
    for win in windowList {
        guard let id = win[kCGWindowNumber as String] as? CGWindowID,
              let owner = win[kCGWindowOwnerName as String] as? String,
              let boundsDict = win[kCGWindowBounds as String] as? [String: Any],
              let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else {
            continue
        }
        let name = win[kCGWindowName as String] as? String ?? ""
        list.append(WindowInfo(id: id, owner: owner, name: name, bounds: bounds))
    }
    return list
}

// 2. Crop utility
func cropImage(at path: String, toPointsRect rect: CGRect, screenWidthPoints: CGFloat, outputPath: String) {
    guard let imageSource = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
        print("Failed to load image at \(path)")
        return
    }
    
    let scale = CGFloat(cgImage.width) / screenWidthPoints
    let pixelRect = CGRect(
        x: rect.origin.x * scale,
        y: rect.origin.y * scale,
        width: rect.size.width * scale,
        height: rect.size.height * scale
    )
    
    guard let cropped = cgImage.cropping(to: pixelRect) else {
        print("Failed to crop image")
        return
    }
    
    let destURL = URL(fileURLWithPath: outputPath) as CFURL
    guard let destination = CGImageDestinationCreateWithURL(destURL, UTType.png.identifier as CFString, 1, nil) else {
        print("Failed to create destination")
        return
    }
    
    CGImageDestinationAddImage(destination, cropped, nil)
    if !CGImageDestinationFinalize(destination) {
        print("Failed to save cropped image")
    } else {
        print("Successfully cropped and saved to \(outputPath)")
    }
}

// 3. Execution logic
let args = CommandLine.arguments
if args.count > 1 {
    let mode = args[1]
    let windows = getWindows()
    
    // Find primary screen dimensions
    let primaryScreen = NSScreen.screens.first(where: { $0.frame.origin == .zero }) ?? NSScreen.main ?? NSScreen.screens[0]
    let screenWidthPoints = primaryScreen.frame.width
    
    switch mode {
    case "preferences":
        // Find Pop Preferences Window ID to capture it natively with standard shadows
        if let prefWin = windows.first(where: { $0.owner == "Pop" && ($0.name.contains("偏好设置") || $0.name.contains("Preferences")) }) {
            print("FOUND_PREF_WINDOW_ID:\(prefWin.id)")
        } else {
            // Fallback: Crop the center of the screen where we placed the preferences window
            let cropRect = CGRect(
                x: (screenWidthPoints - 600) / 2,
                y: 190, // Positioned in the upper center
                width: 600,
                height: 600
            )
            print("Cropping center of the screen for preferences window...")
            cropImage(
                at: "assets/preferences.png",
                toPointsRect: cropRect,
                screenWidthPoints: screenWidthPoints,
                outputPath: "assets/preferences.png"
            )
        }
        
    case "notification":
        // Crop the notification snap (top-right quadrant of the screen)
        // Screen resolution is usually 1512x982 or similar in points.
        // We want to capture the top-right corner: x from (width - 440) to width, y from 0 to 220
        let rightMargin: CGFloat = 440
        let heightMargin: CGFloat = 200
        let cropRect = CGRect(
            x: screenWidthPoints - rightMargin,
            y: 0,
            width: rightMargin,
            height: heightMargin
        )
        print("Cropping top-right quadrant for notification banner...")
        cropImage(
            at: "assets/notification_snap.png",
            toPointsRect: cropRect,
            screenWidthPoints: screenWidthPoints,
            outputPath: "assets/notification_snap.png"
        )
        
    case "menu_bar":
        // Crop the status bar snap (top-right area, Wi-Fi/Bluetooth icons)
        let rightMargin: CGFloat = 400
        let heightMargin: CGFloat = 45
        let cropRect = CGRect(
            x: screenWidthPoints - rightMargin,
            y: 0,
            width: rightMargin,
            height: heightMargin
        )
        print("Cropping top-right status bar area...")
        cropImage(
            at: "assets/menu_bar_snap.png",
            toPointsRect: cropRect,
            screenWidthPoints: screenWidthPoints,
            outputPath: "assets/menu_bar_snap.png"
        )
        
    case "window":
        // Find TextEdit or markdown viewer window
        if let textWin = windows.first(where: { $0.owner == "TextEdit" || $0.name.contains("README") }) {
            print("Found text window bounds: \(textWin.bounds)")
            // Crop with 80pt padding around the window to show Pop selection highlight and active drawings/toolbar
            let padding: CGFloat = 80
            let cropRect = CGRect(
                x: max(0, textWin.bounds.origin.x - padding),
                y: max(0, textWin.bounds.origin.y - padding),
                width: min(screenWidthPoints, textWin.bounds.width + padding * 2),
                height: textWin.bounds.height + padding * 2
            )
            cropImage(
                at: "assets/window_snap.png",
                toPointsRect: cropRect,
                screenWidthPoints: screenWidthPoints,
                outputPath: "assets/window_snap.png"
            )
        } else {
            // Fallback: If no TextEdit window is found, crop the center of the screen
            let cropRect = CGRect(
                x: (screenWidthPoints - 900) / 2,
                y: 200,
                width: 900,
                height: 600
            )
            print("No TextEdit window found. Cropping screen center as fallback...")
            cropImage(
                at: "assets/window_snap.png",
                toPointsRect: cropRect,
                screenWidthPoints: screenWidthPoints,
                outputPath: "assets/window_snap.png"
            )
        }
        
    default:
        print("Unknown mode: \(mode)")
    }
} else {
    print("Usage: swift crop_tool.swift <preferences|notification|window>")
}
