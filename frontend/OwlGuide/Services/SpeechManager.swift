import Foundation
import Speech
import AVFoundation
import AppKit

class SpeechManager: NSObject, SFSpeechRecognizerDelegate {
    static let shared = SpeechManager()
    
    private let audioEngine = AVAudioEngine()
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var textHandler: ((String) -> Void)?
    private var silenceTimer: Timer?
    var onRecordingStopped: (() -> Void)?
    
    private override init() {
        super.init()
        speechRecognizer?.delegate = self
    }
    
    func requestPermissions(completion: @escaping (Bool, Bool, Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { speechAuthStatus in
            AVCaptureDevice.requestAccess(for: .audio) { micGranted in
                DispatchQueue.main.async {
                    let speechGranted = speechAuthStatus == .authorized
                    completion(speechGranted && micGranted, speechGranted, micGranted)
                }
            }
        }
    }
    
    func startRecording(textHandler: @escaping (String) -> Void) throws {
        self.textHandler = textHandler
        
        if audioEngine.isRunning {
            stopRecording()
        }
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            throw NSError(domain: "SpeechManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unable to create recognition request"])
        }
        recognitionRequest.shouldReportPartialResults = true
        
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }
        
        audioEngine.prepare()
        try audioEngine.start()
        
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }
            
            if let result = result {
                let transcribedText = result.bestTranscription.formattedString
                DispatchQueue.main.async {
                    self.textHandler?(transcribedText)
                }
                
                self.resetSilenceTimer()
            }
            
            if error != nil || result?.isFinal ?? false {
                self.stopRecording()
            }
        }
    }
    
    func stopRecording() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        
        recognitionRequest = nil
        recognitionTask = nil
        
        silenceTimer?.invalidate()
        silenceTimer = nil
        
        DispatchQueue.main.async {
            self.onRecordingStopped?()
        }
    }
    
    private func resetSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
            self?.stopRecording()
        }
    }
}
