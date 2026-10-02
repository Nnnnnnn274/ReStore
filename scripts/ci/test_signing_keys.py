"""Exercise the production key validator on macOS using disposable OpenSSL identities."""
import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[2]


def run(*args):
    result = subprocess.run(args, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    if result.returncode:
        sys.stderr.write(result.stderr.decode(errors="replace"))
        result.check_returncode()


def tlv(tag, value):
    length = len(value)
    if length < 128:
        encoded_length = bytes([length])
    else:
        encoded = length.to_bytes((length.bit_length() + 7) // 8, "big")
        encoded_length = bytes([0x80 | len(encoded)]) + encoded
    return bytes([tag]) + encoded_length + value


def read_tlv(data, offset=0):
    tag, length = data[offset:offset + 2]
    offset += 2
    if length & 0x80:
        size = length & 0x7F
        length = int.from_bytes(data[offset:offset + size], "big")
        offset += size
    return tag, data[offset:offset + length], offset + length


def main():
    with tempfile.TemporaryDirectory(prefix="restore-signing-tests-") as directory:
        fixtures = pathlib.Path(directory)
        for name in ["matching", "other"]:
            run("openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes",
                "-keyout", str(fixtures / f"{name}.pem"), "-out", str(fixtures / f"{name}.crt"),
                "-days", "1", "-subj", f"/CN=ReStore Test {name}")
            run("openssl", "pkcs8", "-topk8", "-nocrypt", "-in", str(fixtures / f"{name}.pem"),
                "-outform", "DER", "-out", str(fixtures / f"{name}.pkcs8"))
        run("openssl", "x509", "-in", str(fixtures / "matching.crt"),
            "-outform", "DER", "-out", str(fixtures / "matching.der"))
        # Extract the PKCS#1 fixture independently from OpenSSL's PKCS#8 wrapper.
        pkcs8 = (fixtures / "matching.pkcs8").read_bytes()
        _, body, _ = read_tlv(pkcs8)
        _, _, offset = read_tlv(body)
        _, _, offset = read_tlv(body, offset)
        tag, pkcs1, _ = read_tlv(body, offset)
        assert tag == 0x04
        (fixtures / "matching.pkcs1").write_bytes(pkcs1)

        # Reproduce the MAC-less archive built by our pinned CodeSignKit builder.
        oid_data = bytes.fromhex("06092a864886f70d010701")
        key_bag = bytes.fromhex("060b2a864886f70d010c0a0101")
        cert_bag = bytes.fromhex("060b2a864886f70d010c0a0103")
        x509_oid = bytes.fromhex("060a2a864886f70d01091601")
        def content(bags):
            return tlv(0x30, oid_data + tlv(0xA0, tlv(0x04, tlv(0x30, bags))))
        key_content = content(tlv(0x30, key_bag + tlv(0xA0, pkcs8)))
        cert_value = tlv(0x30, x509_oid + tlv(0xA0, tlv(0x04, (fixtures / "matching.der").read_bytes())))
        cert_content = content(tlv(0x30, cert_bag + tlv(0xA0, cert_value)))
        auth_safe = tlv(0x30, key_content + cert_content)
        archive = tlv(0x30, tlv(0x02, b"\x03") + tlv(0x30, oid_data + tlv(0xA0, tlv(0x04, auth_safe))))
        (fixtures / "legacy.p12").write_bytes(archive)
        executable = fixtures / "signing-tests"
        run("xcrun", "swiftc", str(ROOT / "ReStore/Core/Certificates/SigningKeyPair.swift"),
            str(ROOT / "scripts/ci/test_signing_keys.swift"), "-o", str(executable))
        subprocess.run([str(executable), str(fixtures)], check=True)


if __name__ == "__main__":
    main()
