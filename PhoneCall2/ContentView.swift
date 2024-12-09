//
//  ContentView.swift
//  PhoneCall
//
//  Created by Emre Aşcı on 6.12.2024.
//

import SwiftUI

import SwiftUI
import AVFoundation

struct ContentView: View {
    @State private var onlineUsers: [String] = []
    @State private var incomingCallFrom: String?
    @State private var isCallActive = false
    @State private var activeCallUserId: String?
    let voiceCallManager: VoiceCallManager
    let deviceId: String
    
    init() {
        deviceId = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        voiceCallManager = VoiceCallManager(userId: deviceId)
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Cihaz ID: \(deviceId)")
                    .font(.caption)
                    .padding()
                
                if onlineUsers.isEmpty {
                    ContentUnavailableView("Çevrimiçi Kullanıcı Yok",
                                         systemImage: "person.slash",
                                         description: Text("Başka kullanıcılar bağlandığında burada görünecek"))
                } else {
                    List(onlineUsers, id: \.self) { user in
                        if user != voiceCallManager.userId {
                            Button {
                                activeCallUserId = user
                                voiceCallManager.startCall(to: user)
                                isCallActive = true
                            } label: {
                                HStack {
                                    Image(systemName: "phone.fill")
                                        .foregroundColor(.green)
                                    Text(user)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Sesli Arama")
            .fullScreenCover(isPresented: $isCallActive) {
                if let callerId = activeCallUserId {
                    CallView(callerId: callerId, voiceCallManager: voiceCallManager)
                }
            }
            .onAppear {
                setupCallbacks()
                requestMicrophonePermission()
            }
            .alert("Gelen Arama", isPresented: .constant(incomingCallFrom != nil)) {
                Button("Kabul Et") {
                    if let callerId = incomingCallFrom {
                        voiceCallManager.acceptCall(from: callerId)
                        activeCallUserId = callerId
                        isCallActive = true
                    }
                    incomingCallFrom = nil
                }
                Button("Reddet", role: .cancel) {
                    incomingCallFrom = nil
                }
            } message: {
                if let callerId = incomingCallFrom {
                    Text("\(callerId) arıyor...")
                }
            }
        }
    }
    
    private func setupCallbacks() {
        voiceCallManager.onOnlineUsersUpdated = { users in
            onlineUsers = users
        }
        
        voiceCallManager.onIncomingCall = { callerId in
            incomingCallFrom = callerId
        }
        
        voiceCallManager.onCallEnded = {
            isCallActive = false
            activeCallUserId = nil
        }
    }
    
    private func requestMicrophonePermission() {
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            DispatchQueue.main.async {
                if granted {
                    print("Mikrofon izni verildi")
                } else {
                    print("Mikrofon izni reddedildi")
                }
            }
        }
    }
}
