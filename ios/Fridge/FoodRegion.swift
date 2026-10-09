import Foundation
import CoreGraphics

// AI image coordinates are top-left normalized, not Vision/metadata coordinates.
struct FoodRegion: Identifiable {
    let id: Int
    let name: String
    let count: Int?
    let rect: CGRect
    var title: String { name + (count.map { " · \($0)個" } ?? " · 数量を確認") }
    static func parse(_ text: String) -> [FoodRegion] {
        guard let object = NativeReading.object(from:text),
              object["kind"] as? String != "none", object["uncertain"] as? Bool != true,
              let boxes = object["boxes"] as? [[String:Any]] else { return [] }
        return boxes.prefix(6).enumerated().compactMap { index, box in
            guard let name = box["label"] as? String, !FoodRules.clean(name).isEmpty,
                  let v = box["box_2d"] as? [Double], v.count == 4,
                  v.allSatisfy({ $0.isFinite && (0...1000).contains($0) }), v[2] > v[0], v[3] > v[1] else { return nil }
            let n = box["count"] as? Double
            let count = n.flatMap { $0 >= 1 && $0 <= 99 && $0.rounded() == $0 ? Int($0):nil }
            return FoodRegion(id:index,name:FoodRules.japaneseFoodName(name),count:count,
                rect:CGRect(x:v[1]/1000,y:v[0]/1000,width:(v[3]-v[1])/1000,height:(v[2]-v[0])/1000))
        }
    }
    static func imageFrame(image: CGSize, canvas: CGSize) -> CGRect {
        guard image.width > 0, image.height > 0, canvas.width > 0, canvas.height > 0 else { return .zero }
        let scale = min(canvas.width/image.width,canvas.height/image.height)
        let size = CGSize(width:image.width*scale,height:image.height*scale)
        return CGRect(x:(canvas.width-size.width)/2,y:(canvas.height-size.height)/2,width:size.width,height:size.height)
    }
}
