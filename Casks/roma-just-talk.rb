cask "roma-just-talk" do
  version "1.95.1"
  sha256 "68594bd8476933872edc28b480a3ad81ea6fc8d0f9d537dab9062c30692d8665"

  url "https://github.com/negentropi/roma-just-talk/releases/download/v#{version}/roma.just.talk.app.zip"
  name "roma just talk"
  desc "Dictation with rolling pre-roll capture"
  homepage "https://github.com/negentropi/roma-just-talk"

  livecheck do
    url :url
    strategy :github_latest
  end

  conflicts_with cask: "voiceink"
  depends_on macos: :sonoma

  app "roma just talk.app"

  uninstall quit: ["com.negentropi.RomaJustTalk", "com.prakashjoshipax.VoiceInk"]

  zap trash: [
    "~/Library/Application Support/com.negentropi.RomaJustTalk",
    "~/Library/Application Support/com.prakashjoshipax.VoiceInk",
    "~/Library/Application Support/VoiceInk/CustomSounds",
    "~/Library/Caches/com.negentropi.RomaJustTalk",
    "~/Library/Caches/com.prakashjoshipax.VoiceInk",
    "~/Library/HTTPStorages/com.negentropi.RomaJustTalk",
    "~/Library/HTTPStorages/com.prakashjoshipax.VoiceInk",
    "~/Library/Preferences/com.negentropi.RomaJustTalk.plist",
    "~/Library/Preferences/com.prakashjoshipax.VoiceInk.plist",
    "~/Library/Saved Application State/com.negentropi.RomaJustTalk.savedState",
    "~/Library/Saved Application State/com.prakashjoshipax.VoiceInk.savedState",
  ]

  caveats do
    unsigned_accessibility
  end
end
