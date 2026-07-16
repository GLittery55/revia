import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var model = ReflectionViewModel()

    var body: some View {
        NavigationStack {
            ChatView(model: model)
                .navigationTitle("Beyond Comfort")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button(model.isPaused ? "继续" : "暂停") { model.pause() }
                            Button("结束并查看记录") { model.end() }
                            Button("删除并重新开始", role: .destructive) { model.delete(); model.restart() }
                        } label: { Label("跳过、暂停或结束", systemImage: "ellipsis.circle") }
                    }
                }
                .overlay { if model.isPaused { PauseOverlay { model.pause() } } }
        }
        .tint(Color(red: 0.34, green: 0.28, blue: 0.72))
        .task { await model.prepareRequiredContextData() }
    }
}

private struct ChatView: View {
    @ObservedObject var model: ReflectionViewModel

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(model.session.messages) { message in MessageBubble(message: message).id(message.id) }
                        if model.isTyping { TypingIndicator() }
                        StagePanel(model: model).id("stage-panel")
                    }
                    .padding()
                }
                .onChange(of: model.session.messages.count) { _, _ in withAnimation { proxy.scrollTo("stage-panel", anchor: .bottom) } }
                .onChange(of: model.session.stage) { _, _ in withAnimation { proxy.scrollTo("stage-panel", anchor: .bottom) } }
            }
            if acceptsText {
                Divider()
                HStack(alignment: .bottom) {
                    TextField("写下你的回应…", text: $model.draft, axis: .vertical).lineLimit(1...5).textFieldStyle(.roundedBorder)
                    Button(action: model.send) { Image(systemName: "arrow.up.circle.fill").font(.title) }.disabled(model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isTyping)
                }.padding(12)
            }
        }
        .background(Color(.systemGroupedBackground))
    }

    private var acceptsText: Bool {
        [.contextGathering, .tenderGrounding, .cardInterpretation, .tenderExploration, .candidInquiry].contains(model.session.stage)
    }
}

private struct MessageBubble: View {
    let message: ChatMessage
    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 54) }
            Text(message.content).font(.body).foregroundStyle(message.role == .user ? .white : .primary).padding(.horizontal, 14).padding(.vertical, 10)
                .background(message.role == .user ? Color.accentColor : Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
            if message.role != .user { Spacer(minLength: 54) }
        }
    }
}

private struct StagePanel: View {
    @ObservedObject var model: ReflectionViewModel
    var body: some View {
        Group {
            switch model.session.stage {
            case .orient: OrientPanel(model: model)
            case .contextGathering: Button("跳过这一项", action: model.skipContext).buttonStyle(.bordered)
            case .contextConfirmation: CanvasPanel(model: model)
            case .cardDraw: Button("随机抽取一张卡片", action: model.drawCard).buttonStyle(.borderedProminent)
            case .cardInterpretation, .tenderExploration:
                if let card = model.session.card { CardView(card: card) }
            case .affirmationReadiness: GatePanel(model: model)
            case .candidInquiry: HypothesesPanel(model: model)
            case .actionComposer: ActionPanel(model: model)
            case .reviewClose: ReviewPanel(model: model)
            case .safetyInterrupt: Button("结束本次流程", action: model.end).buttonStyle(.borderedProminent)
            case .tenderGrounding: EmptyView()
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct OrientPanel: View {
    @ObservedObject var model: ReflectionViewModel
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("健康与日程情境").font(.headline)
            Label(model.llmStatus, systemImage: model.llmStatus.hasPrefix("DeepSeek") ? "network" : "exclamationmark.triangle")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(model.llmStatus.hasPrefix("DeepSeek") ? .green : .orange)
            HStack(alignment: .top) { ProgressView().opacity(model.session.trackingCues.isEmpty ? 1 : 0); Text(model.contextDataStatus).font(.subheadline) }
            ForEach(model.session.trackingCues) { cue in Label(cue.observation, systemImage: "waveform.path.ecg").font(.caption) }
            Text("App 启动时会直接请求读取权限。你仍可在情境确认页排除单条线索；数据只用于谨慎推测，不用于诊断、因果判断或归责。").font(.caption).foregroundStyle(.secondary)
            Button("开始一次反思", action: model.begin).buttonStyle(.borderedProminent).frame(maxWidth: .infinity)
        }.cardStyle()
    }
}

private struct CanvasPanel: View {
    @ObservedObject var model: ReflectionViewModel
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text("你报告的内容").font(.headline)
                LabeledCanvasField(label: "事件", text: $model.session.canvas.event)
                LabeledCanvasField(label: "感受与身体体验", text: $model.session.canvas.experience)
                LabeledCanvasField(label: "它对你的意义", text: $model.session.canvas.meaning)
                LabeledCanvasField(label: "现实限制", text: $model.session.canvas.constraints)
                LabeledCanvasField(label: "能影响与不确定的部分", text: $model.session.canvas.agencyAndUncertainty)
                LabeledCanvasField(label: "这次反思的意图", text: $model.session.canvas.reflectiveIntention)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("事件时间").font(.headline)
                DatePicker("用于匹配事件附近的数据", selection: $model.session.canvas.eventDate, in: ...Date(), displayedComponents: [.date])
                Button("按这个日期重新读取情境线索") { Task { await model.refreshContextData() } }.buttonStyle(.bordered)
            }
            VStack(alignment: .leading) {
                Text("可能的情境因素").font(.headline)
                if model.session.trackingCues.isEmpty { Text("没有纳入任何自我追踪观察").foregroundStyle(.secondary) }
                ForEach(model.session.trackingCues) { cue in Toggle(cue.observation, isOn: Binding(get: { cue.included }, set: { model.updateCue(cue, included: $0) })) }
                TextEditor(text: Binding(get: { model.session.canvas.contextualFactors }, set: { model.session.canvas.contextualFactors = $0 })).frame(minHeight: 70).overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
            }
            CanvasField(title: "仍不确定的部分", text: Binding(get: { model.session.canvas.agencyAndUncertainty }, set: { model.session.canvas.agencyAndUncertainty = $0 }))
            Button("确认情境并继续", action: model.confirmCanvas).buttonStyle(.borderedProminent).frame(maxWidth: .infinity)
        }.cardStyle()
    }
}

