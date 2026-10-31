import AppKit
import SwiftUI

struct AlarmsPane: View {
    @ObservedObject var store: AlarmStore = .shared
    @State private var editing: UserAlarm?
    @State private var deleting: UserAlarm?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("확인할 때까지 지정한 분 간격으로 알립니다.")
                    .font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button { editing = UserAlarm() } label: { Image(systemName: "plus") }
                    .help("알람 추가").accessibilityLabel("알람 추가")
                    .disabled(store.storageError != nil)
            }
            if let error = store.storageError {
                Text(verbatim: error).foregroundStyle(.red)
            }
            if store.alarms.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "alarm").font(.system(size: 32)).foregroundStyle(.secondary)
                    Text("등록된 알람이 없습니다")
                    Button("알람 추가") { editing = UserAlarm() }
                        .disabled(store.storageError != nil)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(store.alarms) { alarm in
                            row(alarm)
                        }
                    }
                }
            }
            Text("팝업은 10초 후 사라지며, 확인하지 않으면 다시 표시됩니다. 잠자기 중에는 알릴 수 없으며 깨어나거나 앱을 실행하면 놓친 알람을 표시합니다.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(24)
        .sheet(item: $editing) { alarm in
            AlarmEditor(alarm: alarm) { store.save($0) }
        }
        .alert("이 알람을 삭제할까요?", isPresented: Binding(
            get: { deleting != nil }, set: { if !$0 { deleting = nil } }
        )) {
            Button("취소", role: .cancel) { deleting = nil }
            Button("삭제", role: .destructive) {
                if let alarm = deleting { store.remove(alarm.id) }
                deleting = nil
            }
        }
    }

    private func row(_ alarm: UserAlarm) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(verbatim: alarm.timeLabel).font(.system(size: 22, weight: .semibold).monospacedDigit())
                Spacer()
                Toggle("알람 켜기", isOn: Binding(
                    get: { alarm.isEnabled }, set: { store.setEnabled(alarm.id, $0) }
                ))
                .labelsHidden().toggleStyle(.switch)
                .accessibilityLabel("\(alarm.timeLabel) \(alarm.displayMessage) 알람 켜기")
            }
            Text(verbatim: alarm.displayMessage).lineLimit(2)
            Text(verbatim: scheduleLabel(alarm) + " · \(alarm.repeatMinutes)분마다 반복" + (alarm.soundEnabled ? " · 소리 켜짐" : " · 무음"))
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                if alarm.activeSince != nil {
                    Button("확인 · 반복 종료") { store.acknowledge(alarm.id) }
                        .buttonStyle(.borderedProminent)
                } else if alarm.isEnabled, let due = alarm.nextDue {
                    Text("다음: \(due.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("수정") { editing = alarm }
                Button { deleting = alarm } label: { Image(systemName: "trash") }
                    .help("알람 삭제").accessibilityLabel("알람 삭제")
            }
        }
        .padding(14)
        .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
        .disabled(store.storageError != nil)
    }

    private func scheduleLabel(_ alarm: UserAlarm) -> String {
        switch alarm.schedule {
        case .daily: return "매일"
        case .once: return alarm.date.formatted(date: .abbreviated, time: .omitted) + " 1회"
        case .weekdays:
            return AlarmEditor.weekdayNames.enumerated().compactMap { index, name in
                alarm.weekdays.contains(index + 1) ? name : nil
            }.joined(separator: " · ")
        }
    }
}

private struct AlarmEditor: View {
    static let weekdayNames = ["일", "월", "화", "수", "목", "금", "토"]
    @Environment(\.dismiss) private var dismiss
    @State private var alarm: UserAlarm
    let save: (UserAlarm) -> Void

    init(alarm: UserAlarm, save: @escaping (UserAlarm) -> Void) {
        _alarm = State(initialValue: alarm)
        self.save = save
    }

    private var clock: Binding<Date> {
        Binding(get: {
            Calendar.current.date(bySettingHour: alarm.hour, minute: alarm.minute, second: 0, of: .now) ?? .now
        }, set: {
            let parts = Calendar.current.dateComponents([.hour, .minute], from: $0)
            alarm.hour = parts.hour ?? 0
            alarm.minute = parts.minute ?? 0
        })
    }

    var body: some View {
        VStack(spacing: 12) {
            Text("알람 설정").font(.title2.bold()).padding(.top, 20)
            Form {
                Picker("일정", selection: $alarm.schedule) {
                    ForEach(UserAlarm.Schedule.allCases, id: \.self) { schedule in
                        Text(verbatim: schedule.title).tag(schedule)
                    }
                }
                DatePicker("시간", selection: clock, displayedComponents: .hourAndMinute)
                if alarm.schedule == .weekdays {
                    HStack(spacing: 6) {
                        ForEach(1...7, id: \.self) { day in
                            Toggle(Self.weekdayNames[day - 1], isOn: Binding(
                                get: { alarm.weekdays.contains(day) },
                                set: { if $0 { alarm.weekdays.insert(day) } else { alarm.weekdays.remove(day) } }
                            ))
                            .toggleStyle(.button)
                        }
                    }
                    if alarm.weekdays.isEmpty {
                        Text("요일을 하나 이상 선택해 주세요.").font(.caption).foregroundStyle(.red)
                    }
                }
                if alarm.schedule == .once {
                    DatePicker("날짜", selection: $alarm.date, displayedComponents: .date)
                    if let due = alarm.nextOccurrence(after: .now, calendar: .current), due < .now {
                        Text("지난 시각입니다. 저장 후 바로 알림을 표시합니다.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Stepper(value: $alarm.repeatMinutes, in: 1...1440) {
                    HStack {
                        Text("반복 간격 (분)")
                        TextField("분", value: $alarm.repeatMinutes, format: .number)
                            .frame(width: 65).multilineTextAlignment(.trailing)
                    }
                }
                Text("1~1,440분 · 확인을 누르면 이번 알람의 반복이 종료됩니다.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("알림 소리", isOn: $alarm.soundEnabled)
                TextField("문구 (비워 두면 눈썹 알림)", text: Binding(
                    get: { alarm.message }, set: { alarm.message = String($0.prefix(UserAlarm.messageLimit)) }
                ), axis: .vertical)
                .lineLimit(2...3)
                .accessibilityLabel("알림 문구, 최대 100자")
                Text("\(alarm.message.count)/100자").font(.caption).foregroundStyle(.secondary)
            }
            .formStyle(.grouped)
            Text("팝업 미리보기").font(.caption).foregroundStyle(.secondary)
            AlarmPopupContent(alarm: alarm)
                .allowsHitTesting(false)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("미리보기: \(alarm.displayMessage)")
            Text("수정하여 저장하면 진행 중인 반복을 종료하고 새 일정으로 예약합니다.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("취소") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("저장") { save(alarm); dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .disabled((alarm.schedule == .weekdays && alarm.weekdays.isEmpty) || !(1...1440).contains(alarm.repeatMinutes))
            }
            .padding(.horizontal, 24).padding(.bottom, 20)
        }
        .frame(width: 470, height: min(730, (NSScreen.main?.visibleFrame.height ?? 810) - 80))
    }
}
