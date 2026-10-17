cask "barn-owl" do
  version "0.7.1"
  sha256 "984b96dcaaa866cccc1ebf6c2bc3839235a09e166dfc7ff366b1cf84a4204cf1"

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
