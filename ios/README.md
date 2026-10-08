# iPhone版・AltStoreで試す

今の食品・買い物・献立・設定画面を同梱し、カメラとAIをiOSのネイティブ処理に切り替えた試作です。Apple Developer Programの有料登録は不要です。

## 入れる

1. WindowsのAltServerを起動し、USB接続したiPhoneにAltStore Classicをインストールする。
   初回はiPhoneの「設定 → プライバシーとセキュリティ → デベロッパモード」を有効にし、必要に応じて「一般 → VPNとデバイス管理」で自分の署名を信頼する。
2. `Fridge-unsigned.ipa`をiPhoneの「ファイル」に保存する。
3. AltStoreの「My Apps」→「＋」でIPAを選ぶ。AltServerが起動しているPCと接続しておく。
4. 「Fridge」を開き、設定の「モデルを保存して起動」を押す。
5. Wi-Fiと充電につなぎ、ダウンロード・AIの起動が終わるまでアプリを開いておく。

無料Apple Accountでの署名は7日間です。期限前にAltServerにつないでAltStoreから更新します。更新のためにアプリを削除する必要はありません。無料アカウントには同時に有効にできるアプリ数などの制限があります。

有効にできるのはAltStoreを含めて3アプリまでです。枠が埋まっている場合はAltStoreの「My Apps」で、今使わないアプリをDeactivateしてからインストールします。

Safari版の在庫は自動で移りません。Safariの設定でバックアップを「書き出す」→アプリの設定で「読み込む」と移せます。大切な在庫はバックアップを残してください。

ホーム画面の名前は`Fridge`です。AltServerはAppleのApp ID登録にこの表示名を使うため、日本語名では「The name for this app is invalid」（3009）が発生します。アプリ内は日本語のままです。名前のエラーが出た場合はv0.2.1以降のIPAを選び直してください。IPAファイルの名前だけを変えても、この問題は直りません。

## モデルと端末内処理

### カメラとバーコード（v0.2.6）

広角カメラだけに固定していた構成から、利用できる場合はTriple/Dual Wideの仮想カメラへ切り替えます。レンズ切り替えを自動にし、継続オートフォーカスと近距離優先の探索を有効にします。対応機種では近い被写体に別レンズでピントを合わせられますが、機種の最短撮影距離や照明による制限は残ります。

映像内をタップするか、映像下の「中央にピント」を押すと、指定位置でピントと露出を調整します。プレビューの向き・切り抜きを考慮してAVCaptureVideoPreviewLayerの座標変換を使います。スクロール操作、結果カードや終了ボタンの操作ではピントを動かしません。被写体が大きく変わった場合は中央の自動追従へ戻します。

バーコードは1080p（非対応時は720p等）の映像をAVCaptureMetadataOutputで検出します。対象領域は実際に表示されている映像の範囲で、AI用384pxの中央切り抜きには制限しません。検出が続かない場合はApple Visionでも高解像度画像を低頻度で調べます。HTMLへ送る画像は長辺320pxの小さなサムネイルにし、映像表示は引き続きネイティブプレビューで行います。

Gemmaが未起動でもバーコードは読めます。読めた商品コードを設定やAIの状態にかかわらず画面に表示します。JANコードには食品名や印字期限が含まれていないため、未登録の商品は編集で名称・期限を入力します。商品DB照会は本人が有効にした場合だけ行います。

Windowsのネイティブ代替検証で、AI未起動のバーコード受信、JPEGとは別の検出イベント、タップ/中央へのピント要求、スクロール時の除外、停止時の操作非表示、在庫保存・モバイル表示を確認しました。MacにはHD画像のEAN-13/QR認識、対象領域の除外、AI画像とサムネイルのサイズを確認する検査を追加しました。実機のピント・レンズ切り替え・撮影したコードの認識は、IPA更新後の確認が必要です。

### 公開成功例との差

