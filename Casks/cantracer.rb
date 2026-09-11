cask "cantracer" do
  version "1.0.1"
  sha256 "2c008d2fe30e3f9b869b9a1f4840d6a1a5610033dd97dc6cd03978fdd26f07a4"

  url "https://github.com/PanterSoft/CANtracer/releases/download/v#{version}/CANtracer-macos.dmg"
  name "CANtracer"
  desc "CAN bus tracer with DBC decoding"
  homepage "https://github.com/PanterSoft/CANtracer"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on :macos

  app "CANtracer.app"

  zap trash: [
    "~/Library/Preferences/dev.cantracer.cantracer.plist",
    "~/Library/Saved Application State/dev.cantracer.cantracer.savedState",
  ]

  # The build is ad-hoc signed, so Gatekeeper quarantines it.
  caveats <<~EOS
    CANtracer is not notarised. If macOS refuses to open it:
      xattr -dr com.apple.quarantine "/Applications/CANtracer.app"
    or install with `brew install --cask --no-quarantine cantracer`.
  EOS
end
