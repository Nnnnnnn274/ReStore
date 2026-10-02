import Foundation
import Security
import SideSign

enum ImportedSigningValidation {
    static func validatePrivateKey(_ certificate: ALTCertificate) throws {
        guard let data = certificate.data else {
            throw OperationError.invalidParameters("The signing certificate contains no X.509 data.")
        }
        try SigningKeyPair.validate(certificateData: data, privateKeyData: certificate.privateKey)
    }

    static func permits(_ profile: ALTProvisioningProfile, bundleIdentifier: String) -> Bool {
        let pattern = profile.bundleIdentifier
        guard !bundleIdentifier.isEmpty, !bundleIdentifier.contains("*") else { return false }
        if pattern == "*" { return true }
        if pattern.hasSuffix(".*") {
            return bundleIdentifier.hasPrefix(String(pattern.dropLast())) && !bundleIdentifier.contains("*")
        }
        return pattern == bundleIdentifier
    }

    static func validate(_ profile: ALTProvisioningProfile, certificate: ALTCertificate,
                         bundleIdentifier: String? = nil, deviceID: String? = nil) throws {
        guard profile.expirationDate > Date() else {
            throw OperationError.invalidParameters("This provisioning profile has expired. Import a renewed profile in Signing.")
        }
        guard certificate.x509.expiryDate > Date() else {
            throw OperationError.invalidParameters("This signing certificate has expired. Import a renewed certificate in Signing.")
        }
        guard profile.certificates.contains(where: { $0.data == certificate.data && $0.data != nil }) else {
            throw OperationError.invalidParameters("The provisioning profile does not authorize this signing certificate.")
        }
        if let bundleIdentifier, !permits(profile, bundleIdentifier: bundleIdentifier) {
            throw OperationError.invalidParameters("Profile '\(profile.name)' does not authorize '\(bundleIdentifier)'. Import a matching or wildcard profile.")
        }
        if !profile.deviceIDs.isEmpty, let deviceID, !profile.deviceIDs.contains(deviceID) {
            throw OperationError.invalidParameters("This device is not included in the provisioning profile.")
        }
        try validatePrivateKey(certificate)
    }
}
