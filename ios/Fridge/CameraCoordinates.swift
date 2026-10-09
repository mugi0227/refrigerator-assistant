import CoreGraphics

// AVCaptureOutput: pixels, top-left origin in the rotated output image.
// Vision: normalized 0...1, bottom-left origin in that same image.
// Metadata: normalized coordinates in the device's natural orientation; only
// AVFoundation converts between metadata and the rotated output pixel space.
enum CameraCoordinates {
    static func visionRect(fromOutputPixels rect: CGRect, size: CGSize) -> CGRect {
        guard valid(size), finite(rect) else { return .zero }
        let clipped = rect.intersection(CGRect(origin:.zero,size:size))
        guard !clipped.isNull, !clipped.isEmpty else { return .zero }
        return CGRect(x:clipped.minX/size.width,y:1-clipped.maxY/size.height,
                      width:clipped.width/size.width,height:clipped.height/size.height)
    }
    static func outputPixels(fromVision rect: CGRect, size: CGSize) -> CGRect {
        guard valid(size), finite(rect) else { return .zero }
        let clipped = rect.intersection(CGRect(x:0,y:0,width:1,height:1))
        guard !clipped.isNull, !clipped.isEmpty else { return .zero }
        return CGRect(x:clipped.minX*size.width,y:(1-clipped.maxY)*size.height,
                      width:clipped.width*size.width,height:clipped.height*size.height)
    }
    private static func valid(_ size: CGSize) -> Bool {
        size.width.isFinite && size.height.isFinite && size.width > 0 && size.height > 0
    }
    private static func finite(_ rect: CGRect) -> Bool {
        [rect.minX,rect.minY,rect.width,rect.height].allSatisfy(\.isFinite)
    }
}
