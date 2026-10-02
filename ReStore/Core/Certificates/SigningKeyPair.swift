import Foundation
import Security

enum SigningKeyPair {
    enum ValidationError: LocalizedError {
        case invalidCertificate, invalidPrivateKey, mismatchedKey

        var errorDescription: String? {
            switch self {
            case .invalidCertificate: return "The signing certificate could not be read."
            case .invalidPrivateKey: return "The private key could not be read. Use an unencrypted RSA key in PEM or DER format."
            case .mismatchedKey: return "The private key does not match the selected certificate."
            }
        }
    }

    /// Validate the actual key pair without exporting and re-importing a PKCS#12 archive.
    static func validate(certificateData: Data, privateKeyData: Data) throws {
        guard let certificateDER = decodePEMOrDER(certificateData, labels: ["CERTIFICATE"]),
              let certificate = SecCertificateCreateWithData(nil, certificateDER as CFData),
              let certificateKey = SecCertificateCopyKey(certificate) else {
            throw ValidationError.invalidCertificate
        }
        guard let keyDER = decodePEMOrDER(privateKeyData, labels: ["RSA PRIVATE KEY", "PRIVATE KEY"]),
              let privateKey = SecKeyCreateWithData(unwrapPKCS8(keyDER) as CFData, [
                kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
                kSecAttrKeyClass as String: kSecAttrKeyClassPrivate
              ] as CFDictionary, nil),
              let publicKey = SecKeyCopyPublicKey(privateKey),
              let keyBytes = SecKeyCopyExternalRepresentation(publicKey, nil),
              let certificateBytes = SecKeyCopyExternalRepresentation(certificateKey, nil) else {
            throw ValidationError.invalidPrivateKey
        }
        guard keyBytes as Data == certificateBytes as Data else {
            throw ValidationError.mismatchedKey
        }
    }

    private static func decodePEMOrDER(_ data: Data, labels: [String]) -> Data? {
        guard !data.isEmpty else { return nil }
        guard let text = String(data: data, encoding: .utf8), text.contains("-----BEGIN ") else { return data }
        for label in labels {
            guard let start = text.range(of: "-----BEGIN \(label)-----"),
                  let end = text.range(of: "-----END \(label)-----", range: start.upperBound..<text.endIndex) else { continue }
            let base64 = text[start.upperBound..<end.lowerBound].filter { !$0.isWhitespace }
            return Data(base64Encoded: String(base64))
        }
        return nil
    }

    // Security imports RSA private keys as PKCS#1. iLoader also supplies PKCS#8 wrappers.
    private static func unwrapPKCS8(_ data: Data) -> Data {
        guard let sequence = readTLV(Array(data), offset: 0), sequence.tag == 0x30,
              sequence.end == data.count else { return data }
        let bytes = Array(sequence.value)
        guard let version = readTLV(bytes, offset: 0), version.tag == 0x02,
              let algorithm = readTLV(bytes, offset: version.end), algorithm.tag == 0x30,
              let key = readTLV(bytes, offset: algorithm.end), key.tag == 0x04 else { return data }
        return key.value
    }

    private static func readTLV(_ bytes: [UInt8], offset: Int) -> (tag: UInt8, value: Data, end: Int)? {
        guard offset >= 0, bytes.count - offset >= 2 else { return nil }
        var cursor = offset + 2
        var length = Int(bytes[offset + 1])
        if length & 0x80 != 0 {
            let count = length & 0x7f
            guard count > 0, count <= 4, count <= bytes.count - cursor else { return nil }
            length = 0
            for byte in bytes[cursor..<(cursor + count)] { length = (length << 8) | Int(byte) }
            cursor += count
        }
        guard length <= bytes.count - cursor else { return nil }
        return (bytes[offset], Data(bytes[cursor..<(cursor + length)]), cursor + length)
    }
}
