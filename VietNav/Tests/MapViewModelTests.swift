import XCTest
@testable import VietNavCore

@MainActor
final class MapViewModelTests: XCTestCase {
    func testCameraDefaultsAndClamping() {
        let model = MapViewModel()
        XCTAssertEqual(model.zoomLevel, 17)
        XCTAssertEqual(model.pitch, 60)
        XCTAssertTrue(model.isFollowingUser)
        model.setZoom(99)
        model.setPitch(-1)
        model.setBearing(-90)
        XCTAssertEqual(model.zoomLevel, 20)
        XCTAssertEqual(model.pitch, 0)
        XCTAssertEqual(model.heading, 270)
    }

    func testFollowingCanBeRestored() {
        let model = MapViewModel()
        model.stopFollowing()
        XCTAssertFalse(model.isFollowingUser)
        // Không kích hoạt hộp thoại cấp quyền trong unit test.
    }
}
