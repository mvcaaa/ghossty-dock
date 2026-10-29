@testable import DockLogic
import XCTest

final class LocalNetworkTests: XCTestCase {
    func testGatewayFromRoute() {
        let route = """
               route to: default
            destination: default
                   mask: default
                gateway: 192.168.1.1
              interface: en0
            """
        XCTAssertEqual(DockLocalNetwork.parseGateway(route), "192.168.1.1")
    }

    func testNoIPv4GatewayIsNil() {
        XCTAssertNil(DockLocalNetwork.parseGateway("   route to: default\n  interface: utun4\n"))
        XCTAssertNil(DockLocalNetwork.parseGateway("    gateway: fe80::1%en0\n"))
        XCTAssertNil(DockLocalNetwork.parseGateway(""))
    }
}
