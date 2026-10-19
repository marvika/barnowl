cask "barn-owl" do
  version "0.11.1"
  sha256 "d26e5e3e08d3cfa2b182bed76b6d6c4bf0a3cc86d01afabb8bc52750dbc64401"

  url "https://github.com/marvika/barnowl/releases/download/v#{version}/BarnOwl-#{version}.zip"
  name "Barn Owl"
  desc "Menu bar organiser and keep-awake utility with a playful owl"
  homepage "https://github.com/marvika/barnowl"

  livecheck do
    url :url
    strategy :github_latest
  end

  # Barn Owl updates itself with Sparkle, so `brew upgrade` leaves it alone.
  auto_updates true
  depends_on macos: :tahoe

  app "Barn Owl.app"
  binary "#{appdir}/Barn Owl.app/Contents/Resources/barnowl"

  uninstall quit:       "io.github.marvika.BarnOwl",
            login_item: "Barn Owl"

  zap trash: [
    "~/Library/Application Support/Barn Owl",
    "~/Library/Caches/io.github.marvika.BarnOwl",
    "~/Library/HTTPStorages/io.github.marvika.BarnOwl",
    "~/Library/Preferences/io.github.marvika.BarnOwl.plist",
  ]
end
