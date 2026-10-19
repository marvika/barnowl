cask "barn-owl" do
  version "0.11.3"
  sha256 "59d4fbcea75d9b8be6ea54852ffa097ad350ef659b1fb7e4010be2aeae57488a"

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
    "~/Library/Containers/io.github.marvika.BarnOwl.Widget",
    "~/Library/Group Containers/2S5J2CYWPZ.io.github.marvika.BarnOwl",
    "~/Library/Caches/io.github.marvika.BarnOwl",
    "~/Library/HTTPStorages/io.github.marvika.BarnOwl",
    "~/Library/Preferences/io.github.marvika.BarnOwl.plist",
  ]
end
