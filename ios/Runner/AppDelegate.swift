import UIKit
import Flutter
import LocalAuthentication
import Photos

@main
@objc class AppDelegate: FlutterAppDelegate {
    lazy var flutterEngine = FlutterEngine(name: "jasmine_engine")

    private func setupMethodChannel(
        binaryMessenger: FlutterBinaryMessenger,
        documentDirectory: String
    ) {
        FlutterMethodChannel(name: "methods", binaryMessenger: binaryMessenger).setMethodCallHandler { (call, result) in
            Thread {
                switch (call.method){
                case "invoke":
                    if let params = call.arguments as? String{
                        let chars = params.cString(using: String.Encoding.utf8)
                        guard let rsp = invoke_ffi(chars!) else {
                            result(FlutterError(code: "native_error", message: "Empty native response", details: nil))
                            return
                        }
                        let response = String.init(utf8String: rsp)
                        free_str_ffi(rsp)
                        if let value = response { result(value) }
                        else { result(FlutterError(code: "native_error", message: "Invalid native response", details: nil)) }
                    } else {
                        result(FlutterError(code: "invalid_arguments", message: "Expected a string", details: nil))
                    }
                    break
                case "saveImageFileToGallery":
                    guard let path = call.arguments as? String else {
                        result(FlutterError(code: "invalid_arguments", message: "Expected a path", details: nil))
                        return
                    }
                    PHPhotoLibrary.shared().performChanges({
                        PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: URL(fileURLWithPath: path))
                    }) { success, _ in
                        DispatchQueue.main.async {
                            if success { result("OK") }
                            else { result(FlutterError(code: "save_failed", message: "Unable to save image to Photos", details: nil)) }
                        }
                    }
                case "iosGetDocumentDir" :
                    result(documentDirectory)
                case "verifyAuthentication":
                    let context = LAContext()
                    let can = context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
                    guard can == true else {
                        result(false)
                        return
                    }
                    context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "身份验证") { (success, error) in
                        result(success)
                    }
                default:
                    result(FlutterMethodNotImplemented)
                }
            }.start()
        }
    }

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {

        let documentDirectory = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0]
        let fromChars = documentDirectory.cString(using: String.Encoding.utf8)

        let applicationSupportDirectory = NSSearchPathForDirectoriesInDomains(.applicationSupportDirectory, .userDomainMask, true)[0]
        let chars = applicationSupportDirectory.cString(using: String.Encoding.utf8)

        migration_ffi(fromChars,chars)
        init_ffi(chars!)

        flutterEngine.run()
        GeneratedPluginRegistrant.register(with: flutterEngine)
        setupMethodChannel(binaryMessenger: flutterEngine.binaryMessenger, documentDirectory: documentDirectory)

        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
}
