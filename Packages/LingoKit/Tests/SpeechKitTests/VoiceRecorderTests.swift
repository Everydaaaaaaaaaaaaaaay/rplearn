import AVFoundation
import CoreKit
import Testing
import SpeechKit

@Suite("VoiceRecorder")
@MainActor
struct VoiceRecorderTests {
    @Test("启动前拒绝不可录制的输入格式")
    func rejectsUnrecordableInputFormats() {
        let zeroChannel = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 44_100,
            channels: 0,
            interleaved: false
        )!
        let zeroSampleRate = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 0,
            channels: 1,
            interleaved: false
        )!
        let valid = AVAudioFormat(
            standardFormatWithSampleRate: 44_100,
            channels: 1
        )!

        #expect(!VoiceRecorder.isRecordableInputFormat(zeroChannel))
        #expect(!VoiceRecorder.isRecordableInputFormat(zeroSampleRate))
        #expect(VoiceRecorder.isRecordableInputFormat(valid))
    }

    @Test("启动过程中取消，不继续创建录音管线")
    func cancellationBeforePermissionCompletesDoesNotStartCapture() async {
        final class Probe: @unchecked Sendable {
            var permissionContinuation: CheckedContinuation<Bool, Never>?
            var startCaptureCount = 0
        }

        let probe = Probe()
        let recorder = VoiceRecorder(
            audioSession: AudioSessionCoordinator(),
            permissionRequester: { _ in
                await withCheckedContinuation { continuation in
                    probe.permissionContinuation = continuation
                }
            },
            captureStarter: { _ in
                probe.startCaptureCount += 1
                return VoiceRecorder.StartedCapture(
                    engine: nil,
                    audioFile: nil,
                    recognitionRequest: nil,
                    recognitionTask: nil,
                    fileName: nil
                )
            }
        )

        let task = Task { await recorder.startRecording() }
        await Task.yield()
        task.cancel()
        probe.permissionContinuation?.resume(returning: true)
        await task.value

        #expect(probe.startCaptureCount == 0)
        #expect(recorder.state == .idle)
    }

    @Test("后台音频回调可以安全更新主 actor 状态")
    func audioCallbacksCanRunOffMainActor() async {
        let recorder = VoiceRecorder(audioSession: AudioSessionCoordinator())
        let callbacks = recorder.makeRuntimeCallbacks()

        await Task.detached {
            callbacks.reportLevel(0.42)
        }.value
        await Task.yield()

        #expect(abs(recorder.level - 0.42) < 0.001)
    }

    @Test("录音启动失败后可在当前模式直接重试")
    func retriesDirectlyAfterFailure() async {
        enum TestError: Error {
            case firstAttempt
        }
        final class Probe: @unchecked Sendable {
            var startCaptureCount = 0
        }

        let probe = Probe()
        let recorder = VoiceRecorder(
            audioSession: AudioSessionCoordinator(),
            permissionRequester: { _ in true },
            captureStarter: { _ in
                probe.startCaptureCount += 1
                if probe.startCaptureCount == 1 {
                    throw TestError.firstAttempt
                }
                return VoiceRecorder.StartedCapture(
                    engine: nil,
                    audioFile: nil,
                    recognitionRequest: nil,
                    recognitionTask: nil,
                    fileName: nil
                )
            }
        )

        await recorder.startRecording()
        guard case .failed = recorder.state else {
            Issue.record("首次启动应进入失败态")
            return
        }

        await recorder.startRecording()

        #expect(probe.startCaptureCount == 2)
        #expect(recorder.state == .recording(inCancelZone: false))
        await recorder.cancelRecording()
    }
}
