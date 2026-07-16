//
// Protocol.swift
// FCReborn
//
// FlyingCarpet v9 プロトコル互換の定数。
// 参照: spieglt/FlyingCarpet (core/src/linux/bluetooth.rs, Android/.../Bluetooth.kt)
//

import Foundation
import CoreBluetooth

enum FCProtocol {
    /// メジャーバージョン。相手側 (Android v9) と一致させる。
    static let majorVersion: UInt64 = 9

    /// 転送プロトコル用 TCP ポート。
    static let tcpPort: UInt16 = 3290

    /// 1 チャンクの平文サイズ (1MB)。
    /// 暗号化後はここに nonce(12) + tag(16) が加算される。
    static let chunkSize: Int = 1_000_000

    /// AES-GCM の nonce サイズ (バイト)。
    static let nonceSize: Int = 12

    /// SHA-256 の出力サイズ (バイト)。
    static let hashSize: Int = 32

    /// パスワード長 (文字数)。
    static let passwordLength: Int = 8

    /// パスワード用文字集合 (Rust core/src/utils.rs generate_password と一致)。
    static let passwordAlphabet: [Character] = Array(
        "23456789abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ"
    )

    /// FlyingCarpet の GATT サービス UUID。
    static let serviceUUID = CBUUID(string: "A70BF3CA-F708-4314-8A0E-5E37C259BE5C")

    /// OS 名 (utf-8) を read/write する Characteristic。
    static let osCharacteristicUUID = CBUUID(string: "BEE14848-CC55-4FDE-8E9D-2E0F9EC45946")

    /// Wi-Fi ホットスポットの SSID を read/write する Characteristic。
    static let ssidCharacteristicUUID = CBUUID(string: "0D820768-A329-4ED4-8F53-BDF364EDAC75")

    /// Wi-Fi ホットスポットのパスワードを read/write する Characteristic。
    static let passwordCharacteristicUUID = CBUUID(string: "E1FA8F66-CF88-4572-9527-D5125A2E0762")

    /// iOS が peer に自分の OS を報告するときの文字列。
    static let selfOSString: String = "ios"

    /// iOS は常に Wi-Fi ホットスポットを立てられない (プログラムから hotspot を提供不可)。
    /// 従って peer が iOS 以外なら常に peer 側がホットスポットを立てる。
    /// 参照:
    ///   - Rust core: is_hosting(Peer::IOS, _) == true (自分が Windows/Linux の場合)
    ///   - Android: isHosting() = peer == iOS || peer == macOS || (Android && Receiving)
    /// どちらから見ても iOS 相手なら相手側が立てる、で一致する。
    static func peerHostsHotspot(peerOS: String) -> Bool {
        return Peer(osString: peerOS) != .ios
    }
}
