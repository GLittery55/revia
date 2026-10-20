import AppKit
import AVFoundation
import Foundation

guard (3...4).contains(CommandLine.arguments.count) else {
    fputs("usage: extract_video_frames <video> <output-directory> [step-seconds]\n", stderr)
    exit(2)
}

let videoURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
try FileManager.default.createDirectory(
    at: outputURL,
    withIntermediateDirectories: true
)

let asset = AVURLAsset(url: videoURL)
let duration = CMTimeGetSeconds(asset.duration)
guard duration.isFinite, duration > 0 else {
    fputs("invalid video duration\n", stderr)
    exit(3)
}

let generator = AVAssetImageGenerator(asset: asset)
generator.appliesPreferredTrackTransform = true
generator.requestedTimeToleranceBefore = .zero
generator.requestedTimeToleranceAfter = .zero

let step = CommandLine.arguments.count == 4
    ? (Double(CommandLine.arguments[3]) ?? 1.0)
    : (duration <= 20 ? 1.0 : max(1.0, duration / 20.0))
var second = 0.0
var index = 0
while second < duration {
    let time = CMTime(seconds: second, preferredTimescale: 600)
    do {
        let image = try generator.copyCGImage(at: time, actualTime: nil)
        let representation = NSBitmapImageRep(cgImage: image)
        guard let data = representation.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let filename = String(format: "frame-%03d-%06.2f.png", index, second)
        try data.write(to: outputURL.appendingPathComponent(filename), options: .atomic)
        print(filename)
    } catch {
        fputs("frame at \(second)s failed: \(error)\n", stderr)
    }
    second += step
    index += 1
}
print(String(format: "duration=%.3f step=%.3f", duration, step))
