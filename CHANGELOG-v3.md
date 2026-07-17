# v3 変更点 (バージョン識別の徹底)

## 何が起きたか (v2 での症状)

Sideloadly で入れ直したのに、ログには v2 で追加したはずの `[LNP]` / `[NW]` プレフィックスの
ログが 1 行も出ていない、かつ TCP timeout の間隔が v1 と一致 (4-5秒間隔) していた。

**推定原因**: Sideloadly が入れた IPA が v2 ではなく v1 のまま (どの Artifact を使ったか、
または Bundle Version が同じで iPad 側の上書きが不完全) の可能性が高い。

## v3 の変更

### バージョン識別を徹底
- `CFBundleShortVersionString` を **1.2.0** に、`CFBundleVersion` を **3** に bump
  - iOS 側で「新しいアプリ」と認識され上書きが確実に効く
- `AppVersion.swift` を新規追加、buildTag = `"v1.2.0 (build 3) [FCReborn v3]"`
- **アプリ起動直後にログの先頭にバージョンを刻む**:
  ```
  ========================================
  FCReborn v1.2.0 (build 3) [FCReborn v3] 起動
  ========================================
  ```

### ログの強化
- `LocalNetworkPrimer.prime()` の入口・出口で **必ずログ出力**
- `TransferSession.connect()` の入口で **必ずログ出力**
- `NWConnection.pathUpdateHandler` で **`unsatisfiedReason`** も出力
  - `localNetworkDenied` / `notAvailable` / `cellularDenied` などの判別が可能に

## v3 で必ず見えるべきログ

Sideloadly で v3 IPA を入れて起動すると、**アプリを開いた瞬間** にログの先頭に:

```
[XX:XX:XXZ] ========================================
[XX:XX:XXZ] FCReborn v1.2.0 (build 3) [FCReborn v3] 起動
[XX:XX:XXZ] ========================================
```

が **必ず** 出ます。これが出なければ v3 IPA ではありません。

Receive/Send を開始したあとの TCP フェーズでは:

```
[XX:XX:XXZ] Local Network 権限プロンプトを表示 (初回のみ)
[XX:XX:XXZ] [LNP] prime() 開始 — Bonjour ブラウザで Local Network 権限プロンプトを発火します
[XX:XX:XXZ] [LNP] browser state: ready
[XX:XX:XXZ] [LNP] browser state: cancelled
[XX:XX:XXZ] [LNP] prime() 終了
[XX:XX:XXZ] gateway = 10.172.239.1:3290
[XX:XX:XXZ] iPad Wi-Fi IP = 10.172.239.X
[XX:XX:XXZ] [NW] connect(gateway=10.172.239.1:3290, timeout=6.0s) 開始
[XX:XX:XXZ] [NW] path: status=... interfaces=[en0(wifi)] unsatisfiedReason=...
[XX:XX:XXZ] [NW] state: preparing
[XX:XX:XXZ] [NW] state: waiting(...) or ready
```

**もしこれが出ないなら v3 IPA が正しくインストールされていません。**

## 確認手順

1. GitHub でこのリポジトリを push → Actions で **手動で** `Build unsigned IPA` を Run
2. 完了した Actions run のページから **その run の Artifact** をダウンロード
   (他の run の Artifact ではなく、今 push した v3 の run のもの)
3. Zip を展開して `FCReborn-unsigned.ipa` を取り出す
4. Sideloadly で iPad に入れる (旧バージョンは削除しなくても version bump で上書きされるはず)
5. iPad で FCReborn を起動 → 「受信」ボタンを押す
6. **アプリを起動した瞬間** にログの一番上に `FCReborn v1.2.0 (build 3)` が出るか確認 ← ★

## 万が一 v3 でも同じログしか出ないなら

原因が完全に別 (iOS 26 の networking regression 本体) なので、
v4 で BSD socket 直接叩き実装に切り替えます。
