//
// WiFiHelper.swift
// FCReborn
//
// v5: Bridging Header 経由で <net/route.h> の RTF_GATEWAY / rt_msghdr / RTA_DST を使えるようにし、
// sysctl(PF_ROUTE) を叩いて実際の default gateway を取得。
//

import Foundation
import Network
import Darwin
#if canImport(UIKit)
import UIKit
#endif

enum WiFiHelper {

    /// 現在のデフォルトゲートウェイ IPv4 アドレスをルーティングテーブルから取得する。
    /// 取れなければ nil。
    ///
    /// 実装:
    ///   sysctl(CTL_NET, PF_ROUTE, 0, AF_INET, NET_RT_DUMP, 0) で route dump を取得し、
    ///   RTF_GATEWAY + RTF_UP のエントリで destination = 0.0.0.0 (default) のものを探す。
    static func defaultGatewayIP() -> String? {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, Int32(AF_INET), NET_RT_DUMP, 0]
        var len = 0

        // まず必要バッファサイズを取得
        if sysctl(&mib, u_int(mib.count), nil, &len, nil, 0) < 0 {
            return nil
        }
        guard len > 0 else { return nil }

        var buf = [UInt8](repeating: 0, count: len)
        let getResult = buf.withUnsafeMutableBufferPointer { (bufPtr) -> Int32 in
            var l = len
            return sysctl(&mib, u_int(mib.count), bufPtr.baseAddress, &l, nil, 0)
        }
        if getResult < 0 { return nil }

        // withUnsafeBufferPointer のクロージャ内でパースを完結させる
        return buf.withUnsafeBufferPointer { bufPtr -> String? in
            guard let base = bufPtr.baseAddress else { return nil }
            var offset = 0
            while offset < len {
                let msgPtr = base.advanced(by: offset)
                let rtmPtr = UnsafeRawPointer(msgPtr).assumingMemoryBound(to: rt_msghdr.self)
                let msgLen = Int(rtmPtr.pointee.rtm_msglen)
                if msgLen <= 0 { break }

                let flags = rtmPtr.pointee.rtm_flags
                if (flags & RTF_UP) != 0 && (flags & RTF_GATEWAY) != 0 {
                    let addrs = rtmPtr.pointee.rtm_addrs
                    let saStart = UnsafeRawPointer(rtmPtr).advanced(by: MemoryLayout<rt_msghdr>.size)
                    let msgEnd = UnsafeRawPointer(msgPtr).advanced(by: msgLen)
                    if let (dest, gw) = extractDestAndGateway(from: saStart, addrs: addrs, msgEnd: msgEnd) {
                        if dest == "0.0.0.0" || dest.isEmpty {
                            return gw
                        }
                    }
                }
                offset += msgLen
            }
            return nil
        }
    }

    /// route message から destination と gateway の IPv4 文字列を取り出す。
    /// addrs は「どの address slot が入っているか」のビットマスク (RTA_DST=1, RTA_GATEWAY=2, ...)
    private static func extractDestAndGateway(from base: UnsafeRawPointer, addrs: Int32, msgEnd: UnsafeRawPointer) -> (dest: String, gateway: String)? {
        var cursor = base
        var dest: String = ""
        var gw: String = ""
        for i in 0..<8 {
            let bit: Int32 = 1 << i
            if (addrs & bit) == 0 { continue }
            if cursor >= msgEnd { break }
            let sa = cursor.assumingMemoryBound(to: sockaddr.self)
            let saLen = Int(sa.pointee.sa_len)
            if saLen == 0 {
                cursor = cursor.advanced(by: 4)
                continue
            }
            if sa.pointee.sa_family == UInt8(AF_INET) {
                let sin = cursor.assumingMemoryBound(to: sockaddr_in.self)
                var addr = sin.pointee.sin_addr
                var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                inet_ntop(AF_INET, &addr, &buffer, socklen_t(INET_ADDRSTRLEN))
                let ipStr = String(cString: buffer)
                if bit == RTA_DST { dest = ipStr }
                else if bit == RTA_GATEWAY { gw = ipStr }
            }
            // sockaddr は 4 バイト align される (BSD の SA_SIZE 相当)
            let aligned = (saLen == 0) ? 4 : ((saLen + 3) & ~3)
            cursor = cursor.advanced(by: aligned)
        }
        if gw.isEmpty { return nil }
        return (dest, gw)
    }

    /// gateway 候補リスト。ルーティングテーブルから取得したものを先頭に、
    /// 汎用的な候補 (Android LocalOnlyHotspot 標準、Windows Mobile Hotspot、Personal Hotspot) を後続に置く。
    static func gatewayCandidates() -> [String] {
        var out: [String] = []
        if let gw = defaultGatewayIP() {
            out.append(gw)
        }
        if let ip = interfaceIPv4Address(name: "en0") {
            let parts = ip.split(separator: ".").map(String.init)
            if parts.count == 4 {
                let subnet = "\(parts[0]).\(parts[1]).\(parts[2])"
                for last in [1, 254, 2, 100] {
                    let c = "\(subnet).\(last)"
                    if !out.contains(c) { out.append(c) }
                }
            }
        }
        for c in [
            "192.168.49.1",   // Android LocalOnlyHotspot 標準
            "192.168.43.1",   // Samsung 系
            "192.168.42.1",   // 一部 Android
            "192.168.137.1",  // Windows Mobile Hotspot
            "172.20.10.1"     // iOS Personal Hotspot
        ] {
            if !out.contains(c) { out.append(c) }
        }
        return out
    }

    /// 指定インターフェース名の IPv4 アドレスを返す。
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

    /// 全 IPv4 インターフェース (名前 → IP) の一覧をデバッグ用に返す。
    static func allInterfaceAddresses() -> [(name: String, ip: String)] {
        var results: [(String, String)] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return [] }
        defer { freeifaddrs(ifaddr) }

        var ptr = firstAddr
        while true {
            let interface = ptr.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family
            if addrFamily == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                getnameinfo(interface.ifa_addr,
                            socklen_t(interface.ifa_addr.pointee.sa_len),
                            &hostname,
                            socklen_t(hostname.count),
                            nil,
                            0,
                            NI_NUMERICHOST)
                results.append((name, String(cString: hostname)))
            }
            guard let next = interface.ifa_next else { break }
            ptr = next
        }
        return results
    }

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
