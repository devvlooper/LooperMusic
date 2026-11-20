<p align="center">
  <img src="assets/branding/readme_logo.png" width="140" height="100" />
</p>

<p align="center">
  <b>Looper Music: your own collection and YouTube Music, in one player.</b>
  <br />
  Word-synced lyrics, album-coloured themes, online streaming. On Android.
</p>


<p align="center">
  <img height="20" src="https://img.shields.io/github/v/release/devvlooper/LooperMusic?style=flat-square&color=000000" />
  <img height="20" src="https://img.shields.io/github/downloads/devvlooper/LooperMusic/total?style=flat-square&label=Downloads&color=blue&labelColor=000000&logo=github" />
  <img height="20" src="https://img.shields.io/github/stars/devvlooper/LooperMusic?style=flat-square&color=000000" />
  <img height="20" src="https://img.shields.io/badge/platform-Android-blueviolet?style=flat-square" />
  <img height="20" src="https://img.shields.io/badge/license-GPL--3.0-green?style=flat-square" />
</p>

<p align="center">
  <a href="https://looper-player.web.app/"><img height="28" src="https://img.shields.io/badge/Website-looper--player.web.app-000000?style=for-the-badge&logo=firefoxbrowser&logoColor=white" alt="Website" /></a>
  <a href="https://play.google.com/store/apps/details?id=com.looper.player"><img height="28" src="https://img.shields.io/badge/Google_Play-414141?style=for-the-badge&logo=googleplay&logoColor=white" alt="Google Play" /></a>
  <a href="https://t.me/looperPlayer"><img height="28" src="https://img.shields.io/badge/Telegram-26A5E4?style=for-the-badge&logo=telegram&logoColor=white" alt="Telegram" /></a>
  <a href="https://discord.gg/9nFHhg94wn"><img height="28" src="https://img.shields.io/badge/Discord-5865F2?style=for-the-badge&logo=discord&logoColor=white" alt="Discord" /></a>
</p>


<p align="center">
  <a href="https://ko-fi.com/sthrnilshaaa">
    <img src="https://raw.githubusercontent.com/icedman/dash2dock-lite/main/docs/support-kofi.png" alt="Ko-fi" />
  </a>
</p>

<p align="center">
  <a href="#features">Features</a> •
  <a href="#online">Online streaming</a> •
  <a href="#screenshots">Screenshots</a> •
  <a href="#videos">Videos</a> •
  <a href="#installation">Install</a> •
  <a href="#tech-stack">Built with</a> •
  <a href="#contributing">Contributing</a> •
  <a href="#contributors">Credits</a> •
  <a href="#contact">Contact</a>
</p>

<p align="center">
  <img src="media/banner2.jpg" width="100%" alt="Looper Music" />
</p> 

<p align="center">
  <img src="media/showcase.gif" width="100%" alt="Looper Music showcase" />
</p>

---

## What is Looper Music?

Looper Music plays the music files you already own, and, when you want it to, streams from YouTube Music too. Point it at a folder and it builds a library you can browse by song, album, artist, genre or folder. Turn on online music and the same Home screen gains search, personalised shelves, mixes and stations, with online and local songs sharing one queue, one player and one lyrics page.

We started it because we wanted a player that makes the album art the centre of the screen. The player, the lyrics page and the accents across the app all pick up the colours of the current cover.

There are no ads and no subscription. Your library stays on your device. Online mode is **off by default**; the app goes online only for lyrics, update checks, and the streaming features you switch on.

<a id="features"></a>
## Features

<img src="media/output.gif" align="right" width="170" alt="Word-synced lyrics" />

- **Lyrics that follow the song.** Word-by-word or line-by-line highlighting, tap a line to jump to it, adjust the offset if the timing is off. Lyrics come from 18 online sources (reorder or disable any of them in Settings) or from your own `.lrc` file.
- **Animated artwork.** Apple Music style motion covers and artist banners for songs that have them, with a strict matcher so the wrong video never plays over your song.
- **Looper Analyze.** A report card for your listening: time listened, streaks, top songs and artists, busiest day, and a genre breakdown.
- **Colours from the artwork.** The player background, buttons and highlights change with each track. Or pick your own theme and font.
- **18-band equalizer with AutoEQ.** Drag the curve to shape the sound, ±20 dB per band. Per-song presets, bass and tilt controls, and headphone correction profiles.
- **Picks up where you left off.** The queue, the track and the position are restored when you reopen the app.
- **Fast search.** Search by title, artist, album, or a line of the lyrics. Local and online results side by side.
- **Reorder Home your way.** Hold any row on Home to drag it into the order you want.
- **Home-screen widgets** on Android, in 12 layouts, plus a quick-play shortcut.
- **14 languages**, including Hindi, Arabic, Japanese, Korean and Chinese.
- **Backups.** Export your app data and import it again later.
- **Self-updating** GitHub build on Android.

