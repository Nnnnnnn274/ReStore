import Foundation
import Security

@main
struct SigningKeyPairRegressionTests {
    static func main() throws {
        let fixtures = URL(fileURLWithPath: CommandLine.arguments[1])
        func read(_ name: String) throws -> Data { try Data(contentsOf: fixtures.appendingPathComponent(name)) }
        func pem(_ data: Data, _ label: String) -> Data {
            Data("-----BEGIN \(label)-----\n\(data.base64EncodedString(options: .lineLength64Characters))\n-----END \(label)-----\n".utf8)
        }
        let der = try read("matching.der")
        let certificatePEM = try read("matching.crt")
        let pkcs1 = try read("matching.pkcs1")
        let pkcs8 = try read("matching.pkcs8")
        var passed = 0
        for certificate in [der, certificatePEM] {
            for key in [pkcs1, pkcs8, pem(pkcs1, "RSA PRIVATE KEY"), pem(pkcs8, "PRIVATE KEY")] {
                try SigningKeyPair.validate(certificateData: certificate, privateKeyData: key)
                passed += 1
            }
        }
        func reject(_ certificate: Data, _ key: Data, _ expected: SigningKeyPair.ValidationError) throws {
            do {
                try SigningKeyPair.validate(certificateData: certificate, privateKeyData: key)
                fatalError("Accepted an invalid certificate/key pair")
            } catch let error as SigningKeyPair.ValidationError {
                precondition(error.errorDescription == expected.errorDescription)
                passed += 1
            }
        }
        try reject(der, read("other.pkcs8"), .mismatchedKey)
        try reject(Data(), pkcs1, .invalidCertificate)
        try reject(Data([0x30, 0]), pkcs1, .invalidCertificate)
        try reject(der, Data(), .invalidPrivateKey)
        try reject(der, Data([0x30, 0x84, 0xff, 0xff, 0xff, 0xff]), .invalidPrivateKey)
        try reject(der, Data(pkcs8.dropLast(8)), .invalidPrivateKey)
        try reject(der, pem(pkcs8, "ENCRYPTED PRIVATE KEY"), .invalidPrivateKey)
        try reject(der, Data("-----BEGIN PRIVATE KEY-----\nnot-base64!\n-----END PRIVATE KEY-----".utf8), .invalidPrivateKey)
        var items: CFArray?
        let legacyStatus = SecPKCS12Import(try read("legacy.p12") as CFData,
                                          [kSecImportExportPassphrase as String: ""] as CFDictionary, &items)
        print("Previous PKCS#12 round-trip status: \(legacyStatus)")
        print("Passed \(passed) certificate/key regression checks (PEM, DER, PKCS#1, PKCS#8, mismatched and malformed keys).")
    }
}
