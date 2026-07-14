import CoreMedia
import AudioToolbox
import Darwin
import Foundation
import ScreenCaptureKit

private final class SystemAudioOutput: NSObject, SCStreamOutput {
    private let stdout = FileHandle.standardOutput
    private var retainedBlockBuffer: CMBlockBuffer?
    private var formatChecked = false

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        guard outputType == .audio, CMSampleBufferDataIsReady(sampleBuffer) else { return }
        if !formatChecked {
            guard let format = CMSampleBufferGetFormatDescription(sampleBuffer),
                  let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee,
                  asbd.mFormatID == kAudioFormatLinearPCM,
                  asbd.mBitsPerChannel == 32,
                  asbd.mFormatFlags & kAudioFormatFlagIsFloat != 0
            else {
                fputs("unsupported system audio PCM format\n", stderr)
                exit(2)
            }
            formatChecked = true
        }

        var blockBuffer: CMBlockBuffer?
        var audioBufferList = AudioBufferList()
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: &audioBufferList,
            bufferListSize: MemoryLayout<AudioBufferList>.size,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &blockBuffer
        )
        guard status == noErr else { return }
        retainedBlockBuffer = blockBuffer

        let buffers = UnsafeMutableAudioBufferListPointer(&audioBufferList)
        for buffer in buffers {
            guard let data = buffer.mData, buffer.mDataByteSize > 0 else { continue }
            stdout.write(Data(bytes: data, count: Int(buffer.mDataByteSize)))
        }
    }
}

@main
private struct MacOSSystemAudioCapture {
    static func main() async {
        let parentPID = getppid()
        // ScreenCaptureKit initialization itself can block for several seconds.
        // Monitor the parent independently so a killed launcher cannot strand us
        // before startCapture() has returned.
        Task.detached {
            while true {
                try? await Task.sleep(for: .seconds(1))
                if getppid() != parentPID {
                    exit(0)
                }
            }
        }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )
            guard let display = content.displays.first else {
                throw NSError(
                    domain: "system-audio-capture",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "no display available"]
                )
            }

            let filter = SCContentFilter(
                display: display,
                excludingApplications: [],
                exceptingWindows: []
            )
            let configuration = SCStreamConfiguration()
            configuration.width = 2
            configuration.height = 2
            configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)
            configuration.queueDepth = 3
            configuration.capturesAudio = true
            configuration.excludesCurrentProcessAudio = false
            configuration.sampleRate = 48_000
            configuration.channelCount = 1

            let output = SystemAudioOutput()
            let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
            try stream.addStreamOutput(
                output,
                type: .audio,
                sampleHandlerQueue: DispatchQueue(label: "assistant.system-audio")
            )
            try await stream.startCapture()
            fputs("ready\n", stderr)
            while true {
                try await Task.sleep(for: .seconds(60))
            }
        } catch {
            fputs("system audio capture failed: \(error)\n", stderr)
            exit(1)
        }
    }
}
