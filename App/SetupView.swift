import SwiftUI
import SwitcherKit

/// First run: find the heater on the network, or enter its address by hand.
struct SetupView: View {
    @EnvironmentObject var model: AppModel
    @State private var phase: Phase = .intro
    @State private var host = ""
    @State private var deviceID = ""
    @State private var error: String?

    enum Phase: Equatable { case intro, searching, found(DiscoveredHeater), manual, connecting }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch phase {
            case .intro:
                Text("בוא נחבר את הדוד").font(.system(size: 22, weight: .bold))
                Text("וודא שהאייפון מחובר ל-WiFi של הבית. האפליקציה תחפש את הדוד ברשת. בפעם הראשונה אייפון יבקש אישור לגישה לרשת המקומית - צריך לאשר.")
                    .foregroundStyle(Theme.muted).lineSpacing(3)
                Button("חפש את הדוד") { search() }.buttonStyle(PrimaryStyle())
                Button("הזן את הפרטים בעצמי") { phase = .manual }.buttonStyle(SecondaryStyle())

            case .searching:
                HStack(spacing: 12) {
                    ProgressView().tint(Theme.accent)
                    Text("מחפש את הדוד ברשת...").foregroundStyle(Theme.muted)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 40)

            case .found(let h):
                Text("נמצא דוד").font(.system(size: 22, weight: .bold))
                VStack(alignment: .leading, spacing: 4) {
                    Text(h.name.isEmpty ? h.model : h.name).font(.system(size: 17, weight: .semibold))
                    Text("\(h.model) · \(h.ip)").font(.system(size: 13)).foregroundStyle(Theme.muted)
                        .environment(\.layoutDirection, .leftToRight)
                }
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .glass(20, selected: true)
                Button("זה הדוד שלי") { use(h) }.buttonStyle(PrimaryStyle())

            case .manual, .connecting:
                Text("פרטי הדוד").font(.system(size: 22, weight: .bold))
                Text("אייפון לא תמיד מאפשר לאפליקציה למצוא את הדוד לבד. אפשר להזין את הפרטים פעם אחת, ומשם הכול אוטומטי.")
                    .foregroundStyle(Theme.muted).lineSpacing(3)
                Field(label: "כתובת IP של הדוד", text: $host, placeholder: "192.168.1.37", keyboard: .decimalPad)
                Field(label: "מזהה מכשיר (6 תווים)", text: $deviceID, placeholder: "a1b2c3", keyboard: .asciiCapable)
                Hint()
                if let error { Text(error).font(.system(size: 14)).foregroundStyle(Theme.bad) }
                Button {
                    connect()
                } label: {
                    HStack {
                        if phase == .connecting { ProgressView().tint(Theme.onAccent) }
                        Text(phase == .connecting ? "מתחבר..." : "התחבר")
                    }
                }
                .buttonStyle(PrimaryStyle())
                .disabled(phase == .connecting)
                Button("חפש שוב ברשת") { search() }.buttonStyle(SecondaryStyle())
            }
        }
        .padding(.top, 8)
    }

    private func search() {
        error = nil
        phase = .searching
        Task {
            // poke the network first so iOS shows the local-network prompt
            _ = await SwitcherClient(host: "255.255.255.255", deviceID: "000000", deviceKey: "00", timeout: 1).poke()
            let found = await SwitcherListener.discover(seconds: 8)
            if let h = found.first { phase = .found(h) }
            else { phase = .manual; error = "לא מצאתי את הדוד אוטומטית. הזן את הפרטים למטה." }
        }
    }

    private func use(_ h: DiscoveredHeater) {
        var c = model.config
        c.host = h.ip; c.deviceID = h.deviceID; c.deviceKey = h.deviceKey
        finish(c)
    }

    private func connect() {
        error = nil
        let ip = host.trimmingCharacters(in: .whitespaces)
        let id = deviceID.trimmingCharacters(in: .whitespaces).lowercased()
        guard ip.split(separator: ".").count == 4 else { error = "כתובת ה-IP צריכה להיראות כמו 192.168.1.37"; return }
        guard id.count == 6, Data(hexString: id) != nil else { error = "מזהה המכשיר הוא 6 תווים: ספרות ואותיות a-f"; return }
        phase = .connecting
        Task {
            if let key = await SwitcherClient.findKey(host: ip, deviceID: id) {
                var c = model.config
                c.host = ip; c.deviceID = id; c.deviceKey = key
                finish(c)
            } else {
                phase = .manual
                error = "הדוד לא ענה. בדוק שהכתובת והמזהה נכונים ושאתה על ה-WiFi של הבית."
            }
        }
    }

    private func finish(_ c: HeaterConfig) {
        model.saveConfig(c)
        Notifier.requestPermission()
        model.show("הדוד מחובר")
    }
}

extension SwitcherClient {
    /// A throwaway request whose only job is to trigger the local-network permission prompt.
    func poke() async -> Bool { (try? await state()) != nil }
}

struct Field: View {
    let label: String
    @Binding var text: String
    var placeholder = ""
    var keyboard: UIKeyboardType = .default
    var ltr = true

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 13)).foregroundStyle(Theme.muted)
            TextField(placeholder, text: $text)
                .keyboardType(keyboard)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(size: 17, design: ltr ? .rounded : .default))
                .multilineTextAlignment(ltr ? .leading : .trailing)
                .environment(\.layoutDirection, ltr ? .leftToRight : .rightToLeft)
                .padding(12)
                .glass(14)
        }
    }
}

struct Hint: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("איפה מוצאים את הפרטים?").font(.system(size: 13, weight: .semibold))
            Text("כתובת ה-IP מופיעה ברשימת המכשירים בראוטר, ולפעמים גם במסך המידע של הדוד באפליקציה של סוויץ׳ר. את המזהה הכי קל למצוא עם הסקריפט discover.py שבמאגר, מהמחשב, כשהוא על אותה רשת. כדאי גם לקבע לדוד כתובת קבועה בראוטר, כדי שה-IP לא ישתנה.")
                .font(.system(size: 13)).foregroundStyle(Theme.muted).lineSpacing(2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(16)
    }
}
