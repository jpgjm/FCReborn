# FCReborn

**Flying Carpet 互換 iOS アプリ (iOS 26 対応版)**

`spieglt/FlyingCarpet` プロトコル v9 と互換性を持ちつつ、iOS 26 で壊れた
NEHotspotConfiguration の自動接続を諦めて、Wi-Fi 参加を手動化することで
「iOS 26 + Android」のペア間でファイル送受信を復活させる非公式実装です。

- **無署名 IPA** (Free Apple ID / AltStore / Sideloadly 用)
- **iOS 18+ / iOS 26.5.2 対応**
- **相手デバイス: Android** (Flying Carpet v9)
- **UI: 日本語**

---

## 背景

Flying Carpet 公式 iOS 版は iOS 26 で壊れました。App Store の最新説明文に
作者本人が以下のように記載しています:

> Due to suspected changes in iOS, the functionality to join WiFi hotspots is currently broken.
> I hope to fix this in version 10 around mid-July 2026.

これは iOS 側で `NEHotspotConfiguration` によるプログラム経由の Wi-Fi 参加が
機能しなくなったことが原因と推測されています (Issue #131 と一致)。

このリポジトリでは、**Wi-Fi 参加をあえて手動にする** ことで問題を回避します。
副次的に無署名 IPA でも動作するようになります (無署名では
`com.apple.developer.networking.HotspotConfiguration` entitlement が付与できないため)。

---

## 使い方

### 準備

1. Android 端末に **Flying Carpet v9** をインストール (公式アプリ)。
2. iOS 端末に本アプリをインストール (下記のインストール方法参照)。
3. 両端末で Bluetooth と Wi-Fi を ON。

### iOS 側 = 受信

1. アプリを起動 → 「受信 (Receive)」をタップ
2. Android 側で「送信 (Send)」を選び、ファイルを選択して開始
3. BLE ハンドシェイクが自動で行われ、Wi-Fi 情報が iOS に届く
4. **手動接続画面** で表示された SSID / パスワードをコピー
5. 「設定アプリを開く」→ Wi-Fi → 表示された SSID を選択 → パスワード貼付け → 接続
6. 本アプリに戻り「接続完了、次へ」をタップ
7. 転送が開始される
8. 受信したファイルは **Files アプリ → FCReborn → inbox** に保存される

### iOS 側 = 送信

1. アプリを起動 → 「送信 (Send)」→ ファイル選択 → 「転送開始」
2. Android 側で「受信 (Receive)」を選ぶ
3. 以下 iOS 側 = 受信 と同様のフローで、iOS が Android の立てた Wi-Fi に手動接続

---

## ビルド (GitHub Actions)

このリポジトリを **自分のアカウントに fork または新規リポジトリとして push** すると、
`.github/workflows/build-ipa.yml` が自動で走ります。

### 手動ビルドをトリガーする

1. GitHub 上でこのリポジトリを開く
2. **Actions** タブ → **Build unsigned IPA** ワークフロー
3. **Run workflow** ボタンをクリック
4. ワークフローが完了したら、右上の **Artifacts** から `FCReborn-unsigned-ipa` をダウンロード
5. zip を展開すると `FCReborn-unsigned.ipa` が入っている

### リリースを作る

`v` で始まるタグ (例: `v1.0.0`) を push すると、そのタグの Release にも
自動で IPA が添付されます。

```bash
git tag v1.0.0
git push origin v1.0.0
```

### ローカルでビルドする場合

macOS + Xcode 16 以上が必要。

```bash
brew install xcodegen
xcodegen generate
open FCReborn.xcodeproj
# または CLI から:
xcodebuild -project FCReborn.xcodeproj \
  -scheme FCReborn \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -archivePath build/FCReborn.xcarchive \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  archive
```

---

## インストール (Sideload)

無署名 IPA なので、以下のいずれかで自己署名して端末に入れます。

### AltStore (推奨、macOS/Windows/Linux)

1. [AltStore](https://altstore.io/) をインストール
2. AltServer を PC で起動
3. iPhone を USB 接続、AltStore を iPhone に入れる
4. iPhone を PC と同じ Wi-Fi に接続
5. iPhone 上の AltStore → **My Apps** → **+** ボタン → `FCReborn-unsigned.ipa` を選択
6. Apple ID でログイン (Free Apple ID で OK)
7. 7 日で署名が切れるので、AltStore を開いて再更新

### Sideloadly (macOS/Windows)

1. [Sideloadly](https://sideloadly.io/) をインストール
2. iPhone を USB 接続
3. Sideloadly に IPA をドラッグ&ドロップ
4. Apple ID を入力してサイドロード
5. iPhone の **設定 → 一般 → VPN とデバイス管理** で自分の Apple ID を **信頼**

### 制約

- Free Apple ID は **7 日で署名切れ** → 再度サイドロード必要
- 3 アプリまでしか同時に入れられない
- Local Network 権限は初回接続時にダイアログが出るので許可すること
- Bluetooth 権限も初回に許可すること

---

## 制限事項 / 既知の問題

- **Wi-Fi 参加は完全手動** (iOS 26 + 無署名の両制約により、自動化不可)
- **iOS 同士の転送は不可** (どちらも hotspot を立てられない)
- **相手が macOS の場合は未検証** (プロトコル上は動くはず)
- **Windows / Linux の場合は未検証** (プロトコル上は動くはず)
- **バックグラウンド動作は最小限**。転送中は画面 ON 推奨
- **Bluetooth ペアリング** が初回のみ必要 (iOS ↔ Android)。ダイアログが両端末に出るので許可

---

## プロトコル互換性

Rust の `spieglt/FlyingCarpet` core v9 を解析して以下と一致するように実装:

| 項目 | 値 |
|---|---|
| BLE Service UUID | `A70BF3CA-F708-4314-8A0E-5E37C259BE5C` |
| OS Characteristic | `BEE14848-CC55-4FDE-8E9D-2E0F9EC45946` |
| SSID Characteristic | `0D820768-A329-4ED4-8F53-BDF364EDAC75` |
| PASSWORD Characteristic | `E1FA8F66-CF88-4572-9527-D5125A2E0762` |
| TCP Port | 3290 |
| バージョン | 9 |
| 暗号化 | AES-256-GCM (SHA-256(pw) を鍵に、12バイト random nonce) |
| チャンクサイズ | 1,000,000 bytes |
| バイト順序 | Big Endian |

---

## ライセンス

MIT (元の FlyingCarpet と同じ)。ただしこれは非公式の互換実装であり、
Flying Carpet の公式版とは無関係です。

---

## 参考

- 元プロジェクト: https://github.com/spieglt/FlyingCarpet
- Issue #131: https://github.com/spieglt/FlyingCarpet/issues/131