v0.2.5は[公開実装](https://github.com/john-rocky/swift-litert-lm)の完全なコピーではありません。同じSDK 0.15.0・実機の生成GPU/画像CPU・コンテキスト2048・画像トークン280・ストリームAPIを採用していますが、次の差があります。

- 公開実装は画像枠を16に増やした独自Swiftラッパー、本アプリは公式ラッパーの既定値を使用。
- 公開実装の既定サンプリングはtopK 40・topP 0.95・temperature 0.8、本アプリはtopK 1・topP 1・temperature 0。
- 公開実装は短い「Hi」で事前生成してから会話を使い続ける構成、本アプリはBLUE-47の事前検査を行い、読み取りごとに新しい会話を作成。
- 公開成功例はiOS 27、本人の実機はiOS 26.6.2。

画像枠16は複数画像会話向けと判断して取り込んでいませんでしたが、初期化・メモリ確保に影響しないと検証したわけではありません。画像AIの次の切り分けでは、公開成功例そのものの最小実装で比較する必要があります。v0.2.6ではAIの設定を変更していません。

- Google LiteRT-LM Swift 0.15.0、v0.2.4では実機の生成をGPU（Metal）・画像エンコーダーをCPUに設定、コンテキスト上限2048・画像トークン280。Simulatorの生成はCPUで、実機GPUの検証とは区別します。
- iOS用Gemma 4 E2Bモデルは2,588,147,712バイト（約2.6GB）。Safari版のGPU用モデルとは別ファイルで、新しく取得します。
- モデルはアプリのApplication Supportへ保存し、起動し直した際は再利用します。AIのメモリへの読み込みはアプリの起動時やメモリ解放後に必要です。
- ファイル取り込みは`gemma-4-E2B-it.litertlm`用です。Google AI Edge Galleryなど別アプリ内の保存データを直接共有する機能はありません。
- カメラはAVFoundation、バーコードはApple Vision。画像推論は端末内で行い、画像をサーバーへ送りません。
- v0.2.2では映像の表示をAVCaptureVideoPreviewLayerへ切り替えました。AI用JPEGを約3fpsで作る処理と、画面へ映像を表示する処理を分けています。スクロール・画面サイズ変更時は表示枠を追従させ、カメラ停止・バックグラウンド移行時は隠します。
- AIの起動後に合成テスト画像で画像推論を確認します。失敗した場合は「準備完了」にせず、エラーを設定に表示します。ダウンロード済みモデルは残ります。
- 商品DB照会は初期OFFです。有効にした場合はOpen Food Factsへ商品コードだけ送ります。
- AIを使わなくても手入力・在庫・買い物・バックアップは利用できます。

アプリを削除すると保存データ・モデルも削除されます。バックグラウンド移行時はカメラを止め、AIメモリを解放します。ダウンロード途中で終了した場合は再取得になることがあります。

## Macで再ビルド

XcodeとHomebrewのあるMacで、リポジトリのルートから実行します。

```sh
bash scripts/build-ios.sh
```

成果物は`ios/build/ipa/Fridge-unsigned.ipa`です。Apple証明書・署名アカウントは使わず、インストール時にAltStoreが署名します。モデルの重みはIPAに含めません。Swift Packageの取得にはネット接続が必要です。

```sh
bash scripts/test-ios.sh
```

こちらはiOS Simulatorで手入力・再起動後の在庫保存・ネイティブAIの設定表示を確認します。シミュレーターの検証では、実機のカメラや2.6GBモデルの推論速度は確認できません。

```sh
bash scripts/test-ios-runtime.sh
```

実際の2.6GBモデルを取得し、同じSwift SDKとアプリのAI実装で、起動時の画像テスト・文字列BLUE-47への回答・320px/384pxのJPEG画像認識をiOS Simulatorで検証します。画像はテスト内で作成し、写真をアップロードしません。GitHub Actionsではこの検証と在庫のUIテストが成功した場合だけIPAを配布します。

Windows単独ではApple公式Simulatorを動かせません。WindowsではWeb画面・在庫処理を検証し、iOS固有部分をMacのCIでまとめて確認します。SimulatorはMacのCPU/GPUとメモリで動作するため、iPhoneのメモリ不足・カメラの速度・実機固有のランタイム不具合は保証できません。本人のiPhoneではv0.2.1のAI初期化は成功しましたが、最初の画像推論で`Failed to allocate tensors`が出ています。同様の[iOSでの報告](https://github.com/google-ai-edge/LiteRT-LM/issues/2979)があり、実機での画像推論の解消は未確認です。

## 実機で確認すること

v0.2.3は[Mac CIの実モデル・在庫UIテスト](https://github.com/mugi0227/refrigerator-assistant/actions/runs/37773223614)に成功しました。文章生成CPU・画像GPUの構成で、起動時の合成画像テスト、BLUE-47への回答、320px/384px JPEGへのRedの回答を確認しています。生成もGPUにした構成はSimulatorのMetalリソース制約で初期化に失敗したため、採用していません。

2026/10/08、本人のiPhoneではv0.2.3の起動時画像テストが`Failed to create conversation / Failed to modify graph with delegate`で失敗しました。画像を送る前の画像エンコーダー準備で失敗しています。モデルは保存済みです。[実機で成功した公開実装](https://github.com/john-rocky/swift-litert-lm)はLiteRT-LM **0.15.0**・生成GPU・画像CPU・画像トークン280を使用し、画像GPUではSTABLEHLO_COMPOSITEの準備に失敗すると報告しています。これは今回のエラーと整合しますが、こちらの実機の詳細ログで同じ原因かは未確認です。0.18.0のCPU画像処理も本人の実機では失敗しており、SDKの版の違いを含めた調査が必要です。実機の食品認識は未達です。

Windowsで実機ログを確認するには、iPhoneをUSBで接続・ロック解除し、リポジトリ直下の`Capture-iPhone-Logs.cmd`を実行してからFridgeで「保存したモデルで起動」を押します。既存のBackburner用Python環境のpymobiledevice3を利用します。3分間、Fridgeプロセスのログだけを`local/fridge-iphone-日時.jsonl`へ記録します。Appleの信頼・ペアリングが必要です。端末情報は機種識別子・iOS版・ビルド番号に絞り、アプリの削除やモデル再取得は行いません。未接続時の終了と、以下の実機からのログ取得を確認済みです。

同日、USB接続の実機`iPhone18,1`・iOS 26.6.2からFridgeのログを取得できました。v0.2.3の起動検査で`Node number 138 (STABLEHLO_COMPOSITE) failed to prepare.`を2回確認し、GPU画像処理の失敗と確認しました。記録は`local/fridge-iphone-20261008-224443.jsonl`です。ログがPCへ届くまで時間がかかることがあるため、取得途中の0バイトだけで取得失敗と判断しないでください。

v0.2.4は実機の成功例に合わせてSDK 0.15.0・生成GPU・画像CPUへ変更し、古いSDKのコンパイルキャッシュを別ディレクトリに隔離します。保存済みのモデルはそのまま使います。起動検査は合成赤色画像への回答が`red`を含むことまで確認し、失敗した場合は準備完了としません。新しい検証結果が出るまでは実機での解消を保証しません。SimulatorはSDK 0.15.0のCPU生成・CPU画像処理を検証し、実機GPUの動作はiPhoneの起動検査・食品読み取りで確認します。

v0.2.4/build 5の[Mac CI](https://github.com/mugi0227/refrigerator-assistant/actions/runs/37787773816)は成功しました。実モデルのSHA256とサイズは上記と一致し、起動画像検査・BLUE-47・320px/384px JPEGへのRedの回答、再起動後の在庫保持を確認。実機用IPAには`device: Metal text + CPU vision`の構成が含まれ、ARM64・ASCII名・同一Bundle ID・ZIP CRC・バージョンを検証済みです。

同日の本人のiPhoneではv0.2.4も画像検査に失敗しました。USBログでSDK 0.15.0・実機の生成GPU/画像CPU、モデル初期化の成功、その直後の`Native sendMessage returned null`を確認しました。今回のログには内部のXNNPACKエラーが記録されておらず、[類似報告](https://github.com/google-ai-edge/LiteRT-LM/issues/2979)と同じ原因だと断定できません。証跡: `local/physical-ios-v0.2.4-diagnosis.json`。モデルの再ダウンロードは不要で、実機での画像認識は未達です。

v0.2.5/build 6では公式SDK 0.15.0を維持し、公開成功例と同じ`sendMessageStream`で回答を取得します。通常の`sendMessage`のC APIはエラー時にnullを返しますが、ストリームのコールバックは内部のエラー文字列をSwiftへ伝えます。文字列を集約して既存のJSON読み取りへ渡すため、画面側の返却形式は変わりません。短い文章で生成を事前に検査してから別の会話で赤い画像を検査し、文章と画像のどちらで失敗したかを区別します。入力も公開実装と同じ文章→画像の順にします。画像数16の設定は複数画像会話用の変更で、毎回1画像の本アプリには追加しません。

SwiftUIで画面本体をセーフエリア内へ配置し、背景色だけを端まで伸ばします。WKWebViewとネイティブカメラは同じコンテナ内にあるため、カメラの表示枠の座標系は維持されます。実モデルのテストには合成のMILKラベルと印字日付2026-10-31を読み、JSONの食品名・日付を照合する検査も追加しました。これは合成画像の検査で、実機の食品撮影・速度を保証するものではありません。

2026/10/09、v0.2.5の[Mac CI](https://github.com/mugi0227/refrigerator-assistant/actions/runs/37796150766)は成功しました。実モデルの起動検査・BLUE-47・320px/384px画像のRed・合成ラベルの`{"food":"MILK","date":"2026-10-31"}`を確認し、在庫の保存・再起動後の保持も成功しました。Simulatorのスクリーンショットで時計とロゴの重なりが解消したことを確認。52ユニットテストとWindowsのネイティブ代替画面検証も成功しています。

配布ファイルは`local/ios-v0.2.5/Fridge-0.2.5-AltStore.ipa`（約13.4MB）。ARM64・ASCII名・同一Bundle ID・ZIP CRC・版・実機用GPU生成/CPU画像の文字列・ストリームAPIと文章検査が含まれることを確認しました。証跡: 同ディレクトリの`verification.json`。アプリを削除せずAltStoreで更新し、「保存したモデルで起動」で確認します。実機での解消は未確認です。失敗した場合は文章検査か画像検査かと内部エラーが表示されるため、その画面から次の調査へ進めます。

同日00:10の実機スクリーンショットでv0.2.5も画像検査に失敗したことを確認しました。ストリームAPIは`vision_litert_compiled_model_executor.cc:588 / Failed to invoke the compiled model`を返しています。画像検査まで進んでいるため、先行するBLUE-47の文章検査は通過しています。画像処理の不具合は未解消で、OS更新が解消策だとは未確認です。公開成功例はiPhone 17 Pro・iOS 27ですが、iOS 26から27へ更新した比較検証ではありません。証跡: `local/physical-ios-v0.2.5-diagnosis.json`。追加Macビルドは実施していません。

まずモデルの保存・起動、次にカメラ許可、牛乳の認識と印字された期限の読み取りを確認します。野菜の数量、二重登録の抑制、消費と取り消し、再起動後の在庫保存も確認してください。Safariより動きやすい構成を目指していますが、端末ごとのメモリ・速度・発熱は実機で確認が必要です。

公式資料：[LiteRT-LM Swift](https://developers.google.com/edge/litert-lm/swift)、[AltServer](https://faq.altstore.io/altstore-classic/altserver)、[AltStore Classic](https://faq.altstore.io/altstore-classic/your-altstore)。
