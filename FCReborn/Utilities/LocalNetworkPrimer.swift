//
// LocalNetworkPrimer.swift
// FCReborn
//
// iOS 14+ の Local Network Permission ダイアログを確実に表示させるためのヘルパ。
//
// NWConnection で直接 IP に繋ぐだけではダイアログが出ないことがあるので、
// NWBrowser で bonjour ブラウズを短時間走らせて、iOS に「このアプリはローカルネットワークを
// 使う気がある」ことを明示する。
//
// 参考:
//   - Info.plist に NSBonjourServices が宣言されていないと NWBrowser がすぐ fail する
//   - 一度でも許可 (or 拒否) すれば、次回以降ダイアログは出ない
//   - このダミーブラウザは実際のマッチングを期待しない (すぐ cancel する)
//

import Foundation
import Network

enum LocalNetworkPrimer {

    /// Bonjour ブラウザを最大 `seconds` 秒起動して、Local Network Permission ダイアログを発火させる。
    /// 完了 (成功 or タイムアウト) したら return する。
    static func prime(seconds: TimeInterval = 1.5, log: @escaping (String) -> Void) async {
        log("[LNP] prime() 開始 — Bonjour ブラウザで Local Network 権限プロンプトを発火します")
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            let params = NWParameters()
            params.includePeerToPeer = true

            let browser = NWBrowser(
                for: .bonjour(type: "_flyingcarpet._tcp", domain: nil),
                using: params
            )
            var didFinish = false
            let finish: () -> Void = {
                if didFinish { return }
                didFinish = true
                browser.cancel()
                cont.resume()
            }

            browser.stateUpdateHandler = { state in
                log("[LNP] browser state: \(state)")
                switch state {
                case .ready:
                    // ready になった時点で iOS はすでにダイアログを出しているので少し待って cancel
                    DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
                        finish()
                    }
                case .failed(let err):
                    log("[LNP] browser failed: \(err)")
                    finish()
                case .cancelled:
                    finish()
                default:
                    break
                }
            }
            browser.browseResultsChangedHandler = { _, _ in
                // ダミー、結果は使わない
            }

            browser.start(queue: .main)

            // フォールバックのタイムアウト
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds + 0.5) {
                log("[LNP] prime() タイムアウト到達 → cancel")
                finish()
            }
        }
        log("[LNP] prime() 終了")
    }
}
