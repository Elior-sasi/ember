import XCTest
@testable import SwitcherKit

/// Expected values were produced by the aioswitcher Python library, so these
/// tests prove the Swift port builds byte-identical packets.
final class SwitcherKitTests: XCTestCase {
    let ts = "11223344", sid = "aabbccdd", dev = "a1b2c3"

    func testLogin() {
        XCTAssertEqual(SwitcherProtocol.login(timestamp: ts, deviceKey: "1a").hexString, "fef052000232a100000000003400010000000000000000001122334400000000000000000000f0fe1a0000000000000000000000000000000000000000000000000000000000000000000000000003289f38")
    }
    func testGetState() {
        XCTAssertEqual(SwitcherProtocol.getState(session: sid, timestamp: ts, deviceID: dev).hexString, "fef0300002320103aabbccdd3400010000000000000000001122334400000000000000000000f0fea1b2c300b04b049e")
    }
    func testControl() {
        XCTAssertEqual(SwitcherProtocol.control(on: true, minutes: 30, session: sid, timestamp: ts, deviceID: dev).hexString, "fef05d0002320102aabbccdd3400010000000000000000001122334400000000000000000000f0fea1b2c300000000000000000000000000000000000000000000000000000000000000000000000000010600010008070000bced470c")
        XCTAssertEqual(SwitcherProtocol.control(on: true, minutes: 0, session: sid, timestamp: ts, deviceID: dev).hexString, "fef05d0002320102aabbccdd3400010000000000000000001122334400000000000000000000f0fea1b2c300000000000000000000000000000000000000000000000000000000000000000000000000010600010000000000efedb5b6")
        XCTAssertEqual(SwitcherProtocol.control(on: false, minutes: 0, session: sid, timestamp: ts, deviceID: dev).hexString, "fef05d0002320102aabbccdd3400010000000000000000001122334400000000000000000000f0fea1b2c3000000000000000000000000000000000000000000000000000000000000000000000000000106000000000000004fa82252")
    }
    func testAutoShutdown() {
        XCTAssertEqual(SwitcherProtocol.setAutoShutdown(seconds: 7200, session: sid, timestamp: ts, deviceID: dev).hexString, "fef05b0002320102aabbccdd3400010000000000000000001122334400000000000000000000f0fea1b2c300000000000000000000000000000000000000000000000000000000000000000000000000040400201c0000e13e2a10")
    }
    func testSchedulePackets() {
        XCTAssertEqual(SwitcherProtocol.getSchedules(session: sid, timestamp: ts, deviceID: dev).hexString, "fef0570002320102aabbccdd3400010000000000000000001122334400000000000000000000f0fea1b2c3000000000000000000000000000000000000000000000000000000000000000000000000000600003eca41b7")
        XCTAssertEqual(SwitcherProtocol.deleteSchedule(slot: 3, session: sid, timestamp: ts, deviceID: dev).hexString, "fef0580002320102aabbccdd3400010000000000000000001122334400000000000000000000f0fea1b2c300000000000000000000000000000000000000000000000000000000000000000000000000080100034f9ae3bc")
        XCTAssertEqual(SwitcherProtocol.createSchedule(weekdays: 0x3e, start: 0x33221100, end: 0x77665544, session: sid, timestamp: ts, deviceID: dev).hexString, "fef0630002320102aabbccdd3400010000000000000000001122334400000000000000000000f0fea1b2c300000000000000000000000000000000000000000000000000000000000000000000000000030c00ff013e010011223344556677f87b3587")
    }

    func testParseState() {
        let r = Data(hexString: "52f22665a60c12d289185d950ee8813609166f6b113d178d6c0fd3901ff239a1a095f20f9395650cf9380b8edb224a6b248a1e924e8fd0ae2e1a9492a3305f188cb610900f9e347fae886d0150860bec745c4c3fcb2eb2c73e0807000064020000201c0000121e836b2ac15726ee")!
        XCTAssertEqual(SwitcherParse.session(r), "89185d95")
        let s = SwitcherParse.state(r)
        XCTAssertEqual(s, HeaterState(isOn: true, powerWatts: 2950, secondsLeft: 1800, secondsOn: 612, autoShutdownSeconds: 7200))
    }
    func testParseSchedules() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let list = SwitcherParse.schedules(Data(hexString: "00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000013e01e82ccb6a7437cb6a000000000301000198c7cb6aa0cecb6a0000000000000000")!, calendar: cal)
        XCTAssertEqual(list, [
            HeaterSchedule(slot: 0, weekdays: 0x3e, startMinutes: 390, endMinutes: 435),
            HeaterSchedule(slot: 3, weekdays: 0, startMinutes: 1050, endMinutes: 1080),
        ])
    }
    func testDiscovery() {
        let h = SwitcherDiscovery.parse(Data(hexString: "fef00af6ab13c38e92cae0d15057b159987fa1b2c311d717f14579b2aa100fbbb34fa593feaed2721ab7426f696c657200000000000000000000000000000000000000000000000000000317c0a801256afc5baee261f53b26152d263ba83b037cd4962e434801256b885e9c9051f320b0db83f39ea7adbd0d74e6dec7f3dfaecc8f646566011ac20b660f3011fc3570291c5784030000912689191815000012df359d6026")!)
        XCTAssertEqual(h, DiscoveredHeater(deviceID: "a1b2c3", deviceKey: "1a", ip: "192.168.1.37", name: "Boiler", model: "Switcher V4"))
    }
    func testWeekdays() {
        XCTAssertEqual(WeekdayBits.mask([0, 1, 2, 3, 4]), 0x9e)   // Sunday-Thursday
        XCTAssertEqual(WeekdayBits.indices(0x3e), [1, 2, 3, 4, 5])
    }
}
