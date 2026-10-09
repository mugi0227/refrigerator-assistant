import SwiftUI
import AVFoundation
import PhotosUI

struct NativeScanView: View {
    @EnvironmentObject private var model: NativeAppModel
    @EnvironmentObject private var store: HouseholdStore
    @State private var editing: Food?
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var details = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let camera = model.camera {
                NativeCameraPreview(camera:camera,marks:model.paused ? []:model.marks)
                    .ignoresSafeArea().accessibilityIdentifier("cameraPreview")
            } else {
                VStack(spacing:16) {
                    Image(systemName:"viewfinder").font(.system(size:52))
                    Text(model.demo ? "操作デモ":"食品を、ひとつずつ。").font(.title2.bold())
                    Text(model.demo ? "候補を確認しても在庫には保存しません":"バーコードと期限は自動で検出\n野菜・果物は中央のボタンで読み取り")
                        .font(.subheadline).multilineTextAlignment(.center)
                    if !model.demo {
                        Button("カメラをはじめる") { Task { await model.startCamera(store:store) } }
                            .buttonStyle(.borderedProminent).tint(.white).foregroundStyle(.black).disabled(model.loading)
                    }
                }.padding().foregroundStyle(.white)
            }
        }
        .safeAreaInset(edge:.top,spacing:0) { header }
        .safeAreaInset(edge:.bottom,spacing:0) { controls }
        .onAppear {
            if model.camera == nil { model.location = store.state.settings.location }
        }
        .sheet(item:$editing,onDismiss:{ model.paused = false }) { food in
            FoodEditor(food:food) { next in try model.confirm(next,store:store) }
        }
        .sheet(isPresented:$details) {
            NavigationStack {
                ScrollView {
                    VStack(alignment:.leading,spacing:20) {
                        Text(model.scanMessage).textSelection(.enabled)
                        Text(String(format:"直前のAI処理 %.2f秒",model.lastSeconds))
                        Text(model.lastAnswer).font(.callout).textSelection(.enabled)
                        Text("緑の枠はバーコード、黄色の枠は期限に関係する文字です。AIで読む食品は中央の白い点線の内側に映してください。映像をタップするとピントが合います。候補は確認して保存するまで在庫に入りません。")
                    }.padding()
                }.navigationTitle("読み取りの詳細").toolbar { ToolbarItem(placement:.confirmationAction) { Button("閉じる") { details = false } } }
            }
        }
        .onChange(of:selectedPhoto) { _, item in Task {
            guard let item else { return }; await model.stopCamera()
            do {
                guard let data = try await item.loadTransferable(type:Data.self), data.count <= 35*1024*1024, let image = UIImage(data:data) else { throw FridgeError.message("35MB以下の写真を選んでください。") }
                // Preserve aspect ratio; squashing portrait photos changes food shapes.
                let scale = 768 / max(image.size.width,image.size.height)
                let size = CGSize(width:image.size.width*scale,height:image.size.height*scale)
                let format = UIGraphicsImageRendererFormat(); format.scale = 1
                let jpeg = UIGraphicsImageRenderer(size:size,format:format).image { _ in image.draw(in:CGRect(origin:.zero,size:size)) }.jpegData(compressionQuality:0.85)!
                await model.recognize(store:store,photo:jpeg)
            } catch { model.alert = error.localizedDescription }; selectedPhoto = nil
        } }
    }
    private var header: some View {
        VStack(spacing:12) {
            HStack {
                VStack(alignment:.leading,spacing:2) {
                    Text("スキャン").font(.headline)
                    Text(model.demo ? "デモ · 保存しません":"自動検出 · 手動で登録").font(.caption)
                }
                Spacer()
                Menu {
                    Picker("保存場所",selection:$model.location) { Text("冷蔵").tag("fridge"); Text("冷凍").tag("freezer"); Text("常温").tag("pantry") }
                } label: { Label(FoodRules.locations[model.location] ?? "冷蔵",systemImage:"refrigerator").font(.subheadline).frame(minHeight:44) }
                Menu {
                    Button("手入力",systemImage:"square.and.pencil") { model.nextFood(); model.registrationForReview(); var food = Food(); food.location = model.location; editing = food }
                    Button("読み取りの詳細",systemImage:"info.circle") { details = true }
                    if model.cameraRunning {
                        Button("カメラを終了",systemImage:"stop.circle") { Task { await model.stopCamera() } }
                    }
                    Button("操作デモ：トマト",systemImage:"leaf") { Task { await model.stopCamera(); model.demoFood(store:store) } }
                    Button("操作デモ：牛乳と期限",systemImage:"barcode") { Task { await model.stopCamera(); model.demoFood(store:store,withDate:true) } }
                } label: { Image(systemName:"ellipsis").frame(width:44,height:44).background(.white.opacity(0.14),in:Circle()) }
                    .accessibilityLabel("スキャンのメニュー").accessibilityIdentifier("scanMenu")
            }
            Picker("操作",selection:$model.scanMode) { Text("登録する").tag("add"); Text("使ったものを消費").tag("consume") }
                .pickerStyle(.segmented).onChange(of:model.scanMode) { _, _ in model.nextFood() }
        }.padding(.horizontal,20).padding(.vertical,8).foregroundStyle(.white)
            .background(LinearGradient(colors:[.black.opacity(0.82),.black.opacity(0.45),.clear],startPoint:.top,endPoint:.bottom))
            .environment(\.colorScheme,.dark)
            .onChange(of:model.location) { _, value in model.candidate?.location = value; model.pending?.location = value }
    }
    private var controls: some View {
        VStack(spacing:12) {
            HStack(alignment:.top,spacing:8) {
                if model.aiBusy { ProgressView().tint(.white) }
                Text(model.paused ? "一時停止中":String(model.scanMessage.split(separator:"\n").first ?? ""))
                    .font(.subheadline.weight(.medium)).frame(maxWidth:.infinity,alignment:.leading)
                    .lineLimit(3).accessibilityIdentifier("scanStatus")
                Button { details = true } label: { Image(systemName:"info.circle").frame(width:44,height:44) }.accessibilityLabel("読み取りの詳細")
            }
            if let food = model.candidate {
                candidate(food)
            } else if let date = model.detectedDate {
                Label("日付 \(date) · 商品を選んでください",systemImage:"calendar").font(.subheadline)
            }
            HStack(alignment:.center) {
                PhotosPicker(selection:$selectedPhoto,matching:.images) { Image(systemName:"photo").font(.title2).frame(width:52,height:52).background(.white.opacity(0.14),in:Circle()) }
                    .accessibilityLabel("写真から読み取る").disabled(!model.aiReady || model.aiBusy || model.paused)
                Spacer()
                VStack(spacing:6) {
                    Button {
                        if model.aiBusy { model.cancelAI(); model.resetScan(); model.scanMessage = "中止しています…" }
                        else { Task { await model.recognize(store:store) } }
                    } label: {
                        ZStack {
                            Circle().stroke(.white.opacity(0.8),lineWidth:3).frame(width:74,height:74)
                            Circle().fill(model.aiBusy ? .orange:.white).frame(width:62,height:62)
                            Image(systemName:model.aiBusy ? "stop.fill":"sparkles").font(.title2).foregroundStyle(.black)
                        }
                    }.accessibilityLabel(model.aiBusy ? "AI読み取りを中止":"いまの食品を読み取る")
                        .accessibilityIdentifier("aiShutter").disabled(!model.aiBusy && (!model.cameraRunning || !model.aiReady || model.paused))
                    Text(model.aiBusy ? "中止":model.aiReady ? "AIで読み取る":"AIは設定で準備").font(.caption)
                }
                Spacer()
                Button { model.pauseScan() } label: { Image(systemName:model.paused ? "play.fill":"pause.fill").font(.title2).frame(width:52,height:52).background(.white.opacity(0.14),in:Circle()) }
                    .accessibilityLabel(model.paused ? "読み取りを再開":"読み取りを一時停止").disabled(!model.cameraRunning || model.aiBusy)
            }
            if model.candidate == nil, !model.aiBusy {
                Button("次の食品・次の1個") { model.nextFood() }.font(.subheadline).frame(minHeight:44)
            }
        }.padding(.horizontal,20).padding(.top,18).padding(.bottom,8).foregroundStyle(.white)
            .background(LinearGradient(colors:[.clear,.black.opacity(0.86),.black],startPoint:.top,endPoint:.bottom))
    }
    private func candidate(_ food: Food) -> some View {
        VStack(alignment:.leading,spacing:12) {
            HStack {
                Text(food.name.isEmpty ? "商品名を確認":food.name).font(.title3.bold()).lineLimit(2)
                Spacer()
                Button { model.cancelCandidate() } label: { Image(systemName:"xmark").frame(width:44,height:44) }.accessibilityLabel("候補を取り消す")
            }
            ScrollView(.horizontal,showsIndicators:false) {
                HStack(spacing:8) {
                    chip(food.quantity > 0 ? "\(food.quantity.formatted())\(food.unit)":"数量を確認",icon:"number",food:food)
                    chip(food.expiryDate.map { "\(FoodRules.expiryTypes[food.expiryType] ?? "日付") \($0)" } ?? "期限を映す・入力",icon:"calendar",food:food)
                    if let code = food.barcode { chip(String(code.hasPrefix("0") ? code.dropFirst():Substring(code)),icon:"barcode",food:food) }
                }
            }
            Button { model.registrationForReview(); editing = food } label: {
                Label(model.scanMode == "consume" ? "確認して消費":"確認して登録",systemImage:"checkmark").font(.headline).frame(maxWidth:.infinity,minHeight:46)
            }.background(.white,in:Capsule()).foregroundStyle(.black).accessibilityIdentifier("reviewCandidate")
        }.padding(16).background(Color(white:0.15),in:RoundedRectangle(cornerRadius:22))
            .overlay(RoundedRectangle(cornerRadius:22).stroke(.white.opacity(0.2),lineWidth:1))
    }
    private func chip(_ text: String, icon: String, food: Food) -> some View {
        Button { model.registrationForReview(); editing = food } label: {
            Label(text,systemImage:icon).font(.subheadline).padding(.horizontal,12).frame(minHeight:44).background(.white.opacity(0.12),in:Capsule())
        }
    }
}

