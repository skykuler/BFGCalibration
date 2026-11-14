#!/usr/bin/env python3
"""Run the production adapter against a stub, without an iOS radio/device."""
from pathlib import Path
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parent.parent
build = root / "build"
build.mkdir(exist_ok=True)
scratch = Path(tempfile.mkdtemp(prefix="transport-", dir=build))
assert scratch.resolve().is_relative_to(build.resolve())
files = {
    "Sources/BFGCore/BleTransport.swift": "Sources/BFGCore/BleTransport.swift",
    "Sources/CoreBluetooth/CoreBluetooth.swift": "Tools/AppleStubs/CoreBluetooth.swift",
    "Sources/TransportRegression/BleTransport.swift": "ios/BFGCalibration/BleTransport.swift",
    "Sources/TransportRegression/main.swift": "Tools/TransportRegressionMain.swift",
}
for target, source in files.items():
    destination = scratch / target
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(root / source, destination)
(scratch / "Package.swift").write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "TransportRegression", targets: [
    .target(name: "BFGCore"), .target(name: "CoreBluetooth"),
    .executableTarget(name: "TransportRegression", dependencies: ["BFGCore", "CoreBluetooth"])
])
''', encoding="utf-8")
subprocess.run(["swift", "run", "--package-path", str(scratch), "TransportRegression"], check=True)
