import SwiftUI

/// Entry point tương thích với các phiên bản trước; state chỉ sở hữu tại NavigationScreen.
public struct MapContainerView: View {
    public init() {}
    public var body: some View { NavigationScreen() }
}
