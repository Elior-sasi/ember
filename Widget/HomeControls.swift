import AppIntents
import SwiftUI
import WidgetKit

// Control Center buttons (iOS 18): any HomeOn device on/off, and any HomeOn scene, without opening the app.

@available(iOS 18.0, *)
struct PickDeviceConfig: ControlConfigurationIntent {
    static var title: LocalizedStringResource = "מכשיר"
    @Parameter(title: "מכשיר") var device: DeviceEntity?
    init() {}
}

@available(iOS 18.0, *)
struct SetDevicePowerIntent: SetValueIntent {
    static var title: LocalizedStringResource = "הדלקה או כיבוי"
    static var isDiscoverable = false
    @Parameter(title: "מכשיר") var deviceID: String
    @Parameter(title: "דולק") var value: Bool
    init() {}
    init(_ id: String) { deviceID = id }
    func perform() async throws -> some IntentResult {
        let id = deviceID, before = HomeLink.devices.first { $0.id == id }?.on ?? false
        HomeLink.mark(id, value)
        do { try await HomeLink.setPower(id, value) } catch { HomeLink.mark(id, before); throw error }
        return .result()
    }
}

@available(iOS 18.0, *)
struct DevicePowerControl: ControlWidget {
    struct Value { var id: String; var name: String; var on: Bool }

    struct Provider: AppIntentControlValueProvider {
        func previewValue(configuration: PickDeviceConfig) -> Value {
            Value(id: configuration.device?.id ?? "", name: configuration.device?.name ?? "מכשיר", on: false)
        }
        func currentValue(configuration: PickDeviceConfig) async throws -> Value {
            guard let e = configuration.device else { return Value(id: "", name: "בחר מכשיר", on: false) }
            let all = await HomeLink.refresh([e.id])
            let d = all.first { $0.id == e.id }
            return Value(id: e.id, name: d?.name ?? e.name, on: d?.on ?? false)
        }
    }

    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: "com.elior.homeon.device", provider: Provider()) { v in
            ControlWidgetToggle(v.name, isOn: v.on, action: SetDevicePowerIntent(v.id)) { on in
                Label(on ? "דולק" : "כבוי", systemImage: "power")
            }
            .tint(Theme.accent)
        }
        .displayName("מכשיר של HomeOn")
        .description("הדלקה וכיבוי של מכשיר, ישר ממרכז הבקרה.")
        .promptsForUserConfiguration()
    }
}

@available(iOS 18.0, *)
struct PickSceneConfig: ControlConfigurationIntent {
    static var title: LocalizedStringResource = "סצנה"
    @Parameter(title: "סצנה") var scene: SceneEntity?
    init() {}
}

@available(iOS 18.0, *)
struct SceneControl: ControlWidget {
    struct Value { var id: String; var name: String }
    struct Provider: AppIntentControlValueProvider {
        func previewValue(configuration: PickSceneConfig) -> Value { Value(id: configuration.scene?.id ?? "", name: configuration.scene?.name ?? "סצנה") }
        func currentValue(configuration: PickSceneConfig) async throws -> Value { Value(id: configuration.scene?.id ?? "", name: configuration.scene?.name ?? "בחר סצנה") }
    }

    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: "com.elior.homeon.scene", provider: Provider()) { v in
            ControlWidgetButton(action: RunSceneIntent(scene: SceneEntity(id: v.id, name: v.name))) {
                Label(v.name, systemImage: "sparkles")
            }
        }
        .displayName("סצנה של HomeOn")
        .description("הפעלת סצנה בלחיצה, ממרכז הבקרה.")
        .promptsForUserConfiguration()
    }
}
