//
//  CertificateStore.swift
//  ReStore
//
//  Created by Magesh K on 3/8/26.
//  Copyright © 2026 SideStore. All rights reserved.
//

import Foundation
import Security
import SideSign

public enum CertificateStore {
    /// Loads an ALTCertificate from PKCS#12 data. If password is provided, decrypts with password; if nil, loads unencrypted PKCS#12.
    public static func load(_ data: Data, password: String?) throws -> ALTCertificate {
        do {
            let certificate = try ALTCertificate(p12Data: data, password: password)
            try ImportedSigningValidation.validatePrivateKey(certificate)
            return certificate
        } catch {
            let parserError = error
            // Use the platform importer for archives our Swift parser cannot decode.
            var items: CFArray?
            let options = [kSecImportExportPassphrase as String: password ?? ""] as CFDictionary
            guard SecPKCS12Import(data as CFData, options, &items) == errSecSuccess,
                  let entries = items as? [[String: Any]] else { throw parserError }
            for entry in entries {
                guard let value = entry[kSecImportItemIdentity as String],
                      CFGetTypeID(value as CFTypeRef) == SecIdentityGetTypeID() else { continue }
                let identity = value as! SecIdentity
                var certificate: SecCertificate?
                var key: SecKey?
                guard SecIdentityCopyCertificate(identity, &certificate) == errSecSuccess,
                      SecIdentityCopyPrivateKey(identity, &key) == errSecSuccess,
                      let certificate, let key,
                      let keyData = SecKeyCopyExternalRepresentation(key, nil),
                      let x509 = ALTX509Certificate(data: SecCertificateCopyData(certificate) as Data) else { continue }
                let result = ALTCertificate(x509: x509, privateKey: keyData as Data)
                try ImportedSigningValidation.validatePrivateKey(result)
                return result
            }
            throw parserError
        }
    }

    static func normalizedSerial(_ serial: String) -> String {
        var result = serial.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if result.hasPrefix("0X") { result.removeFirst(2) }
        result.removeAll { $0 == ":" }
        while result.hasPrefix("0") && result.count > 1 { result.removeFirst() }
        return result
    }

    /// Never return the host's embedded key when a different account's certificate was requested.
    static func recover(_ data: Data, serialNumber: String, passwords: [String?]) -> ALTCertificate? {
        for password in passwords {
            guard let certificate = try? load(data, password: password),
                  serialNumber.isEmpty || normalizedSerial(certificate.serialNumber) == normalizedSerial(serialNumber) else { continue }
            return certificate
        }
        return nil
    }

    /// Exports an ALTCertificate to PKCS#12 data. If password is provided, encrypts PKCS#12 with password; if nil, exports unencrypted PKCS#12.
    public static func export(_ cert: ALTCertificate, password: String?) throws -> Data {
        if let password = password {
            return try cert.encryptedP12Data(password: password)
        } else {
            return try cert.unencryptedP12Data()
        }
    }
}
