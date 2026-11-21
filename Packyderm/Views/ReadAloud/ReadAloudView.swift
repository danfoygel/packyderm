import SwiftData
import SwiftUI

struct ReadAloudView: View {
    let trip: Trip
    let items: [PackItem]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @AppStorage(SettingsKey.speechRate) private var speechRate = ReadAloudDefaults.rate
    @AppStorage(SettingsKey.pauseBetweenItems) private var pause = ReadAloudDefaults.pause
    @AppStorage(SettingsKey.listenTimeout) private var listenTimeout = ReadAloudDefaults.listenTimeout
    @State private var controller: ReadAloudController?
    @State private var showSpeed = false

    var body: some View {
        NavigationStack {
            Group {
                if let controller {
                    SessionView(controller: controller, total: controller.steps.count,
                                speechRate: $speechRate, pause: $pause, showSpeed: $showSpeed)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Read aloud")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        controller?.shutdown()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { showSpeed.toggle() } label: { Image(systemName: "gauge.with.dots.needle.67percent") }
                        .accessibilityLabel("Speed")
                }
            }
        }
        .onChange(of: speechRate) { _, new in controller?.rate = new }
        .onChange(of: pause) { _, new in controller?.pause = new }
        .task {
            UIApplication.shared.isIdleTimerDisabled = true
            let steps = items.map {
                ReadAloudController.Step(itemID: $0.id, name: $0.name, category: $0.category?.name ?? "", isCritical: $0.isCritical)
            }
            let controller = ReadAloudController(steps: steps)
            controller.rate = speechRate
            controller.pause = pause
            controller.listenTimeout = listenTimeout
            controller.onAnswer = { id, packed in record(id, packed: packed) }
            self.controller = controller
            await controller.start()
        }
        .onDisappear {
            controller?.shutdown()
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    private func record(_ itemID: UUID, packed: Bool) {
        guard let item = items.first(where: { $0.id == itemID }) else { return }
        trip.ensureEntry(for: item, in: context).isPacked = packed
    }
}

private struct SessionView: View {
    let controller: ReadAloudController
    let total: Int
    @Binding var speechRate: Double
    @Binding var pause: Double
    @Binding var showSpeed: Bool

    var body: some View {
        VStack(spacing: 20) {
            ProgressView(value: Double(min(controller.index, controller.steps.count)),
                         total: Double(max(controller.steps.count, 1)))
                .tint(.green)
            Text("\(min(controller.index + 1, controller.steps.count)) of \(controller.steps.count)")
                .font(.caption)
                .foregroundStyle(.secondary)

            if showSpeed {
                ReadAloudSpeedControls(rate: $speechRate, pause: $pause, onSample: controller.sample)
                    .padding()
                    .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 14))
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Spacer()

            if controller.phase == .finished {
                finished
            } else if let step = controller.current {
                VStack(spacing: 8) {
                    Text(step.category.uppercased())
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(step.name)
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.5)
                    if step.isCritical {
                        FlagBadge(text: "Critical", color: .red)
                    }
                }
                status
            }

            Spacer()

            if let problem = controller.permissionProblem {
                Text(problem)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if controller.phase != .finished {
                controls
            }
        }
        .padding()
        .animation(.default, value: showSpeed)
        .animation(.default, value: controller.phase)
    }

    @ViewBuilder
    private var status: some View {
        switch controller.phase {
        case .speaking:
            Label("Speaking", systemImage: "speaker.wave.2.fill")
                .symbolEffect(.variableColor.iterative, isActive: true)
                .foregroundStyle(.secondary)
        case .listening:
            VStack(spacing: 6) {
                Label("Listening — say yes or no", systemImage: "mic.fill")
                    .symbolEffect(.pulse, isActive: true)
                    .foregroundStyle(.red)
                if !controller.heard.isEmpty {
                    Text("“\(controller.heard)”").foregroundStyle(.secondary)
                }
            }
        case .waiting:
            Text("Tap Yes or No").foregroundStyle(.secondary)
        case .paused:
            Text("Paused").foregroundStyle(.secondary)
        default:
            EmptyView()
        }
    }

    private var controls: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                Button { controller.answer(.no) } label: {
                    Label("No", systemImage: "xmark").frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.bordered)
                .tint(.orange)
                Button { controller.answer(.yes) } label: {
                    Label("Yes, packed", systemImage: "checkmark").frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
            .font(.title3.weight(.semibold))

            HStack(spacing: 28) {
                Button { controller.answer(.back) } label: { Image(systemName: "backward.fill") }
                    .accessibilityLabel("Previous item")
                    .disabled(controller.index == 0)
                if controller.phase == .paused {
                    Button { controller.resume() } label: { Image(systemName: "play.fill") }
                        .accessibilityLabel("Resume")
                } else {
                    Button { controller.stop() } label: { Image(systemName: "pause.fill") }
                        .accessibilityLabel("Pause")
                }
                Button { controller.answer(.again) } label: { Image(systemName: "arrow.counterclockwise") }
                    .accessibilityLabel("Repeat")
            }
            .font(.title2)

            Text("Say “yes” or “no”. You can also say “repeat”, “back”, or “stop”.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var finished: some View {
        VStack(spacing: 12) {
            Image(systemName: controller.skippedIDs.isEmpty ? "checkmark.seal.fill" : "list.bullet.clipboard")
                .font(.system(size: 56))
                .foregroundStyle(controller.skippedIDs.isEmpty ? .green : .orange)
            Text(controller.skippedIDs.isEmpty ? "All done!" : "\(controller.skippedIDs.count) still to pack")
                .font(.title.bold())
            Text("\(controller.packedIDs.count) checked off this round")
                .foregroundStyle(.secondary)
            if !controller.skippedIDs.isEmpty {
                Button("Go through those again") { controller.reviewSkipped() }
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}

struct ReadAloudSpeedControls: View {
    @Binding var rate: Double
    @Binding var pause: Double
    var onSample: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Speaking speed")
                Spacer()
                Text(String(format: "%.1f×", rate)).monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: $rate, in: 0.5...1.8, step: 0.1) {
                Text("Speaking speed")
            } minimumValueLabel: {
                Image(systemName: "tortoise")
            } maximumValueLabel: {
                Image(systemName: "hare")
            }
            HStack {
                Text("Pause between items")
                Spacer()
                Text(String(format: "%.1f s", pause)).monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: $pause, in: 0...2, step: 0.1)
            if let onSample {
                Button("Preview speed", systemImage: "play.circle", action: onSample)
                    .font(.subheadline)
            }
        }
    }
}
