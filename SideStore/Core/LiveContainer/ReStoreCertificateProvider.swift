#if os(iOS)
import Foundation
import SideSign

@objc(ReStoreCertificateProvider)
final class ReStoreCertificateProvider: NSObject {
    private static let hostMetadata: (serial: String?, appGroup: String?) = (
        CertificateManager.shared.getSigningCertificate(at: Bundle.main.bundleURL)?.serialNumber,
        Bundle.main.altstoreAppGroup
    )

    static func prepareHost() { _ = hostMetadata }

    private static var hostCertificate: ALTCertificate? {
        hostMetadata.serial.flatMap { CertificateManager.shared.getSignableCertificate(for: $0) }
    }

    @objc static func certificateData() -> NSData? {
        guard let certificate = hostCertificate,
              let data = try? CertificateStore.export(certificate, password: certificate.serialNumber) else { return nil }
        return data as NSData
    }

    @objc static func certificatePassword() -> NSString? {
        hostCertificate?.serialNumber as NSString?
    }

    @objc static func appGroupIdentifier() -> NSString? {
        hostMetadata.appGroup as NSString?
    }
}
#endif