private struct CanvasField: View {
    let title: String
    @Binding var text: String
    var body: some View { VStack(alignment: .leading) { Text(title).font(.headline); TextEditor(text: $text).frame(minHeight: 90).overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary)) } }
}

private struct LabeledCanvasField: View {
    let label: String
    @Binding var text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextField(label, text: $text, axis: .vertical).textFieldStyle(.roundedBorder)
        }
    }
}

private struct CardView: View {
    let card: ReflectionCard
    var body: some View {
        VStack(spacing: 12) {
            TarotCardImage(imageName: card.imageName)
                .frame(maxHeight: 420)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: .black.opacity(0.18), radius: 10, y: 5)
                .accessibilityLabel(card.neutralLabel)
            Text(card.neutralLabel).font(.headline)
            Text("没有固定含义 · 以你的解读为准").font(.caption).foregroundStyle(.secondary)
        }.cardStyle()
    }
}

private struct TarotCardImage: View {
    let imageName: String

    var body: some View {
        Group {
            if let image = croppedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                ContentUnavailableView(
                    "卡片图片无法加载",
                    systemImage: "photo.badge.exclamationmark",
                    description: Text("缺少资源：\(imageName).jpg")
                )
                .frame(height: 280)
            }
        }
    }

    private var croppedImage: UIImage? {
        guard let url = Bundle.main.url(forResource: imageName, withExtension: "jpg"),
              let image = UIImage(contentsOfFile: url.path),
              let cgImage = image.cgImage else { return nil }
        // Remove the printed title/number band so the card is presented as an
        // ambiguous visual object rather than as a conventional tarot category.
        let crop = CGRect(x: 0, y: 0, width: CGFloat(cgImage.width), height: CGFloat(cgImage.height) * 0.88)
        guard let cropped = cgImage.cropping(to: crop) else { return image }
        return UIImage(cgImage: cropped, scale: image.scale, orientation: image.imageOrientation)
    }
}

private struct GatePanel: View {
    @ObservedObject var model: ReflectionViewModel
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("继续前的明确确认").font(.headline)
            Toggle("当前理解贴合我的体验", isOn: $model.affirmed)
            Toggle("我明确愿意继续坦诚探索", isOn: $model.ready)
            Button(model.affirmed && model.ready ? "继续" : "在这里结束", action: model.resolveGate).buttonStyle(.borderedProminent).frame(maxWidth: .infinity)
        }.cardStyle()
    }
}

private struct HypothesesPanel: View {
    @ObservedObject var model: ReflectionViewModel
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(model.session.hypotheses) { hypothesis in
                VStack(alignment: .leading, spacing: 10) {
                    Text("模型提出的可能性").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text(hypothesis.text)
                    HStack {
                        Button("保留") { model.setHypothesis(hypothesis.id, status: .kept) }
                        Button("修订") { model.setHypothesis(hypothesis.id, status: .revised) }
                        Button("搁置") { model.setHypothesis(hypothesis.id, status: .setAside) }
                    }.buttonStyle(.bordered)
                }.padding().background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
            }
            Button("进入行动选择", action: model.proceedToAction).buttonStyle(.borderedProminent).frame(maxWidth: .infinity)
        }.cardStyle()
    }
}