<br clear="right"/>

<a id="online"></a>
## Online streaming

Switch on **Settings > Online music** and Looper Music streams from YouTube Music next to your local library.

- **Search and play anything.** Songs, albums, artists and playlists, played through the normal queue with the same player, equalizer and lyrics.
- **A Home feed that knows your taste, even signed out.** Guest mode seeds recommendations from the library you already have: quick picks, mixes, stations, moods and genre rows built from what you actually play. Pick your interests once in the taste setup, or keep several taste profiles and switch between them.
- **Sign in for your own YouTube Music.** On Android with microG (or ReVanced GmsCore) your Google account is picked up with no extra prompt. Without it, sign in through a real Google login screen inside the app. Then you get *Listen again*, *Mixed for you*, your likes, playlists, saved albums and subscriptions, synced into Looper's library, and your plays recorded to your YouTube history. Multiple accounts and brand channels are supported.
- **Downloads.** Save online songs as tagged `.m4a` files into a folder you choose. They then behave like any other local track.
- **Plays once, replays without a network.** Every streamed song and its lyrics are cached, so a replay needs no network. Choose streaming and download quality separately for Wi-Fi and mobile data.
- **Mark what you don't want.** "Not interested" removes a song or artist from future recommendations.
- **Honest loading.** Buffering is shown as buffering, not as paused; the seek bar shows the buffered range; failed streams fall back and skip instead of hanging. If YouTube ever stops responding, **Refresh** on the Home header resets the session.

Online mode is compiled into the GitHub build (`github` flavor) and disabled in the Play Store build. YouTube Music is a trademark of Google LLC; Looper Music is not affiliated with Google.

---

<a id="screenshots"></a>
## Screenshots

### Android

<p align="center">
  <img src="media/screenshots/fluid_player_playing.png" width="32%" alt="Now playing" />
  <img src="media/screenshots/player_lyrics.png" width="32%" alt="Lyrics" />
  <img src="media/screenshots/player_lyrics_blur.png" width="32%" alt="Lyrics with blur" />
</p>
<p align="center">
  <img src="media/screenshots/home_today_mix.png" width="32%" alt="Home" />
  <img src="media/screenshots/home_surprise_me.png" width="32%" alt="Surprise Me" />
  <img src="media/screenshots/home_for_you.png" width="32%" alt="Artists and albums for you" />
</p>
<p align="center">
  <img src="media/screenshots/home_artist_pick.png" width="32%" alt="Artist pick" />
  <img src="media/screenshots/artist.png" width="32%" alt="Artist" />
  <img src="media/screenshots/album.png" width="32%" alt="Album" />
</p>
<p align="center">
  <img src="media/screenshots/library.png" width="32%" alt="Library" />
  <img src="media/screenshots/songs.png" width="32%" alt="Songs" />
  <img src="media/screenshots/search.png" width="32%" alt="Search" />
</p>
<p align="center">
  <img src="media/screenshots/favorites.png" width="32%" alt="Favorites" />
  <img src="media/screenshots/albums.png" width="32%" alt="Albums" />
  <img src="media/screenshots/recently_played.png" width="32%" alt="Recently played" />
</p>
<p align="center">
  <img src="media/screenshots/analyze.png" width="32%" alt="Looper Analyze" />
  <img src="media/screenshots/account.png" width="32%" alt="Account" />
  <img src="media/screenshots/about.png" width="32%" alt="About" />
</p>
<p align="center">
  <img src="media/screenshots/settings.png" width="32%" alt="Settings" />
  <img src="media/screenshots/settings_player_interface.png" width="32%" alt="Player interface settings" />
  <img src="media/screenshots/settings_now_playing.png" width="32%" alt="Now playing settings" />
</p>
<p align="center">
  <img src="media/screenshots/settings_miscellaneous.png" width="32%" alt="Miscellaneous settings" />
  <img src="media/screenshots/card_style.png" width="32%" alt="Card style" />
  <img src="media/screenshots/fluid_player.png" width="32%" alt="Fluid player" />
</p>

---

