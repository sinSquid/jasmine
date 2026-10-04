import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController.init()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    
    MethodsPlugin.register(
        with: flutterViewController.registrar(forPlugin:"methods")
    )

    super.awakeFromNib()
  }
}


public class MethodsPlugin: NSObject, FlutterPlugin {

    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "methods", binaryMessenger: registrar.messenger)
        let instance = MethodsPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        Thread {
            switch call.method {
            case "invoke":
                if let params = call.arguments as? String {
                    let chars = params.cString(using: String.Encoding.utf8)
                    guard let rsp = invoke_ffi(chars!) else {
                        result(FlutterError(code: "native_error", message: "Empty native response", details: nil))
                        return
                    }
                    let str = String.init(utf8String: rsp)
                    free_str_ffi(rsp)
                    if let value = str { result(value) }
                        else { result(FlutterError(code: "native_error", message: "Invalid native response", details: nil)) }
                } else {
                    result(FlutterError(code: "invalid_arguments", message: "Expected a string", details: nil))
                }
            default:
                result(FlutterMethodNotImplemented)
            }
        }.start()
    }
}