private struct ActionPanel: View {
    @ObservedObject var model: ReflectionViewModel
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("给下一步留一点温柔的空间").font(.headline)
            if model.session.actionSuggestions.isEmpty {
                HStack { ProgressView(); Text("正在准备几个小而可行的邀请…").foregroundStyle(.secondary) }
            }
            ForEach(model.session.actionSuggestions) { suggestion in
                Button { model.chooseAction(suggestion) } label: {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(suggestion.type.title).font(.caption.weight(.bold)).foregroundStyle(.tint)
                        Text(suggestion.text).foregroundStyle(.primary)
                        Text(suggestion.rationale).font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color.accentColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                }.buttonStyle(.plain)
            }
            Button("我现在还不想决定", action: model.chooseNotReady).buttonStyle(.bordered).frame(maxWidth: .infinity)
        }.cardStyle()
    }
}

private struct ReviewPanel: View {
    @ObservedObject var model: ReflectionViewModel
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("你的文字").font(.headline)
            Text(model.session.canvas.reported.isEmpty ? "未记录" : model.session.canvas.reported)
            if !model.session.cardInterpretation.isEmpty { Label(model.session.cardInterpretation, systemImage: "person.fill") }
            Divider()
            Text("模型提出的可能性").font(.headline)
            ForEach(model.session.hypotheses) { Text("• \($0.text) [\($0.status.rawValue)]") }
            Divider()
            Text("你的行动选择").font(.headline)
            Text("\(model.session.action.type.title)：\(model.session.action.text.isEmpty ? "未填写" : model.session.action.text)")
            Divider()
            Text("研究反馈（1–7）").font(.headline)
            MeasureSlider(title: "我感到被理解", value: $model.session.studyMeasures.feltUnderstood)
            MeasureSlider(title: "对话兼顾了温柔与坦诚", value: $model.session.studyMeasures.compassionateCandor)
            MeasureSlider(title: "我感到被推动或被说服", value: $model.session.studyMeasures.reactance)
            MeasureSlider(title: "我更清楚责任、限制与可控部分", value: $model.session.studyMeasures.responsibilityClarity)
            MeasureSlider(title: "卡片的解释主要来自我自己", value: $model.session.studyMeasures.interpretationOwnership)
            MeasureSlider(title: "我原本就熟悉这张图的传统含义", value: $model.session.studyMeasures.cardFamiliarity)
            HStack { Button("保存在本机", action: model.save).buttonStyle(.borderedProminent); Button("删除记录", role: .destructive, action: model.delete).buttonStyle(.bordered) }
            if let exportURL = model.exportURL {
                ShareLink(item: exportURL) { Label("导出研究 JSON", systemImage: "square.and.arrow.up") }.buttonStyle(.bordered)
            } else {
                Button("准备去标识化研究导出", action: model.prepareExport).buttonStyle(.bordered)
            }
            if !model.saveNotice.isEmpty { Text(model.saveNotice).font(.caption).foregroundStyle(.secondary) }
            Button("开始新的反思", action: model.restart).frame(maxWidth: .infinity)
        }.cardStyle()
    }
}

private struct MeasureSlider: View {
    let title: String
    @Binding var value: Double
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack { Text(title).font(.subheadline); Spacer(); Text("\(Int(value))").monospacedDigit().foregroundStyle(.secondary) }
            Slider(value: $value, in: 1...7, step: 1)
        }
    }
}

private struct TypingIndicator: View {
    var body: some View { HStack { ProgressView().controlSize(.small); Text("正在组织回应…").font(.caption).foregroundStyle(.secondary); Spacer() }.padding(.horizontal) }
}

private struct PauseOverlay: View {
    let resume: () -> Void
    var body: some View { ZStack { Color.black.opacity(0.35).ignoresSafeArea(); VStack(spacing: 16) { Image(systemName: "pause.circle.fill").font(.largeTitle); Text("反思已暂停").font(.headline); Button("继续", action: resume).buttonStyle(.borderedProminent) }.padding(30).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24)) } }
}

private extension View {
    func cardStyle() -> some View { padding(16).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18)).shadow(color: .black.opacity(0.04), radius: 8, y: 3) }
}
