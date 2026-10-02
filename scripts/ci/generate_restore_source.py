"""Publish this build's ReStore source alongside its IPA, without an upstream deploy."""
import json
from pathlib import Path
import sys


def generate(metadata_path, output_path):
    metadata = json.loads(Path(metadata_path).read_text(encoding="utf-8"))
    version = {
        "version": metadata["version_ipa"],
        "date": metadata["version_date"],
        "localizedDescription": metadata["localized_description"],
        "downloadURL": metadata["download_url"],
        "size": int(metadata["size"]),
        "sha256": metadata["sha256"],
        "minOSVersion": "15.0",
    }
    source = {
        "version": 2,
        "name": "ReStore",
        "identifier": "com.ReStore.ReStore",
        "website": "https://github.com/Nnnnnnn274/ReStore",
        "subtitle": "Apps, signing, and built-in LiveContainer",
        "tintColor": "335CFF",
        "apps": [{
            "name": "ReStore",
            "bundleIdentifier": metadata["bundle_identifier"],
            "developerName": "ReStore contributors",
            "localizedDescription": "Install and refresh apps with multiple signing accounts, custom certificates, and built-in LiveContainer.",
            "iconURL": "https://raw.githubusercontent.com/Nnnnnnn274/ReStore/develop/ReStoreApp/Resources/Icons.xcassets/AppIcon.appiconset/1024.png",
            "version": version["version"],
            "versionDate": version["date"],
            "versionDescription": version["localizedDescription"],
            "downloadURL": version["downloadURL"],
            "size": version["size"],
            "isBeta": metadata["release_channel"] != "stable",
            "releaseChannels": [{"track": metadata["release_channel"], "releases": [version]}],
        }],
        "news": [],
    }
    output = Path(output_path)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(source, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    generate(*sys.argv[1:])
