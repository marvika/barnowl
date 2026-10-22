import CoreGraphics

/// Where the cropped image sits on the output canvas, once the frame's padding and aspect
/// ratio are applied. All in pixels, with y pointing down.
struct FrameLayout: Equatable {
    /// The whole output.
    let canvasSize: CGSize
    /// The cropped image, on the canvas.
    let imageRect: CGRect
    /// The part of the image shown, in image pixels.
    let crop: CGRect

    init(crop: CGRect, frame: FrameSettings) {
        let crop = crop.integral
        self.crop = crop
        let width: CGFloat = crop.width
        let height: CGFloat = crop.height
        guard frame.isOn else {
            canvasSize = crop.size
            imageRect = CGRect(origin: .zero, size: crop.size)
            return
        }
        let padding: CGFloat = max(0, frame.padding.rounded())
        var canvasWidth: CGFloat = width + 2 * padding
        var canvasHeight: CGFloat = height + 2 * padding
        if let ratio = frame.ratio.value, canvasHeight > 0 {
            if canvasWidth / canvasHeight < ratio {
                canvasWidth = (canvasHeight * ratio).rounded(.up)
            } else {
                canvasHeight = (canvasWidth / ratio).rounded(.up)
            }
        }
        canvasSize = CGSize(width: canvasWidth, height: canvasHeight)
        // The padding is the least there is; the position says where any room beyond it goes.
        let spareX: CGFloat = canvasWidth - width - 2 * padding
        let spareY: CGFloat = canvasHeight - height - 2 * padding
        let along = CGFloat(min(max(frame.position.x, 0), 1))
        let down = CGFloat(min(max(frame.position.y, 0), 1))
        let x: CGFloat = (spareX * along + padding).rounded(.down)
        let y: CGFloat = (spareY * down + padding).rounded(.down)
        imageRect = CGRect(x: x, y: y, width: width, height: height)
    }

    init(document: EditorDocument) {
        self.init(crop: document.crop, frame: document.frame)
    }

    /// Add to an image point to get its canvas point.
    var offset: CGPoint {
        CGPoint(x: imageRect.minX - crop.minX, y: imageRect.minY - crop.minY)
    }

    func canvasPoint(fromImage point: CGPoint) -> CGPoint {
        CGPoint(x: point.x + offset.x, y: point.y + offset.y)
    }

    func imagePoint(fromCanvas point: CGPoint) -> CGPoint {
        CGPoint(x: point.x - offset.x, y: point.y - offset.y)
    }
}
