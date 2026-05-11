import XCTest
@testable import Clawix

final class ChatSidebarStateTests: XCTestCase {
    func testSimulatorSidebarItemsRoundTripThroughCodableState() throws {
        let iosId = UUID()
        let androidId = UUID()
        let iosUDID = "4B28C82C-D4EB-42E4-BA0F-D9A1DE603E97"
        var state = ChatSidebarState(
            isOpen: true,
            items: [
                .iosSimulator(.init(id: iosId, deviceUDID: iosUDID, deviceName: "iPhone 17")),
                .androidSimulator(.init(id: androidId, avdName: "clawix_pixel_tablet", deviceName: "Pixel Tablet"))
            ],
            activeItemId: androidId
        )

        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(ChatSidebarState.self, from: data)

        XCTAssertEqual(decoded, state)
        XCTAssertEqual(decoded.activeItem?.id, androidId)

        state.activeItemId = iosId
        XCTAssertEqual(state.activeItem?.id, iosId)
    }
}
