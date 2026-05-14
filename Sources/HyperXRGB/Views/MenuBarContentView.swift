import SwiftUI
import HyperXCore
import HyperXProtocol

struct MenuBarContentView: View {
    @EnvironmentObject var controller: MicController
    @EnvironmentObject var state: AppState

    @State private var pendingUpper: Color = .white
    @State private var pendingLower: Color = .white
    @State private var applyTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            Divider()

            zonesSection

            Divider()

            brightnessSection

            Divider()

            HStack {
                Button("Salir") {
                    controller.stop()
                    NSApp.terminate(nil)
                }
                .keyboardShortcut("q")
                Spacer()
                Text("HyperX Quadcast 2 S")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(width: 280)
        .onAppear {
            pendingUpper = state.upperColor.asColor
            pendingLower = state.lowerColor.asColor
        }
    }

    private var header: some View {
        HStack {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(statusText)
                .font(.headline)
            Spacer()
        }
    }

    private var statusColor: Color {
        switch controller.status {
        case .connected: return .green
        case .disconnected: return .gray
        case .busy: return .orange
        case .error: return .red
        }
    }

    private var statusText: String {
        switch controller.status {
        case .connected: return "Conectado"
        case .disconnected: return "No detectado"
        case .busy: return "Ocupado"
        case .error(let msg): return msg
        }
    }

    @ViewBuilder
    private var zonesSection: some View {
        Toggle("Vincular zonas", isOn: $state.linkZones)
            .onChange(of: state.linkZones) { _, _ in
                state.persist()
                scheduleApply()
            }

        ColorPicker("Zona superior", selection: $pendingUpper, supportsOpacity: false)
            .onChange(of: pendingUpper) { _, newValue in
                state.upperColor = RGB(newValue)
                if state.linkZones {
                    state.lowerColor = state.upperColor
                    pendingLower = newValue
                }
                state.persist()
                scheduleApply()
            }

        if !state.linkZones {
            ColorPicker("Zona inferior", selection: $pendingLower, supportsOpacity: false)
                .onChange(of: pendingLower) { _, newValue in
                    state.lowerColor = RGB(newValue)
                    state.persist()
                    scheduleApply()
                }
        }
    }

    private var brightnessSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Brillo")
                Spacer()
                Text("\(state.brightness)%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(
                value: Binding(
                    get: { Double(state.brightness) },
                    set: { state.brightness = Int($0) }
                ),
                in: 0...100,
                step: 1
            )
            .onChange(of: state.brightness) { _, _ in
                state.persist()
                scheduleApply()
            }
        }
    }

    private func scheduleApply() {
        applyTask?.cancel()
        applyTask = Task {
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }
            controller.setColor(
                upper: state.upperColor,
                lower: state.linkZones ? state.upperColor : state.lowerColor,
                brightness: state.brightness
            )
        }
    }
}
