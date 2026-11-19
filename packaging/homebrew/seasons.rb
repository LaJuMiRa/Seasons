# Homebrew Cask template for Seasons.
# Copy to Casks/seasons.rb in your tap repository (homebrew-tap) and replace the placeholders:
#   __VERSION__   e.g. 1.0.0
#   __SHA256__    from dist/Seasons-<version>-arm64.zip.sha256 or the GitHub release page
#   __GITHUB_USER__  your GitHub user name
cask "seasons" do
  version "__VERSION__"
  sha256 "__SHA256__"

  url "https://github.com/__GITHUB_USER__/seasons/releases/download/v#{version}/Seasons-#{version}-arm64.zip"
  name "Seasons"
  desc "Seasonal snow, leaves, rain, blossoms and flowers on your desktop"
  homepage "https://github.com/__GITHUB_USER__/seasons"

  depends_on arch: :arm64
  depends_on macos: ">= :sonoma"

  app "Seasons.app"

  uninstall quit: "com.laurenzrauscher.Seasons"

  zap trash: [
    "~/Library/Preferences/com.laurenzrauscher.Seasons.plist",
    "~/Library/Saved Application State/com.laurenzrauscher.Seasons.savedState",
  ]

  caveats <<~EOS
    Seasons is ad-hoc signed but not notarized by Apple (no paid developer account).
    macOS will block the first start. Either allow it in
      System Settings > Privacy & Security > "Open Anyway"
    or remove the quarantine flag once:
      xattr -dr com.apple.quarantine "#{appdir}/Seasons.app"
  EOS
end
