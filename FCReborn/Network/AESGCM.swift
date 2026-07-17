//
// AESGCM.swift
// FCReborn
//
// FlyingCarpet の暗号化フォーマット互換の AES-256-GCM 実装。
//
// Rust core/src/sending.rs encrypt_and_send_chunk:
//   nonce = random 12 bytes
//   ciphertext_with_tag = aes256gcm.encrypt(nonce, plaintext)
//   wire = nonce (12 bytes) || ciphertext_with_tag
//
// Rust core/src/receiving.rs receive_and_decrypt_chunk:
//   nonce = wire[0..12]
//   ciphertext_with_tag = wire[12..]
//
// CryptoKit の AES.GCM.seal(...).combined は
//   nonce (12 bytes) || ciphertext (N bytes) || tag (16 bytes)
// の順で結合されており、これはそのまま FlyingCarpet の wire フォーマットに一致する。
//

import Foundation
import CryptoKit

enum AESGCMFC {

    enum FCCryptoError: Error, LocalizedError {
        case sealFailed
        case openFailed
        case invalidCombinedLength

        var errorDescription: String? {
            switch self {
            case .sealFailed: return "AES-GCM 暗号化に失敗"
            case .openFailed: return "AES-GCM 復号に失敗 (改ざん検知/鍵不一致の可能性)"
            case .invalidCombinedLength: return "暗号化データが短すぎます"
            }
        }
    }

    /// 平文チャンクを暗号化し、wire フォーマット (nonce||ciphertext||tag) の Data を返す。
    static func seal(plaintext: Data, key: SymmetricKey) throws -> Data {
        let box = try AES.GCM.seal(plaintext, using: key)
        guard let combined = box.combined else { throw FCCryptoError.sealFailed }
        return combined
    }

    /// wire フォーマットの Data (nonce||ciphertext||tag) を復号して平文を返す。
    static func open(combined: Data, key: SymmetricKey) throws -> Data {
        // nonce 12 + tag 16 = 28 バイトが最低必要
        guard combined.count >= 28 else { throw FCCryptoError.invalidCombinedLength }
        do {
            let box = try AES.GCM.SealedBox(combined: combined)
            return try AES.GCM.open(box, using: key)
        } catch {
            throw FCCryptoError.openFailed
        }
    }
}
