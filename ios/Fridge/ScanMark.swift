import Foundation
import CoreGraphics

// Normalized AVFoundation metadata coordinates, converted by the preview layer.
// Vision's bottom-left coordinates must be converted by AVCaptureVideoDataOutput
// first; stretching them to screen size breaks rotation/aspect-fill cropping.
struct ScanMark: Identifiable {
    let id: String
    let rect: CGRect
    let title: String
    let isDate: Bool
    let seenAt: Date

    static func barcode(_ row: [String:String]) -> ScanMark? {
        guard NativeReading.barcode(row["text"] ?? "") != nil,
              let x = Double(row["x"] ?? ""), let y = Double(row["y"] ?? ""),
              let width = Double(row["width"] ?? ""), let height = Double(row["height"] ?? ""), width > 0, height > 0 else { return nil }
        return ScanMark(id:"code-"+(row["text"] ?? ""),rect:CGRect(x:x,y:y,width:width,height:height),title:row["text"] ?? "バーコード",isDate:false,seenAt:Date())
    }
    static func dates(_ lines: [[String:Any]]) -> [ScanMark] {
        lines.compactMap { row in
            guard let text = row["text"] as? String, NativeReading.usablePrintedLine(row),
                  text.range(of:"製造|加工|包装",options:.regularExpression) == nil,
                  FoodRules.dateFromLabel(text) != nil || text.precomposedStringWithCompatibilityMapping.range(of:"賞味|消費|best\\s*before|use\\s*by|[0-9]{2,4}\\s*[年./-]\\s*[0-9]{1,2}",options:[.regularExpression,.caseInsensitive]) != nil,
                  let x = row["metadataX"] as? Double, let y = row["metadataY"] as? Double,
                  let w = row["metadataWidth"] as? Double, let h = row["metadataHeight"] as? Double else { return nil }
            return ScanMark(id:"date-\(text)-\(x)",rect:CGRect(x:x,y:y,width:w,height:h),title:text,isDate:true,seenAt:Date())
        }
    }
}
