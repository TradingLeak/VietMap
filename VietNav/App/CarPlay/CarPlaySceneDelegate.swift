#if CARPLAY_MAPS
import UIKit
import CarPlay

/// Chỉ là điểm nối thử nghiệm, không phải navigation CarPlay hoàn chỉnh.
/// Chưa bật scene/entitlement cho đến khi được Apple duyệt và có map/trip integration.
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private var interfaceController: CPInterfaceController?
    func templateApplicationScene(_ scene: CPTemplateApplicationScene,
                                  didConnect interfaceController: CPInterfaceController,
                                  to window: CPWindow) {
        self.interfaceController = interfaceController
        let screen = CPInformationTemplate(title: "VietNav chưa hỗ trợ CarPlay", layout: .leading,
                                           items: [], actions: [])
        interfaceController.setRootTemplate(screen, animated: false, completion: nil)
    }
    func templateApplicationScene(_ scene: CPTemplateApplicationScene,
                                  didDisconnectInterfaceController interfaceController: CPInterfaceController,
                                  from window: CPWindow) {
        self.interfaceController = nil
    }
}
#endif
