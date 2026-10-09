import SwiftUI
import AVFoundation
import PhotosUI

struct NativeScanView: View {
    @EnvironmentObject private var model: NativeAppModel
    @EnvironmentObject private var store: HouseholdStore
    @State private var editing: Food?
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var details = false
    @State private var editingExpiry = false
    @State private var expandedPhoto = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let image = model.capturedImage {
                FrozenFoodImage(image:image,regions:model.foodRegions,processing:model.aiBusy,caption:model.expiryMode ? "印字と読み取り結果を照合してください":nil)
                    .accessibilityIdentifier("frozenAIImage")
                    .overlay(alignment:.topTrailing) {
                        Button { expandedPhoto = true } label: {
                            Label("拡大",systemImage:"arrow.up.left.and.arrow.down.right").padding(.horizontal,12).frame(minHeight:44)
                                .background(.black.opacity(0.65),in:Capsule())
                        }.foregroundStyle(.white).padding(8).accessibilityIdentifier("expandPhoto")
                    }
            } else if let camera = model.camera {
                NativeCameraPreview(camera:camera,marks:model.paused ? []:model.marks,expiryMode:model.expiryMode)
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
        .overlay { if model.aiBusy { AIProcessingFrame().ignoresSafeArea().allowsHitTesting(false) } }
        .fullScreenCover(isPresented:$expandedPhoto) {
            ZStack(alignment:.topTrailing) {
                Color.black.ignoresSafeArea()
                if let image = model.capturedImage {
                    FrozenFoodImage(image:image,regions:model.foodRegions,processing:model.aiBusy,caption:model.expiryMode ? "期限の撮影画像":nil)
                }
                Button("閉じる") { expandedPhoto = false }.padding(.horizontal,20).frame(minHeight:44)
                    .background(.black.opacity(0.8),in:Capsule()).padding()
            }.foregroundStyle(.white).preferredColorScheme(.dark)
        }
        .onAppear {
            if model.camera == nil { model.location = store.state.settings.location }
            if model.capturedImage == nil, !model.demo { Task { await model.startCamera(store:store) } }
        }
        .sheet(item:$editing,onDismiss:{ model.paused = false }) { food in
            FoodEditor(food:food) { next in try model.confirm(next,store:store) }
        }
        .sheet(isPresented:$editingExpiry,onDismiss:{ model.paused = false }) {
            if let food = model.candidate {
                ExpiryEditor(food:food) { type, date in
                    guard model.candidate?.id == food.id else { return }
                    model.candidate?.expiryType = type; model.candidate?.expiryDate = date
                    model.scanMessage = "期限を候補に反映しました。確認して登録してください。"
                }
            }
        }
        .sheet(isPresented:$details) {
            NavigationStack {
                ScrollView {
                    VStack(alignment:.leading,spacing:20) {
                        Text(model.scanMessage).textSelection(.enabled)
                        Text("印字の読み取り").font(.headline)
                        Text(model.printedDetail).font(.callout).textSelection(.enabled)
                        Text(String(format:"直前のAI処理 %.2f秒",model.lastSeconds))
                        Text("生出力（加工前）").font(.headline)
                        Text(model.lastAnswer).font(.callout).textSelection(.enabled)
                        Text("判定・エラーの理由").font(.headline)
                        Text(model.scanDebug).textSelection(.enabled)
                        Text("白枠の中を食品AIで読み取ります。期限モードでは黄色い枠の中を読み取ります。映像をタップするとピントが合います。写真を開いた場合は、その写真からも期限を読めます。確認して保存するまで在庫には入りません。")
                    }.padding()
                }.navigationTitle("読み取りの詳細").toolbar { ToolbarItem(placement:.confirmationAction) { Button("閉じる") { details = false } } }
            }
        }
        .onChange(of:selectedPhoto) { _, item in Task {
            guard let item else { return }; await model.stopCamera()
            do {
                guard let data = try await item.loadTransferable(type:Data.self), data.count <= 35*1024*1024, let image = UIImage(data:data) else { throw FridgeError.message("35MB以下の写真を選んでください。") }
                // Preserve aspect ratio; squashing portrait photos changes food shapes.
                let scale = min(1,2048 / max(image.size.width,image.size.height))
                let size = CGSize(width:image.size.width*scale,height:image.size.height*scale)
                let format = UIGraphicsImageRendererFormat(); format.scale = 1
                let jpeg = UIGraphicsImageRenderer(size:size,format:format).image { _ in image.draw(in:CGRect(origin:.zero,size:size)) }.jpegData(compressionQuality:0.85)!
                await model.usePhoto(jpeg,store:store)
            } catch { model.alert = error.localizedDescription }; selectedPhoto = nil
        } }
    }
    private var header: some View {
        VStack(spacing:12) {
            HStack {
                VStack(alignment:.leading,spacing:2) {
                    Text(model.expiryMode ? "期限を読み取る":model.capturedImage != nil ? "写真を確認":"スキャン").font(.headline)
                    Text(model.demo ? "デモ · 保存しません":model.expiryMode ? "枠内を自動で読み取り":model.capturedImage != nil ? "この写真だけをAIが読み取ります":"自動検出 · 手動で登録").font(.caption)
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
                    #if DEBUG
                    Button("表示テスト：AIの静止画",systemImage:"sparkles") { Task { await model.demoFrozenImage() } }
                    #endif
                } label: { Image(systemName:"ellipsis").frame(width:44,height:44).background(.white.opacity(0.14),in:Circle()) }
                    .disabled(model.aiBusy)
                    .accessibilityLabel("スキャンのメニュー").accessibilityIdentifier("scanMenu")
            }
            if model.capturedImage == nil { Picker("操作",selection:$model.scanMode) { Text("登録する").tag("add"); Text("使ったものを消費").tag("consume") }
                .pickerStyle(.segmented).disabled(model.aiBusy || model.expiryMode).onChange(of:model.scanMode) { _, _ in model.nextFood() }
            }
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
            if let proposal = model.aiExpiryProposal {
                VStack(alignment:.leading,spacing:8) {
                    Text("印字：\(proposal.raw)").font(.subheadline)
                    Text("\(FoodRules.expiryTypes[proposal.type] ?? "日付") \(proposal.date)").font(.title3.bold())
                    Button("この日付を使う") { model.applyAIExpiry() }.frame(maxWidth:.infinity,minHeight:44)
                        .background(.white,in:Capsule()).foregroundStyle(.black).accessibilityIdentifier("applyAIExpiry")
                }.padding(12).background(Color(white:0.15),in:RoundedRectangle(cornerRadius:18))
            } else if let food = model.candidate, !model.expiryMode {
                candidate(food).disabled(model.aiBusy)
            } else if let date = model.detectedDate {
                Label("日付 \(date) · 商品を選んでください",systemImage:"calendar").font(.subheadline)
            }
            if model.expiryMode {
                if model.aiBusy {
                    Button("AI読み取りを中止") { model.cancelAI(); model.scanMessage = "中止しています…" }.frame(minHeight:44)
                } else {
                    HStack {
                        Button { Task { await model.readExpiryStill() } } label: {
                            Label(model.expiryPhotoData == nil ? "撮影して文字読取":"写真を文字読取",systemImage:"text.viewfinder").frame(maxWidth:.infinity,minHeight:48)
                        }.accessibilityIdentifier("stillOCR")
                        Button { Task { await model.recognizeExpiry() } } label: {
                            Label(model.aiReady ? "AIで期限を読む":model.loading ? "AI起動中…":"AIは設定で準備",systemImage:"sparkles").frame(maxWidth:.infinity,minHeight:48)
                        }.disabled(!model.aiReady || model.paused).accessibilityIdentifier("aiExpiryShutter")
                    }.font(.subheadline).background(.white.opacity(0.14),in:RoundedRectangle(cornerRadius:16))
                    if model.capturedImage != nil, model.cameraRunning { Button("期限を撮り直す") { model.beginExpiry() }.frame(minHeight:44) }
                }
                HStack {
                    Button("撮影を終える") { model.endExpiry() }.frame(minHeight:44)
                    Spacer()
                    Button("期限を手入力") { openExpiryEditor() }.frame(minHeight:44)
                }.disabled(model.aiBusy).accessibilityIdentifier("expiryModeControls")
            } else if model.capturedImage != nil, !model.aiBusy {
                if model.candidate == nil { Button("この写真の期限を読み取る") { model.beginExpiry() }.frame(minHeight:44) }
                Button { model.nextFood(); if model.camera == nil { Task { await model.startCamera(store:store) } } } label: {
                    Label("次を撮影する",systemImage:"camera").font(.headline).frame(maxWidth:.infinity,minHeight:52)
                }.background(.white.opacity(0.14),in:Capsule()).accessibilityIdentifier("nextCapture")
            } else { HStack(alignment:.center) {
                PhotosPicker(selection:$selectedPhoto,matching:.images) { Image(systemName:"photo").font(.title2).frame(width:52,height:52).background(.white.opacity(0.14),in:Circle()) }
                    .accessibilityLabel("写真から読み取る").disabled(model.aiBusy || model.paused)
                Spacer()
                VStack(spacing:6) {
                    Button {
                        if model.aiBusy { model.cancelAI(); model.scanMessage = "中止しています…" }
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
            } }
            if !model.aiBusy, !model.lastAnswer.isEmpty || !model.scanDebug.isEmpty {
                Button { details = true } label: {
                    Label("生出力・判定理由を見る",systemImage:"text.bubble").font(.subheadline).frame(maxWidth:.infinity,minHeight:44)
                }.accessibilityIdentifier("rawRecognition")
            }
            if model.candidate == nil, !model.aiBusy, model.capturedImage == nil, !model.expiryMode {
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
            if model.capturedImage == nil { ScrollView(.horizontal,showsIndicators:false) {
                HStack(spacing:8) {
                    chip(food.quantity > 0 ? "\(food.quantity.formatted())\(food.unit)":"数量を確認",icon:"number",food:food)
                    if let date = food.expiryDate {
                        Button { openExpiryEditor() } label: {
                            Label("\(FoodRules.expiryTypes[food.expiryType] ?? "日付") \(date)",systemImage:"calendar")
                                .font(.subheadline).padding(.horizontal,12).frame(minHeight:44).background(.white.opacity(0.12),in:Capsule())
                        }
                    }
                    if let code = food.barcode { chip(String(code.hasPrefix("0") ? code.dropFirst():Substring(code)),icon:"barcode",food:food) }
                }
            } } else {
                Text(food.quantity > 0 ? "\(food.quantity.formatted())\(food.unit) · 数量は確認画面で変更できます":"数量を確認してください").font(.subheadline)
            }
            if !model.expiryMode, food.kind != "produce" {
                HStack(spacing:12) {
                    Button { model.beginExpiry() } label: { Label(food.expiryDate == nil ? "期限を読み取る":"期限を再読取",systemImage:"viewfinder").frame(minHeight:44) }
                        .disabled(!model.cameraRunning && !model.demo && model.capturedImage == nil).accessibilityIdentifier("readExpiry")
                    Spacer(minLength:0)
                    Button("期限を手入力") { openExpiryEditor() }.frame(minHeight:44)
                }.font(.subheadline)
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
    private func openExpiryEditor() { model.endExpiry(); model.registrationForReview(); editingExpiry = true }
}

private struct ExpiryEditor: View {
    @Environment(\.dismiss) private var dismiss
    let food: Food
    let apply: (String,String?) -> Void
    @State private var type: String
    @State private var date: Date
    init(food: Food, apply: @escaping (String,String?) -> Void) {
        self.food = food; self.apply = apply
        _type = State(initialValue:food.expiryType)
        _date = State(initialValue:FoodRules.dateFormatter().date(from:food.expiryDate ?? FoodRules.today) ?? Date())
    }
    var body: some View {
        NavigationStack {
            Form {
                Section(food.name.isEmpty ? "選択中の商品":food.name) {
                    Picker("期限の種類",selection:$type) {
                        Text("選んでください").tag("unknown"); Text("賞味期限").tag("best_before")
                        Text("消費期限").tag("use_by"); Text("使い切り目安").tag("estimate")
                    }
                    DatePicker("日付",selection:$date,displayedComponents:.date)
                        .datePickerStyle(.graphical).environment(\.timeZone,TimeZone(secondsFromGMT:0)!)
                }
                Text("ここでは候補の期限だけを変更します。在庫への登録は、次の確認画面で行います。")
                    .font(.footnote).foregroundStyle(.secondary)
            }.navigationTitle("期限を入力").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement:.cancellationAction) { Button("キャンセル") { dismiss() } }
                    ToolbarItem(placement:.confirmationAction) {
                        Button("候補に反映") { apply(type,FoodRules.dateFormatter().string(from:date)); dismiss() }
                            .disabled(type == "unknown").accessibilityIdentifier("applyExpiry")
                    }
                }
        }
    }
}

struct NativeCameraPreview: UIViewRepresentable {
    let camera: NativeCamera
    var marks: [ScanMark] = []
    var expiryMode = false
    func makeUIView(context: Context) -> NativePreviewSurface { NativePreviewSurface(camera:camera) }
    func updateUIView(_ view: NativePreviewSurface, context: Context) { view.marks = marks; view.expiryMode = expiryMode; view.setNeedsLayout() }
}
final class NativePreviewSurface: UIView {
    private let camera: NativeCamera, video: AVCaptureVideoPreviewLayer
    private let overlay = CALayer()
    private var expiryTimer: Timer?
    var marks: [ScanMark] = []
    var expiryMode = false
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
        let expiryRect = CGRect(x:bounds.width*0.08,y:bounds.height*0.34,width:bounds.width*0.84,height:bounds.height*0.24)
        let side = min(bounds.width*0.86,bounds.height*0.55)
        let foodRect = CGRect(x:(bounds.width-side)/2,y:bounds.height*0.40-side/2,width:side,height:side)
        if bounds.width > 0, bounds.height > 0 { camera.updateVisibleRegion(video.metadataOutputRectConverted(fromLayerRect:expiryMode ? expiryRect:bounds)) }
        if side > 0 { camera.updateAIRegion(video.metadataOutputRectConverted(fromLayerRect:expiryMode ? expiryRect:foodRect)) }
        overlay.sublayers?.forEach { $0.removeFromSuperlayer() }
        if expiryMode {
            let shade = CAShapeLayer(), path = UIBezierPath(rect:bounds)
            path.append(UIBezierPath(roundedRect:expiryRect,cornerRadius:16)); shade.path = path.cgPath
            shade.fillRule = .evenOdd; shade.fillColor = UIColor.black.withAlphaComponent(0.55).cgColor; overlay.addSublayer(shade)
            let frame = CAShapeLayer(); frame.path = UIBezierPath(roundedRect:expiryRect,cornerRadius:16).cgPath
            frame.strokeColor = UIColor.systemYellow.cgColor; frame.fillColor = UIColor.clear.cgColor; frame.lineWidth = 2; overlay.addSublayer(frame)
        }
        if !expiryMode, side > 0 {
            let frame = CAShapeLayer(); frame.path = UIBezierPath(roundedRect:foodRect,cornerRadius:24).cgPath
            frame.strokeColor = UIColor.white.withAlphaComponent(0.8).cgColor; frame.fillColor = UIColor.clear.cgColor
            frame.lineWidth = 2; overlay.addSublayer(frame)
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