<a id="videos"></a>
## Videos

<table>
  <tr>
    <td align="center" width="50%">
      <a href="https://youtu.be/KnoETY34sgk">
        <img src="https://i.ytimg.com/vi/KnoETY34sgk/hqdefault.jpg" width="100%" alt="10 Mejores APLICACIONES Android 2026 by YouTutosJeff" />
      </a>
      <br />
      <b><a href="https://youtu.be/KnoETY34sgk">10 Mejores APLICACIONES Android 2026</a></b>
      <br />
      by <a href="https://www.youtube.com/@YouTutosJeff">YouTutosJeff</a>
    </td>
    <td align="center" width="50%">
      <a href="https://youtu.be/t8LsCkGY9-4">
        <img src="https://i.ytimg.com/vi/t8LsCkGY9-4/hqdefault.jpg" width="100%" alt="Introducing Looper Music" />
      </a>
      <br />
      <b><a href="https://youtu.be/t8LsCkGY9-4">Introducing Looper Music</a></b>
      <br />
      the official intro, by <a href="https://www.youtube.com/@TechWithNeelshy">Neelesh Suthar</a>
    </td>
  </tr>
</table>

Thank you to everyone who has made a video about Looper. Made one too? Open an [issue](https://github.com/devvlooper/LooperMusic/issues) or message us on [Telegram](https://t.me/looperPlayer) and we'll add it here.

---

<a id="installation"></a>
## Installation

Android is on [Google Play](https://play.google.com/store/apps/details?id=com.looper.player). The GitHub build, with online streaming and the in-app updater, is on the [Releases](https://github.com/devvlooper/LooperMusic/releases) page.

### Android (`.apk`)
Needs Android 10 or newer.
- Download `looper-player-v<version>-<abi>-online-release.apk` for your phone. `arm64-v8a` is right for almost every phone from the last several years; use `armeabi-v7a` for older ones, `x86_64` for emulators, or `universal` if unsure.
- Open it and tap **Install**. Android will ask you to allow installs from your browser or file manager the first time.
- The GitHub build updates itself from inside the app.
- Verify a download against the `SHA256SUMS-v<version>.txt` file attached to each release.

---

<a id="tech-stack"></a>
## Built with

| | |
| :--- | :--- |
| UI | Flutter & Dart |
| State | Riverpod |
| Database | Isar (local, on-device) |
| Playback | mpv, through `mpv_audio_kit` |
| Streaming | YouTube Music via InnerTube, resolved and cached in Dart |
| Account sign-in | microG / GmsCore, or in-app Google login |
| Tags | `metadata_god` and Android MediaStore |
| Analytics / crash reports | AppAmbit (opt-in, only when an `env.json` is supplied at build time) |

---

<a id="contributing"></a>
## Contributing

Contributions are welcome, whether it's a bug fix, a new feature, a translation or a better screenshot. For anything big, open an [issue](https://github.com/devvlooper/LooperMusic/issues) first so we can talk it through.

### Getting started
1. Fork the repo and create a branch from `main`.
2. Install [Flutter](https://docs.flutter.dev/get-started/install) (Dart 3.11 or newer; releases are built with Flutter 3.47.7).
3. Get the packages. This also generates the translation files:
   ```bash
   flutter pub get
   ```
4. Run it:
   ```bash
   # Use the github flavor for local builds; the play flavor has online mode off
   flutter run --flavor github
   ```
5. If you change a Riverpod provider or an Isar model, regenerate the code:
   ```bash
   dart run build_runner build
   ```
6. Run `flutter analyze` and `flutter test` before you open a pull request, and describe what you changed and how you tested it.

### Translations
All app text lives in `lib/l10n/app_<language>.arb`. To fix a translation, edit that file. To add a new language, copy `app_en.arb` to your language's code and translate the values. Leave the keys and the `{placeholders}` as they are.

### Releasing
Releases are built by the **Build and Release** workflow (manual, `workflow_dispatch`). Bump `version` in `pubspec.yaml`, optionally add `media/release-notes/<tag>.md`, then run the workflow with the release tag. Signing material comes from the `release` environment secrets; APKs are verified against the pinned certificate before upload.

---

<a id="contributors"></a>
## Credits

### Team
* **Nilesh Suthar** — development
* **Karan Suthar** — design

### Thanks
* **[Vinyzu](https://github.com/Vinyzu)** for the dashboard playlists row, the playlist cover collages and the German translations
* **[YouTutosJeff](https://www.youtube.com/@YouTutosJeff)** for featuring Looper in [10 Mejores APLICACIONES Android 2026](https://youtu.be/KnoETY34sgk)
* Everyone who reports bugs, suggests features and shares Looper with friends

### Online streaming
* **[Koda](https://github.com/Ivorisnoob/Koda)** by Ivorisnoob: its documented InnerTube findings and failure history shaped Looper's stream resolver and cache. Looper's Dart implementation was written from those notes, not from Koda's Kotlin.
* **[yt-dlp](https://github.com/yt-dlp/yt-dlp)**: reference for client identities and stream resolution.
* **[Inzx](https://github.com/nirmaleeswar30/Inzx)**: reference for AutoEQ and several lyrics sources.
* **[microG](https://microg.org)** and **[ReVanced GmsCore](https://github.com/ReVanced/GmsCore)**: account sign-in on Android without Google Play Services.

### Lyrics Sources
Online lyrics come from these services and projects. Lyrics belong to their artists and rights holders and are fetched for personal display only.
* **[lrc.red](https://lrc.red)**: word-synced lyrics (the default provider)
* **[LyricsPlus](https://github.com/ibratabian17/lyricsplus)**: word-synced lyrics. It's an open-source server by ibratabian17 (Apache-2.0), hosted by binimum.
* **[AMLL](https://amll.dev)**, **[NetEase](https://music.163.com)**, **[KuGou](https://www.kugou.com)**, **[Musixmatch](https://www.musixmatch.com)** and **[Lyricify](https://lyricify.app)**: word-synced lyrics, asked after the two above.
* **[BetterLyrics](https://lyrics-api.boidu.dev)**, **[Unison](https://unison.boidu.dev)**, **[SimpMusic](https://simpmusic.org)**, **[Paxsenix](https://lyrics.paxsenix.org)**, **[BiniLyrics](https://lyrics-api.binimum.org)** and YouTube captions: further synced-lyrics sources.
* **[LRCLIB](https://lrclib.net)**: line-synced lyrics from a free, open database
* **[MusicBrainz](https://musicbrainz.org)**: finds each song's ISRC so lrc.red can match it (open music database, CC0 data)
* **[am-lyrics](https://github.com/binimum/am-lyrics)** by binimum (MPL-2.0): inspired Looper's word-synced lyrics support. No code was copied; Looper's Dart implementation was written from the lyrics formats.
* **[Morphe Patches](https://github.com/MorpheApp/morphe-patches)** (GPL-3.0): reference for the NetEase, KuGou, Musixmatch and Lyricify lookups and their lyrics formats.

---

## Support

Looper Music is free and open source. If you enjoy it, you can help by starring the repo, sharing it, or supporting us on Ko-fi:

<a href="https://ko-fi.com/L2L124TL7L">
  <img src="https://ko-fi.com/img/githubbutton_sm.svg" alt="Support Looper on Ko-fi" />
</a>

---

## License

LooperMusic is free and open-source software licensed under
the GNU General Public License v3.0 (GPL-3.0).

See [LICENSE](LICENSE) for details.

---

## Star History

<a href="https://www.star-history.com/?repos=devvlooper%2FLooperMusic&type=date&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=devvlooper/LooperMusic&type=date&theme=dark&legend=top-left" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=devvlooper/LooperMusic&type=date&legend=top-left" />
   <img alt="Star History Chart" src="https://api.star-history.com/chart?repos=devvlooper/LooperMusic&type=date&legend=top-left" />
 </picture>
</a>

---

<a id="contact"></a>
## Contact

Found a bug or want a feature? Open an [issue](https://github.com/devvlooper/LooperMusic/issues), or come say hi:

| | |
|---|---|
| Website | [looper-player.web.app](https://looper-player.web.app/) |
| Telegram | [t.me/looperPlayer](https://t.me/looperPlayer) |
| Discord | [discord.gg/9nFHhg94wn](https://discord.gg/9nFHhg94wn) |
| Google Play | [Looper Music](https://play.google.com/store/apps/details?id=com.looper.player) |
| Support us | [Ko-fi](https://ko-fi.com/L2L124TL7L) |

[![Telegram](https://img.shields.io/badge/Telegram-26A5E4?style=for-the-badge&logo=telegram&logoColor=white)](https://t.me/looperPlayer)
[![Discord](https://img.shields.io/badge/Discord-5865F2?style=for-the-badge&logo=discord&logoColor=white)](https://discord.gg/9nFHhg94wn)
