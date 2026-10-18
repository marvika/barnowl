cask "barn-owl" do
  version "0.9.1"
  sha256 "23342f8eebfb05a0bd301de0d6e4fd221f9b8ddddf37c84bd87d3628123b8331"

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
