#if SWIFT_PACKAGE
import GoldPriceCore
#endif
import SwiftUI
import Cocoa

@MainActor struct RulesSettingsView: View {
    @ObservedObject var model: SettingsModel
    @State private var filter: Instrument?
    @State private var draft: RuleDraft?
    @State private var deleting: AlertRule?
    @State private var confirmDisable = false
    private var visibleRules: [AlertRule] { model.rules.filter { filter == nil || $0.instrument == filter } }
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Picker("品种", selection: $filter) {
                    Text("全部品种").tag(Optional<Instrument>.none)
                    ForEach(Instrument.alertInstruments, id: \.self) { Text($0.displayName).tag(Optional($0)) }
                }.frame(width: 224)
                Spacer()
                Button("停用全部") { confirmDisable = true }.disabled(model.activeRuleCount == 0)
                Button { draft = RuleDraft(instrument: filter ?? .minsheng) } label: { Label("添加规则", systemImage: "plus") }
                    .disabled(model.alertStore == nil)
            }
            HStack { Text("\(model.activeRuleCount) 条生效中"); Spacer(); Text("穿越提醒需先回撤到目标价外 0.1% 再激活") }
                .font(.caption).foregroundColor(.secondary)
            ScrollView {
                LazyVStack(spacing: 8) {
                    if visibleRules.isEmpty {
                        VStack(spacing: 12) { Image(systemName: "bell.badge").font(.largeTitle); Text("添加一条规则，让价格到位时提醒你。") }
                            .foregroundColor(.secondary).padding(32)
                    }
                    ForEach(visibleRules, id: \.id) { rule in
                        RuleRow(rule: rule, model: model, edit: { draft = RuleDraft(rule: rule) }, delete: { deleting = rule })
                    }
                }
            }
        }.padding(16)
            .sheet(item: $draft) { value in RuleEditorView(model: model, draft: value) }
            .alert("停用全部预警？", isPresented: $confirmDisable) {
                Button("取消", role: .cancel) {}
                Button("停用全部", role: .destructive) { model.disableAll() }
            } message: { Text("规则会保留，可随时重新开启。") }
            .alert("删除这条预警？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
                Button("取消", role: .cancel) { deleting = nil }
                Button("删除", role: .destructive) { if let rule = deleting { model.remove(rule) }; deleting = nil }
            }
    }
}
@MainActor private struct RuleRow: View {
    let rule: AlertRule
    @ObservedObject var model: SettingsModel
    let edit: () -> Void
    let delete: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(rule.instrument.displayName).font(.headline)
                    Text(rule.direction.displayName).font(.caption).foregroundColor(Color(nsColor: rule.direction == .up ? .systemRed : .systemGreen))
                }.frame(width: 96, alignment: .leading)
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(String(format: "%.2f", rule.price)) \(rule.instrument.unit)").monospacedDigit()
                    Text(MarketPresentation.distance(target: rule.price, info: model.prices.priceInfo(for: rule.instrument)))
                        .font(.caption).monospacedDigit().foregroundColor(.secondary)
                }.frame(width: 144, alignment: .leading)
                VStack(alignment: .leading, spacing: 4) {
                    Text(MarketPresentation.policyText(rule.repeatPolicy)).font(.callout)
                    if rule.repeatPolicy == .once && model.consumedOnce.contains(rule.id) { Text("本次已提醒").font(.caption).foregroundColor(.secondary) }
                    if let step = rule.trailingStep { Text("自动顺延 \(String(format: "%g", step))").font(.caption).foregroundColor(.secondary) }
                }
                Spacer(minLength: 4)
                Toggle("启用", isOn: Binding(get: { rule.enabled }, set: { model.toggle(rule, enabled: $0) })).labelsHidden()
                Button(action: edit) { Image(systemName: "pencil") }.help("编辑规则")
            }
            if !rule.note.isEmpty { Text(rule.note).font(.caption).foregroundColor(.secondary) }
            let info = model.prices.priceInfo(for: rule.instrument)
            if MarketPresentation.isDelayed(info, now: model.now) { Text("现价休市/延迟，距离仅供参考").font(.caption).foregroundColor(.secondary) }
        }.padding(12).background(Color(nsColor: .controlBackgroundColor)).cornerRadius(8)
            .contextMenu { Button("编辑", action: edit); Button("删除", action: delete) }
    }
}
@MainActor struct RuleEditorView: View {
    @ObservedObject var model: SettingsModel
    @State var draft: RuleDraft
    @State private var immediateConfirmed = false
    @Environment(\.dismiss) private var dismiss
    private var current: PriceInfo { model.prices.priceInfo(for: draft.instrument) }
    private var immediate: Bool { draft.triggersImmediately(current) }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(draft.original == nil ? "添加预警规则" : "编辑预警规则").font(.title2)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("品种", selection: $draft.instrument) { ForEach(Instrument.alertInstruments, id: \.self) { Text($0.displayName).tag($0) } }
                    Text("现价 \(current.price) \(draft.instrument.unit)").monospacedDigit().foregroundColor(.secondary)
                    if MarketPresentation.isDelayed(current, now: model.now) { Text("现价休市/延迟，请核对交易平台报价。").font(.caption).foregroundColor(.secondary) }
                    Picker("方向", selection: $draft.direction) { ForEach(AlertDirection.allCases, id: \.self) { Text($0.displayName).tag($0) } }.pickerStyle(.segmented)
                    TextField("目标价", text: $draft.targetText).textFieldStyle(.roundedBorder)
                        .foregroundColor(draft.target == nil && !draft.targetText.isEmpty ? Color(nsColor: .systemRed) : Color(nsColor: .labelColor))
                    HStack(spacing: 8) {
                        ForEach([-2.0,-1,1,2], id: \.self) { percent in
                            Button(String(format: "%+.0f%%", percent)) { draft.fillShortcut(percent: percent, current: current) }.disabled(!current.isValid)
                        }
                        Text("按现价填入").font(.caption).foregroundColor(.secondary)
                    }
                    if immediate {
                        Text("将立即触发：目标价已在当前价格的突破区间内。").foregroundColor(Color(nsColor: .systemRed))
                        Toggle("我已确认，仍保存该规则", isOn: $immediateConfirmed)
                    }
                    Picker("提醒策略", selection: $draft.reminder) { ForEach(ReminderKind.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                    if draft.reminder == .continuous { TextField("间隔（分钟）", text: $draft.intervalMinutes).textFieldStyle(.roundedBorder)
                        .foregroundColor((parsePriceInput(draft.intervalMinutes) ?? 0) > 0 ? Color(nsColor: .labelColor) : Color(nsColor: .systemRed)) }
                    TextField("自动顺延步长（留空或 0 关闭）", text: $draft.stepText).textFieldStyle(.roundedBorder)
                        .foregroundColor(parsePriceInput(draft.stepText) == nil ? Color(nsColor: .systemRed) : Color(nsColor: .labelColor))
                    Text("上破后目标增加步长，下破后目标减少步长。每次穿越须回撤到缓冲区之外才再次提醒。")
                        .font(.caption).foregroundColor(.secondary)
                    if draft.original?.trailingBehavior == .legacyLadder {
                        Text("这条规则来自旧版档位，继续保留旧版整组自动追踪方式；改变品种或方向后使用独立顺延。")
                            .font(.caption).foregroundColor(.secondary)
                    }
                    TextField("备注（可选）", text: $draft.note).textFieldStyle(.roundedBorder)
                    Toggle("启用规则", isOn: $draft.enabled)
                    if let error = draft.validationMessage { Text(error).font(.caption).foregroundColor(Color(nsColor: .systemRed)) }
                    if !model.errorMessage.isEmpty { Text(model.errorMessage).foregroundColor(Color(nsColor: .systemRed)) }
                }
            }
            HStack { Spacer(); Button("取消") { dismiss() }; Button("保存") { if let rule = draft.makeRule(), model.save(rule) { dismiss() } }
                .keyboardShortcut(.defaultAction).disabled(draft.validationMessage != nil || (draft.enabled && immediate && !immediateConfirmed) || model.alertStore == nil) }
        }.padding(16).frame(width: 568, height: 568)
            .onChange(of: draft.targetText) { _ in immediateConfirmed = false }
            .onChange(of: draft.instrument) { _ in immediateConfirmed = false }
            .onChange(of: draft.direction) { _ in immediateConfirmed = false }
    }
}
