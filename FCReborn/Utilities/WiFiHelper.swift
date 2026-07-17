//
// WiFiHelper.swift
// FCReborn
//
// 現在接続中の Wi-Fi の SSID とゲートウェイ IP を取得するヘルパ。
//
// 制約 (無署名 IPA 前提):
//   - CNCopyCurrentNetworkInfo: iOS 14+ では entitlement 必須 → 使用不可
//   - NEHotspotNetwork.fetchCurrent: entitlement 必須 → 使用不可
//   - NWPathMonitor: interface が "en0" (Wi-Fi) かは分かるが SSID は取れない
//   - Route/ARP からゲートウェイを引く: 素の getifaddrs で自機の IP は取れるので、
//     ここから /24 の .1 を推定する
//
// つまり SSID は "手動で設定 → 接続してください" と UI に案内し、
// gateway IP はコードで取得する。gateway IP が取れれば TCP 接続は可能。
//

import Foundation
import Network
import Darwin
#if canImport(UIKit)
import UIKit
#endif

enum WiFiHelper {

    /// 現在の Wi-Fi (en0) 経由のデフォルトゲートウェイ IP を取得する。
    /// 取れなければ nil。
    ///
    /// 実装は簡易的で、自機の IPv4 が取れたら同じ /24 の .1 を返す。
    /// Android LocalOnlyHotspot は 192.168.49.1、
    /// Windows Mobile Hotspot は 192.168.137.1、
    /// Personal Hotspot 系は 172.20.10.1 で、いずれも .1 なので通常一致する。
    static func defaultGatewayIP() -> String? {
        if let ip = interfaceIPv4Address(name: "en0") {
            let parts = ip.split(separator: ".").map(String.init)
            if parts.count == 4 {
                return "\(parts[0]).\(parts[1]).\(parts[2]).1"
            }
        }
        return nil
    }

    /// 指定インターフェース名 (例: "en0") の IPv4 アドレスを返す。
    static func interfaceIPv4Address(name interfaceName: String) -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        var ptr = firstAddr
        while true {
            let interface = ptr.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family
            if addrFamily == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                if name == interfaceName {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(interface.ifa_addr,
                                socklen_t(interface.ifa_addr.pointee.sa_len),
                                &hostname,
                                socklen_t(hostname.count),
                                nil,
                                0,
                                NI_NUMERICHOST)
                    address = String(cString: hostname)
                    break
                }
            }
            guard let next = interface.ifa_next else { break }
            ptr = next
        }
        return address
    }

    /// アプリから設定アプリを開く。iOS 15+ で "App-Prefs:root=WIFI" は動かないため
    /// 実質的に自アプリの設定ページを開くのみ。ユーザーは Back で Wi-Fi 設定へ遷移する。
    @MainActor
    static func openSettings() {
        #if canImport(UIKit)
        if let url = URL(string: "App-Prefs:root=WIFI"), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
            return
        }
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
        #endif
    }
}
