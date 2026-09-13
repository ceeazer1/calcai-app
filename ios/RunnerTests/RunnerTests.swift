import Flutter
import UIKit
import XCTest

class RunnerTests: XCTestCase {

  func testReleaseResourcesAreIncluded() {
    let app = Bundle.main
    XCTAssertEqual(app.bundleIdentifier, "com.calcai.calcaiApp")
    XCTAssertNotNil(app.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"))
    XCTAssertNotNil(app.object(forInfoDictionaryKey: "NSBluetoothAlwaysUsageDescription"))
    XCTAssertNotNil(app.object(forInfoDictionaryKey: "NSPhotoLibraryAddUsageDescription"))
  }

}
