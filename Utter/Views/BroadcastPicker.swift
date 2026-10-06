import SwiftUI
import ReplayKit

/// iOS's own "start screen recording" button, pointed at Utter's add-on and kept invisible,
/// so a plain text link in Utter can open the system prompt.
struct BroadcastPicker: UIViewRepresentable {
    let trigger: Int   // change this to open the prompt

    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        picker.preferredExtension = "com.christruong.utter.broadcast"
        picker.showsMicrophoneButton = false
        picker.alpha = 0.011   // invisible, but still allowed to receive the tap
        return picker
    }

    func updateUIView(_ picker: RPSystemBroadcastPickerView, context: Context) {
        guard trigger != context.coordinator.lastTrigger else { return }
        context.coordinator.lastTrigger = trigger
        if trigger > 0, let button = picker.subviews.compactMap({ $0 as? UIButton }).first {
            button.sendActions(for: .touchUpInside)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var lastTrigger = 0 }
}
