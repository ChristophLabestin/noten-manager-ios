// CryptoService.swift
import Foundation
import CryptoKit

enum CryptoService {
    // Base64 <-> Data
    static func base64Encode(_ data: Data) -> String {
        data.base64EncodedString()
    }

    static func base64Decode(_ b64: String) throws -> Data {
        if let d = Data(base64Encoded: b64) { return d }
        throw NSError(domain: "CryptoService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Ungültige Base64"])
    }

    // Salt erzeugen (default 16 Bytes), Base64-kodiert – kompatibel zum Web
    static func generateSalt(length: Int = 16) -> String {
        var bytes = [UInt8](repeating: 0, count: length)
        let status = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        precondition(status == errSecSuccess)
        return Data(bytes).base64EncodedString()
    }

    // PBKDF2-SHA256 (rein in Swift) -> 32 Bytes Key (256 Bit)
    static func deriveKeyFromPassword(password: String, saltBase64: String, iterations: Int = 150_000) throws -> SymmetricKey {
        let salt = try base64Decode(saltBase64)
        let keyData = try pbkdf2SHA256(password: password, salt: salt, iterations: iterations, keyLength: 32)
        return SymmetricKey(data: keyData)
    }

    // AES-GCM Encrypt: liefert "ivB64:ciphertextB64" (ciphertextB64 = ciphertext||tag)
    static func encryptString(_ plain: String, key: SymmetricKey) throws -> String {
        // 12-Byte IV
        var iv = [UInt8](repeating: 0, count: 12)
        let status = SecRandomCopyBytes(kSecRandomDefault, iv.count, &iv)
        precondition(status == errSecSuccess)
        let nonce = try AES.GCM.Nonce(data: Data(iv))

        let sealed = try AES.GCM.seal(Data(plain.utf8), using: key, nonce: nonce)
        // CryptoKit gibt ciphertext und tag separat
        let ct = sealed.ciphertext + sealed.tag
        let ivB64 = base64Encode(Data(iv))
        let ctB64 = base64Encode(ct)
        return "\(ivB64):\(ctB64)"
    }

    // AES-GCM Decrypt: erwartet "ivB64:ciphertextB64" (ciphertextB64 = ciphertext||tag)
    static func decryptString(_ payload: String, key: SymmetricKey) throws -> String {
        let parts = payload.split(separator: ":")
        guard parts.count == 2 else { throw NSError(domain: "CryptoService", code: -2, userInfo: [NSLocalizedDescriptionKey: "Ungültiges Ciphertext-Format"]) }
        let iv = try base64Decode(String(parts[0]))
        let ctAll = try base64Decode(String(parts[1]))

        // Tag ist 16 Bytes am Ende
        guard ctAll.count >= 16 else {
            throw NSError(domain: "CryptoService", code: -3, userInfo: [NSLocalizedDescriptionKey: "Ciphertext zu kurz"])
        }
        let tag = ctAll.suffix(16)
        let ciphertext = ctAll.prefix(ctAll.count - 16)

        let nonce = try AES.GCM.Nonce(data: iv)
        let sealed = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)
        let decrypted = try AES.GCM.open(sealed, using: key)
        guard let str = String(data: decrypted, encoding: .utf8) else {
            throw NSError(domain: "CryptoService", code: -4, userInfo: [NSLocalizedDescriptionKey: "UTF8-Dekodierung fehlgeschlagen"])
        }
        return str
    }

    // MARK: - PBKDF2-SHA256 (Swift-Implementierung)

    private static func pbkdf2SHA256(password: String, salt: Data, iterations: Int, keyLength: Int) throws -> Data {
        // PBKDF2: F = U1 ^ U2 ^ ... ^ Uc, mit U1 = PRF(P, S || INT_32_BE(i)), Uj = PRF(P, Uj-1)
        // PRF = HMAC-SHA256
        let blocks = Int(ceil(Double(keyLength) / 32.0))
        var derived = Data()
        let passwordKey = SymmetricKey(data: Data(password.utf8))

        for i in 1...blocks {
            // S || INT_32_BE(i)
            var blockData = Data()
            blockData.append(salt)
            var be = UInt32(i).bigEndian
            withUnsafeBytes(of: &be) { blockData.append(contentsOf: $0) }

            // U1
            var u = Data(HMAC<SHA256>.authenticationCode(for: blockData, using: passwordKey))
            var t = u

            // U2..Uc
            if iterations > 1 {
                for _ in 2...iterations {
                    u = Data(HMAC<SHA256>.authenticationCode(for: u, using: passwordKey))
                    // XOR
                    for j in 0..<t.count {
                        t[j] ^= u[j]
                    }
                }
            }

            derived.append(t)
        }

        return derived.prefix(keyLength)
    }
}
