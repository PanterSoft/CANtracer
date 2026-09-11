import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    self.minSize = NSSize(width: 640, height: 480)  // below this the trace layout breaks

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
