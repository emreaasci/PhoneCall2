// CallView.swift
struct CallView: View {
    let callerId: String
    let voiceCallManager: VoiceCallManager
    @Environment(\.dismiss) private var dismiss
    @State private var callStatus = "Bağlanıyor..."
    @State private var timer: Timer?
    @State private var callDuration = 0
    
    var body: some View {
        VStack(spacing: 30) {
            Spacer()
            
            Image(systemName: "person.circle.fill")
                .resizable()
                .frame(width: 100, height: 100)
                .foregroundColor(.blue)
            
            Text("Kullanıcı: \(callerId)")
                .font(.title2)
            
            Text(callStatus)
                .foregroundColor(.gray)
            
            if callStatus == "Görüşme devam ediyor" {
                Text(timeString(from: callDuration))
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            Button(action: {
                voiceCallManager.endCall()
                timer?.invalidate()
                dismiss()
            }) {
                Image(systemName: "phone.down.fill")
                    .font(.system(size: 30))
                    .padding(20)
                    .background(Color.red)
                    .foregroundColor(.white)
                    .clipShape(Circle())
            }
            .padding(.bottom, 50)
        }
        .onAppear {
            setupCallbacks()
        }
        .onDisappear {
            timer?.invalidate()
        }
    }
    
    private func setupCallbacks() {
        voiceCallManager.onCallConnected = {
            callStatus = "Görüşme devam ediyor"
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                callDuration += 1
            }
        }
        
        voiceCallManager.onCallEnded = {
            timer?.invalidate()
            dismiss()
        }
    }
    
    private func timeString(from seconds: Int) -> String {
        let minutes = seconds / 60
        let seconds = seconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
Last edited 1 dakika önce