//
//  VoiceCallManager.swift
//  PhoneCall2
//
//  Created by Emre Aşcı on 9.12.2024.
//


//
//  VoiceCallManager.swift
//  PhoneCall
//
//  Created by Emre Aşcı on 6.12.2024.
//


import AVFoundation
import SocketIO

class VoiceCallManager: NSObject, AVAudioRecorderDelegate, AVAudioPlayerDelegate {
    private var socket: SocketIOClient!
    private var manager: SocketManager!
    private var audioEngine: AVAudioEngine!
    private var audioPlayer: AVAudioPlayer?
    private var isRecording = false
    private var currentRoomId: String?
    let userId: String
    private var playerNodes: [AVAudioPlayerNode] = []
    
    var onOnlineUsersUpdated: (([String]) -> Void)?
    var onIncomingCall: ((String) -> Void)?
    var onCallConnected: (() -> Void)?
    var onCallEnded: (() -> Void)?
    
    init(userId: String) {
        self.userId = userId
        super.init()
        
        // Önce socket'i kur, sonra audio'yu başlat
        setupSocket()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.setupAudio()
        }
    }
    
    private func setupAudio() {
        audioEngine = AVAudioEngine()
        
        // Audio session ayarları
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth])
            try audioSession.setActive(true)
            try audioSession.overrideOutputAudioPort(.speaker)
            print("Audio session yapılandırıldı")
        } catch {
            print("Audio session hatası:", error)
        }
        
        // MainMixer'a bağlantı kur
        let mainMixer = audioEngine.mainMixerNode
        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        
        // Input'u mainMixer'a bağla
        audioEngine.connect(input, to: mainMixer, format: format)
        
        // Output'u mainMixer'a bağla
        let output = audioEngine.outputNode
        audioEngine.connect(mainMixer, to: output, format: format)
        
        // Şimdi engine'i başlat
        do {
            try audioEngine.start()
            print("Audio engine başlatıldı")
        } catch {
            print("Audio engine başlatma hatası:", error)
        }
    }
    
    
    
    private func setupSocket() {
        manager = SocketManager(socketURL: URL(string: "http://172.10.40.51:3000")!, config: [.log(true)])
        socket = manager.defaultSocket
        
        socket.on(clientEvent: .connect) { [weak self] _, _ in
            print("Socket bağlandı")
            self?.registerUser()
        }
        
        socket.on("online-users") { [weak self] data, _ in
            if let users = data[0] as? [String] {
                self?.onOnlineUsersUpdated?(users)
            }
        }
        
        socket.on("incoming-call") { [weak self] data, _ in
            if let callData = data[0] as? [String: Any],
               let callerId = callData["callerId"] as? String,
               let roomId = callData["roomId"] as? String {
                self?.currentRoomId = roomId
                self?.onIncomingCall?(callerId)
            }
        }
        
        socket.on("call-accepted") { [weak self] _, _ in
            self?.startAudioStream()
            self?.onCallConnected?()
        }
        
        socket.on("audio") { [weak self] data, _ in
            if let audioData = data[0] as? [String: Any],
               let base64String = audioData["data"] as? String,
               let audioBytes = Data(base64Encoded: base64String) {
                self?.playAudio(audioBytes)
            }
        }
        
        socket.on("call-ended") { [weak self] _, _ in
            self?.endCall()
        }
        
        socket.connect()
    }
    
    private func registerUser() {
        socket.emit("register", userId)
    }
    
    func startCall(to targetUserId: String) {
        currentRoomId = "\(userId)-\(targetUserId)"
        socket.emit("start-call", ["targetUserId": targetUserId, "callerId": userId, "roomId": currentRoomId])
    }
    
    func acceptCall(from callerId: String) {
        if let roomId = currentRoomId {
            socket.emit("accept-call", ["callerId": callerId, "roomId": roomId])
            startAudioStream()
        }
    }
    
    private func startAudioStream() {
            guard !isRecording else { return }
            
            do {
                // Input node'u ayarla
                let input = audioEngine.inputNode
                let format = input.outputFormat(forBus: 0)
                let sampleRate = format.sampleRate
                
                // Buffer size'ı küçült ve kaliteyi artır
                let bufferSize: AVAudioFrameCount = 512
                input.installTap(onBus: 0, bufferSize: bufferSize, format: format) { [weak self] buffer, time in
                    guard let self = self, self.isRecording else { return }
                    
                    // Ses verisini işle ve gönder
                    let frameCount = buffer.frameLength
                    let channels = UnsafeBufferPointer(start: buffer.floatChannelData?[0],
                                                     count: Int(frameCount))
                    var samples = [Float](repeating: 0, count: Int(frameCount))
                    
                    // Ses örneğini al
                    for i in 0..<Int(frameCount) {
                        samples[i] = channels[i]
                    }
                    
                    // Ses verisini base64'e çevir ve gönder
                    let data = Data(bytes: samples, count: samples.count * MemoryLayout<Float>.size)
                    if let roomId = self.currentRoomId {
                        self.socket.emit("audio", [
                            "roomId": roomId,
                            "data": data.base64EncodedString(),
                            "sampleRate": sampleRate
                        ])
                    }
                }
                
                if !audioEngine.isRunning {
                    try audioEngine.start()
                }
                isRecording = true
                print("Audio stream başlatıldı")
            } catch {
                print("Audio stream başlatma hatası:", error)
            }
        }
    
    private func playAudio(_ data: Data) {
            guard audioEngine.isRunning else {
                print("Audio engine çalışmıyor")
                return
            }
            
            do {
                // Gelen ses verisini float array'e çevir
                var samples: [Float] = []
                data.withUnsafeBytes { rawBuffer in
                    let floatBuffer = rawBuffer.bindMemory(to: Float.self)
                    samples = Array(floatBuffer)
                }
                
                // Format oluştur
                guard let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1) else {
                    print("Format oluşturulamadı")
                    return
                }
                
                // Buffer oluştur
                guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else {
                    print("Buffer oluşturulamadı")
                    return
                }
                
                buffer.frameLength = AVAudioFrameCount(samples.count)
                
                // Buffer'a verileri kopyala
                if let channelData = buffer.floatChannelData?[0] {
                    for i in 0..<samples.count {
                        channelData[i] = samples[i]
                    }
                }
                
                // Eski player node'ları temizle
                for node in playerNodes {
                    audioEngine.detach(node)
                }
                playerNodes.removeAll()
                
                // Yeni player node oluştur
                let playerNode = AVAudioPlayerNode()
                audioEngine.attach(playerNode)
                audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: format)
                playerNodes.append(playerNode)
                
                // Sesi çal
                playerNode.scheduleBuffer(buffer, completionHandler: {
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        // Node'u temizle
                        self.audioEngine.detach(playerNode)
                        if let index = self.playerNodes.firstIndex(of: playerNode) {
                            self.playerNodes.remove(at: index)
                        }
                    }
                })
                
                playerNode.play()
            } catch {
                print("Ses çalma hatası:", error)
            }
        }
    
    func endCall() {
            isRecording = false
            
            // Tüm player node'ları temizle
            for node in playerNodes {
                node.stop()
                audioEngine.detach(node)
            }
            playerNodes.removeAll()
            
            // Input tap'i kaldır
            audioEngine.inputNode.removeTap(onBus: 0)
            
            // Audio engine'i durdur
            audioEngine.stop()
            
            if let roomId = currentRoomId {
                socket.emit("end-call", ["roomId": roomId])
            }
            
            currentRoomId = nil
            onCallEnded?()
        }
}
