#!/usr/bin/env bash
# Explicit local asset production. Reuses the resolved SDK checkout, never updates it.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
voice_output="${1:?Pass an absolute production output directory}"
voice_models="${2:?Pass the bundled Supertonic3/Models directory}"
voice_workspace="$(pwd)/build/voice-producer"
mkdir -p "$voice_workspace/Sources/VoiceProducer"
cat > "$voice_workspace/Package.swift" <<'SWIFT'
// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "VoiceProducer", platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../SourcePackages/checkouts/FluidAudio")],
    targets: [.executableTarget(name: "VoiceProducer", dependencies: [.product(name: "FluidAudio", package: "FluidAudio")])])
SWIFT
cp Scripts/produce-story-voices.swift "$voice_workspace/Sources/VoiceProducer/Producer.swift"
swift run --package-path "$voice_workspace" -c release VoiceProducer "$voice_output" "$voice_models"