struct NativeCameraPreview: UIViewRepresentable {
    let camera: NativeCamera
    var marks: [ScanMark] = []
    func makeUIView(context: Context) -> NativePreviewSurface { NativePreviewSurface(camera:camera) }
    func updateUIView(_ view: NativePreviewSurface, context: Context) { view.marks = marks; view.setNeedsLayout() }
}
final class NativePreviewSurface: UIView {
    private let camera: NativeCamera, video: AVCaptureVideoPreviewLayer
    private let overlay = CALayer()
    private var expiryTimer: Timer?
    var marks: [ScanMark] = []
    init(camera: NativeCamera) {
        self.camera = camera; video = camera.makePreviewLayer(); super.init(frame:.zero)
        layer.addSublayer(video); layer.addSublayer(overlay); clipsToBounds = true
        addGestureRecognizer(UITapGestureRecognizer(target:self,action:#selector(focus(_:))))
        isAccessibilityElement = true; accessibilityLabel = "カメラ映像。タップしてピントを合わせます。"
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }
    override func didMoveToWindow() {
        super.didMoveToWindow(); expiryTimer?.invalidate(); expiryTimer = nil
        if window != nil {
            expiryTimer = Timer.scheduledTimer(withTimeInterval:0.25,repeats:true) { [weak self] _ in self?.setNeedsLayout() }
        }
    }
    deinit { expiryTimer?.invalidate() }
    override func layoutSubviews() {
        super.layoutSubviews(); CATransaction.begin(); CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        video.frame = bounds; overlay.frame = bounds
        if let connection = video.connection, connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
        if bounds.width > 0, bounds.height > 0 { camera.updateVisibleRegion(video.metadataOutputRectConverted(fromLayerRect:bounds)) }
        overlay.sublayers?.forEach { $0.removeFromSuperlayer() }
        let guideRect = camera.aiGuide()
        if guideRect.width > 0 {
            let guide = CAShapeLayer()
            guide.path = UIBezierPath(roundedRect:video.layerRectConverted(fromMetadataOutputRect:guideRect),cornerRadius:20).cgPath
            guide.strokeColor = UIColor.white.withAlphaComponent(0.65).cgColor; guide.fillColor = UIColor.clear.cgColor
            guide.lineWidth = 1.5; guide.lineDashPattern = [9,7]; overlay.addSublayer(guide)
        }
        for mark in marks where Date().timeIntervalSince(mark.seenAt) < 1.5 {
            var rect = video.layerRectConverted(fromMetadataOutputRect:mark.rect)
            guard rect.intersects(bounds) else { continue }
            // A legacy Vision barcode result can be only one scanline high.
            // Keep its center/width, but give the detection indicator visible height.
            if !mark.isDate, rect.height < 24 {
                rect = CGRect(x:rect.minX,y:rect.midY-12,width:rect.width,height:24)
            }
            let color: UIColor = mark.isDate ? .systemYellow:.systemGreen
            let outline = CAShapeLayer(); outline.path = UIBezierPath(roundedRect:rect.insetBy(dx:-3,dy:-3),cornerRadius:6).cgPath
            outline.strokeColor = color.cgColor; outline.fillColor = UIColor.clear.cgColor; outline.lineWidth = 3; overlay.addSublayer(outline)
            let label = CATextLayer(); label.string = mark.title; label.fontSize = 13; label.contentsScale = traitCollection.displayScale
            label.foregroundColor = UIColor.black.cgColor; label.backgroundColor = color.cgColor; label.cornerRadius = 4; label.truncationMode = .end
            let width = min(bounds.width-24,max(110,CGFloat(mark.title.count)*14))
            label.frame = CGRect(x:max(12,min(rect.minX,bounds.width-width-12)),y:max(0,rect.minY-25),width:width,height:21)
            overlay.addSublayer(label)
        }
    }
    @objc private func focus(_ gesture: UITapGestureRecognizer) {
        let point = video.captureDevicePointConverted(fromLayerPoint:gesture.location(in:self))
        Task { try? await camera.focus(at:point) }
    }
}
