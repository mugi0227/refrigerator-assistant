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

- Google LiteRT-LM Swift 0.18.0、v0.2.3では生成をCPU・画像エンコーダーをGPU（Metal）に設定、コンテキスト上限2048。画像処理をCPU/XNNPACKから切り離す構成です。
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

v0.2.3は[Mac CIの実モデル・在庫UIテスト](https://github.com/mugi0227/refrigerator-assistant/actions/runs/37773223614)に成功しました。文章生成CPU・画像GPUの構成で、起動時の合成画像テスト、BLUE-47への回答、320px/384px JPEGへのRedの回答を確認しています。生成もGPUにした構成はSimulatorのMetalリソース制約で初期化に失敗したため、採用していません。v0.2.3の実機の食品認識・速度はまだ未確認です。

まずモデルの保存・起動、次にカメラ許可、牛乳の認識と印字された期限の読み取りを確認します。野菜の数量、二重登録の抑制、消費と取り消し、再起動後の在庫保存も確認してください。Safariより動きやすい構成を目指していますが、端末ごとのメモリ・速度・発熱は実機で確認が必要です。

公式資料：[LiteRT-LM Swift](https://developers.google.com/edge/litert-lm/swift)、[AltServer](https://faq.altstore.io/altstore-classic/altserver)、[AltStore Classic](https://faq.altstore.io/altstore-classic/your-altstore)。
