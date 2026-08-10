import AppKit

/// 撮影結果。ピクセル画像と、点⇔ピクセル変換のスケールを保持する。
struct Capture {
    let cgImage: CGImage
    let scale: CGFloat

    var pointSize: CGSize {
        CGSize(width: CGFloat(cgImage.width) / scale, height: CGFloat(cgImage.height) / scale)
    }

    func nsImage() -> NSImage {
        NSImage(cgImage: cgImage, size: pointSize)
    }

    func pngData() -> Data? {
        let rep = NSBitmapImageRep(cgImage: cgImage)
        rep.size = pointSize  // Retina の DPI 情報を埋め込む
        return rep.representation(using: .png, properties: [:])
    }
}

enum Clipboard {
    static func copy(_ capture: Capture) {
        let pb = NSPasteboard.general
        pb.clearContents()
        if let png = capture.pngData() {
            pb.setData(png, forType: .png)
        }
        if let tiff = capture.nsImage().tiffRepresentation {
            pb.setData(tiff, forType: .tiff)
        }
    }
}
