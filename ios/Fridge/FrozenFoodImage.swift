import SwiftUI

struct FrozenFoodImage: View {
    let image: UIImage
    let regions: [FoodRegion]
    let processing: Bool
    private let colors: [Color] = [.mint,.yellow,.cyan,.pink,.orange,.green]
    var body: some View {
        GeometryReader { proxy in
            let frame = FoodRegion.imageFrame(image:image.size,canvas:proxy.size)
            ZStack(alignment:.topLeading) {
                Image(uiImage:image).resizable().scaledToFit()
                    .frame(width:frame.width,height:frame.height).position(x:frame.midX,y:frame.midY)
                    .accessibilityLabel("AIに渡した写真")
                ForEach(regions) { region in
                    let rect = CGRect(x:frame.minX+region.rect.minX*frame.width,y:frame.minY+region.rect.minY*frame.height,
                                      width:region.rect.width*frame.width,height:region.rect.height*frame.height)
                    let color = colors[region.id % colors.count]
                    RoundedRectangle(cornerRadius:8).stroke(color,lineWidth:2.5)
                        .frame(width:rect.width,height:rect.height).position(x:rect.midX,y:rect.midY).accessibilityHidden(true)
                    Text(region.title).font(.subheadline.bold()).foregroundStyle(.black)
                        .padding(.horizontal,8).padding(.vertical,5).background(color,in:RoundedRectangle(cornerRadius:6))
                        .frame(width:min(180,max(0,frame.width-16)),alignment:.leading)
                        .offset(x:max(frame.minX+8,min(rect.minX,frame.maxX-188)),y:max(frame.minY+4,rect.minY-32))
                }
                if !processing {
                    Text(regions.isEmpty ? "位置を特定できませんでした":"AIの推定 · 数量も確認してください")
                        .font(.caption).padding(8).background(.black.opacity(0.8),in:Capsule())
                        .frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.bottom).padding(.bottom,4)
                }
            }.frame(width:proxy.size.width,height:proxy.size.height).clipped()
        }
    }
}

struct AIProcessingFrame: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.animation(minimumInterval:1.0/30,paused:reduceMotion)) { context in
            let phase = reduceMotion ? 0:context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy:4)/4
            let gradient = AngularGradient(colors:[.cyan,.blue,.purple,.pink,.orange,.yellow,.mint,.cyan],center:.center,angle:.degrees(phase*360))
            GeometryReader { proxy in
                ZStack {
                    RoundedRectangle(cornerRadius:34).stroke(gradient,lineWidth:9).blur(radius:12)
                    RoundedRectangle(cornerRadius:34).stroke(gradient,lineWidth:3)
                    ForEach(0..<4) { index in
                        Image(systemName:"sparkle").font(.system(size:16)).foregroundStyle(.white)
                            .opacity(reduceMotion ? 0.7:0.35+0.65*abs(sin(phase*Double.pi*2+Double(index))))
                            .position(x:index.isMultiple(of:2) ? 8:proxy.size.width-8,
                                      y:proxy.size.height*(index < 2 ? 0.25:0.7))
                    }
                }
            }.padding(5)
        }.accessibilityHidden(true)
    }
}
