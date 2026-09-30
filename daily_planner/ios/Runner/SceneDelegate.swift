import UIKit
import Flutter

@available(iOS 13.0, *)
@objc(SceneDelegate)
class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        
        // Initialize the window and attach the Flutter view controller
        window = UIWindow(windowScene: windowScene)
        let flutterViewController = FlutterViewController(project: nil, nibName: nil, bundle: nil)
        
        // Register Flutter plugins to the new view controller
        GeneratedPluginRegistrant.register(with: flutterViewController)
        
        window?.rootViewController = flutterViewController
        window?.makeKeyAndVisible()
    }
}