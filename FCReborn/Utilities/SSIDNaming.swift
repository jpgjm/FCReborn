//
// SSIDNaming.swift
// FCReborn
//
// Rust core/src/utils.rs get_key_and_ssid 互換:
//   key = SHA-256(password)         // 32バイト
//   ssid = "flyingCarpet_" + hex(key[0]) + hex(key[1])
//

import Foundation
import CryptoKit

enum KeyAndSSID {
    struct Result {
        let key: SymmetricKey  // 32バイト AES-256 鍵
        let ssid: String       // "flyingCarpet_XX" 形式
    }

    static func derive(from password: String) -> Result {
        let hash = SHA256.hash(data: Data(password.utf8))
        let bytes = Array(hash)
        let ssid = String(format: "flyingCarpet_%02x%02x", bytes[0], bytes[1])
        return Result(
            key: SymmetricKey(data: Data(bytes)),
            ssid: ssid
        )
    }
}
