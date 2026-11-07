# AGENT HANDOFF - Looper Music Online & Account Integration

## 1. Project Overview & Current State
Looper Music is a Flutter/Riverpod/Isar music player with offline playback and online streaming via InnerTube (YouTube Music).
Task takeover from Claude Code after weekly limit exhaustion, continuing the implementation of real account data fetching, mood-based selections, home shelf relevance ordering, row expansion to 15 items with "View all" navigation, two distinct artist rows (offline vs online), paginated view all screens following core design style, and YouTube lyrics provider.

### Git & Codebase Status Summary
- **Branch**: `main`
- **Flutter Analyze**: `No issues found!` (0 errors, 0 warnings across the entire app).
- **Tests**: All tests passing (`test/account_feed_and_mood_test.dart`, `test/home_layout_test.dart`, `test/online_hardening_test.dart`, `test/lyrics_services_sheet_test.dart`, `test/online_lyrics_and_downloads_test.dart`, `test/microg_auth_test.dart`, `test/online_parsers_test.dart`).
- **Graphify**: Updated AST graph current (`9937 nodes, 16873 edges, 327 communities`).

## 2. Completed Implementations

### A. Fixed Compile Issue & Added Mood Selections
- **Fix in `online_providers.dart`**: Fixed type error where `OnlineApi.home()` returns `(List<OnlineShelf>, List<OnlineMood>)`.
- **`OnlineMood` Class**: Added JSON serialization (`toJson`, `fromJson`), equality, and hash code in [`lib/features/online/data/parsers.dart`](file:///home/hiteshsuthar/projects/looper_music/lib/features/online/data/parsers.dart).
- **`OnlineHomeState` & `OnlineHomeNotifier`**:
  - Added `moods` and `activeMood` state tracking.
  - Added `selectMood(OnlineMood? mood)`: Tapping an active mood toggles it off; tapping an inactive mood fetches mood-specific shelves via `OnlineApi.home(params: mood.params)`.
  - Disk-cached moods so mood chips appear immediately on app launch.
- **Mood Chips Bar & Visual Refreshing Indicator**: Implemented in [`lib/features/online/presentation/online_widgets.dart`](file:///home/hiteshsuthar/projects/looper_music/lib/features/online/presentation/online_widgets.dart):
  - Shows an inline crisp circular loading indicator on the active mood chip when refreshing.
  - Renders a sleek `LinearProgressIndicator` directly beneath the chips row when refreshing shelves.

### B. Home Shelves Relevance Ordering & Layout Positioning
- Implemented `_shelfRelevanceRank` in [`lib/features/online/presentation/online_providers.dart`](file:///home/hiteshsuthar/projects/looper_music/lib/features/online/presentation/online_providers.dart) enforcing user-specified priority:
  1. **Speed dial** (rank 0 - personalized instant access)
  2. **For you / Discover / Quick picks / Listen again** (rank 1)
  3. **Trending songs for you** (rank 2)
  4. **Active mood shelves** (rank 3 - when a mood is selected)
  5. **Mixes / My Supermix** (rank 4)
  6. **Forgotten favourites** (rank 5)
  7. **Trending community playlists** (rank 6)
  8. **Albums for you** (rank 7)
  9. **Broader / remaining shelves** (rank 8)
- In [`OnlineHomeSliver`](file:///home/hiteshsuthar/projects/looper_music/lib/features/online/presentation/online_widgets.dart), `_ArtistsForYouRow` is positioned **between online shelves** (after the first 2 shelves, not at the top), seamlessly separating top recommendations from extended shelves.

### C. Two Artist Rows & Paginated View All
- **Two Distinct Artist Rows on Home**:
  - **Offline Library Artists**: Located in [`android_home_tab.dart`](file:///home/hiteshsuthar/projects/looper_music/lib/ui/android/tabs/home/android_home_tab.dart), displays 15 items, and clicking "View all" opens the offline library artists tab (`NavItem.artists`).
  - **Online "Artists for you"**: Located in [`online_widgets.dart`](file:///home/hiteshsuthar/projects/looper_music/lib/features/online/presentation/online_widgets.dart), displays up to 20 artists, sits between online shelves, and clicking "View all" (header button or end card) opens `OnlineViewAllScreen`.
- **`OnlineViewAllScreen`** ([`lib/features/online/presentation/online_view_all_screen.dart`](file:///home/hiteshsuthar/projects/looper_music/lib/features/online/presentation/online_view_all_screen.dart)):
  - Built using core design style with `CollectionPinnedBar` (blurred header, back button, title, and action buttons).
  - Supports infinite scrolling with continuation tokens via `OnlineApi.listPage`.
  - Shows bottom loading indicator (`CircularProgressIndicator`) as more items load.
  - Supports adaptive circular artist grid (for artist lists) and responsive card/song lists.
  - Resolves online library artists (`FEmusic_library_corpus_artists`) when authenticated.
- **Shelf "View all" Fix**: `_openShelfViewAll` now routes to `OnlineViewAllScreen` with `moreBrowseId` and `moreParams` rather than mistakenly treating section endpoints as collection/playlists.

### D. Real Account Data Fetching & Suggestion Base
- **`AccountDataSync`** ([`lib/features/online/data/account_data_sync.dart`](file:///home/hiteshsuthar/projects/looper_music/lib/features/online/data/account_data_sync.dart)):
  - Fetches user's subscribed artists (`FEmusic_library_corpus_artists`).
  - Fetches user's playlists (`FEmusic_liked_playlists`).
  - Fetches user's saved albums (`FEmusic_liked_albums`).
  - Caches account collections via `LocalJsonStore`.
  - Automatically merges account subscribed artists into `TasteNotifier` and invalidates `TasteProfileStore` so suggestions and recommendations adapt to the real Google/YouTube Music account.
- **`TasteNotifier.mergeAccountTaste`** ([`lib/features/online/data/taste_store.dart`](file:///home/hiteshsuthar/projects/looper_music/lib/features/online/data/taste_store.dart)):
  - Integrates subscribed artists, marks `seen: true` to bypass generic taste setup, and triggers personalized suggestions.
- **Authentication Hooks** ([`lib/features/microg/presentation/providers/auth_provider.dart`](file:///home/hiteshsuthar/projects/looper_music/lib/features/microg/presentation/providers/auth_provider.dart)):
  - Triggers `AccountDataSync.sync` on sign-in and clears account caches on `signOut()`.
- **Search Suggestions**:
  - `onlineSuggestionsProvider` in `online_providers.dart` queries `OnlineApi.suggestions(query)` (`music/get_search_suggestions`), returning personalized account search history and cloud completions.

### E. YouTube Lyrics Provider & Documentation
- `YtMusicLyricsClient` ([`lib/features/playback/data/lyrics_providers/ytmusic_client.dart`](file:///home/hiteshsuthar/projects/looper_music/lib/features/playback/data/lyrics_providers/ytmusic_client.dart)) is wired into [`LyricsProviderInfo`](file:///home/hiteshsuthar/projects/looper_music/lib/features/playback/data/lyrics_providers/lyrics_provider_info.dart) (`id: 'YTMUSIC'`), [`LyricsService`](file:///home/hiteshsuthar/projects/looper_music/lib/features/playback/data/lyrics_service.dart), and [`LyricsFetcher`](file:///home/hiteshsuthar/projects/looper_music/lib/features/playback/data/lyrics_fetcher.dart).
- Added comprehensive documentation in [`docs/online/microg/16-unified-library-and-activity.md`](file:///home/hiteshsuthar/projects/looper_music/docs/online/microg/16-unified-library-and-activity.md) detailing unified library mode (online + offline activities synced) vs pure offline zero-cloud privacy mode.
- Expanded row layouts to 15 items + "View all" end cards across playlists, artists, albums, and genres.

### F. Implemented Unified Library & Activity Synchronization (16-unified-library-and-activity.md)
- **Account Data Fetching & Caching (`AccountDataSync`)**:
  - Expanded sync pipeline to fetch all 5 cloud sections:
    1. Subscribed artists (`FEmusic_library_corpus_artists`)
    2. Playlists (`FEmusic_liked_playlists`)
    3. Saved albums (`FEmusic_liked_albums`)
    4. Liked Music / Favorites (`FEmusic_liked_videos` / `LM`)
    5. History (`FEmusic_history`)
  - Stored each under dedicated cache keys in `LocalJsonStore` (`online_account_playlists_v1`, `online_account_artists_v1`, `online_account_albums_v1`, `online_account_favorites_v1`, `online_account_history_v1`).
  - Added reactive Riverpod providers: `isOnlineConnectedProvider`, `onlineAccountPlaylistsProvider`, `onlineAccountArtistsProvider`, `onlineAccountAlbumsProvider`, `onlineAccountFavoritesProvider`, `onlineAccountHistoryProvider`.
- **Playlists Screen (`PlaylistView`)**:
  - Added `All`, `On Device`, and `YouTube Music` filter chips when online playlists exist.
  - Displays local playlists alongside cloud YouTube Music playlists (`_OnlinePlaylistCard`) with cloud sync badges.
  - Tapping cloud playlists opens `OnlineCollectionScreen`.
- **Favorites Screen (`FavoritesView`)**:
  - `PagedSongsNotifier(PagedQueryKind.favorites)` merges online Liked Music (`OnlineSong.toSong()..isFavorite = true`) with local favorites in unified mode.
  - Offline mode returns strictly on-device `isFavoriteEqualTo(true)` songs.
- **History & Recently Played (`RecentlyPlayedView` & `AndroidLibraryTab`)**:
  - `PagedSongsNotifier(PagedQueryKind.history)` merges cross-device YouTube Music history tracks with local play history.
  - `AndroidLibraryTab._buildRecentlyAccessed` falls back to online account history when local history is empty, populating the Library tab immediately on login.
- **Artists Category Grid (`ArtistsGridView`)**:
  - Unifies local artists with subscribed YouTube Music artists (deduplicated by name).
  - Filter chips: `All`, `On Device`, `YouTube Music`.
  - Tapping online artists opens `OnlineCollectionScreen` with their catalog.
- **Albums Category Grid (`AlbumsGridView`)**:
  - Unifies local albums with saved YouTube Music albums.
  - Filter chips: `All`, `On Device`, `YouTube Music`.
  - Tapping online albums opens `OnlineCollectionScreen`.
- **Looper Analyze (`LooperAnalyzeView` & `analyzeSnapshotProvider`)**:
  - Synthesizes online history, favorites, and subscribed artists into `AnalyzeSnapshot.compute` so users without local files still get a rich listening report card.
- **Zero Cloud Leakage Invariant**:
  - When online mode is disabled or the user signs out, `isOnlineConnectedProvider` immediately evaluates to `false`, instantly clearing all online entities from the library in 0ms without database mutations.

### G. Artist Following & Continuous Recommendation Pipeline
- **Prominent Follow/Following Buttons on All Artist Screens**:
  - **`CollectionDetailView` (`collection_header.dart` & `desktop_collection.dart`)**: Local and library artist pages now feature a styled `_ArtistFollowButton` directly in the collection header next to Play, Shuffle, and Sort.
  - **`OnlineCollectionScreen` (`online_collection_screen.dart`)**: Upgraded `_FollowButton` with Material 3 `FilledButton.tonalIcon` when following and `OutlinedButton.icon` with plus icon when not following.
  - **Explore Online Shortcut**: Added `_exploreArtistOnline` action (globe icon) in the header and an `_ExploreOnlineArtistCard` at the bottom of local artist songs in `CollectionDetailView`, allowing users to jump directly to the artist's full online catalog on YouTube Music with all albums and top tracks.
- **Immediate Recommendation Adaptation**:
  - `TasteNotifier.toggleArtist` prepends the newly followed artist to the front of `taste.artists`, invalidates `TasteProfileStore`, and deletes `online_artists_for_you_v1` disk cache.
  - `OnlineHomeNotifier.build()` listens reactively to `tasteProvider` and immediately re-evaluates `load(force: true)` when taste changes, fetching new songs and latest releases from the followed artist.
  - `RecommendationEngine.forYou` and `discover` expanded to query up to 5 top artists (guaranteeing the newly followed artist at index 0 is queried for `$artist songs` and `$artist latest songs`).
  - `onlineArtistsForYouProvider` checks cache validity against active followed artists and bypasses stale cache when new artists are followed.

### H. Apple Music Animated Artwork Support Implementation
- Fully implemented Apple Music Motion Artworks per [`docs/online/20-apple-music-animated-artworks.md`](file:///home/hiteshsuthar/projects/looper_music/docs/online/20-apple-music-animated-artworks.md):
  - **Domain & Service**:
    - Created [`lib/features/artwork/domain/animated_artwork_models.dart`](file:///home/hiteshsuthar/projects/looper_music/lib/features/artwork/domain/animated_artwork_models.dart) with `AnimatedArtwork`, `AnimatedArtworkSettings`, and `AnimatedArtworkMode` (`always`, `wifiOnly`, `never`).
    - Created [`lib/features/artwork/data/animated_artwork_service.dart`](file:///home/hiteshsuthar/projects/looper_music/lib/features/artwork/data/animated_artwork_service.dart):
      - Direct Apple Music storefront scraper & iTunes catalog resolver (`itunes.apple.com/search` -> `music.apple.com` embedded JSON parser for `videoArtwork` & `tallVideoArtwork`).
      - Self-hosted `m8tec/apple-music-animated-artworks` REST API client support (`/api/v1/artwork/search`).
      - Two-tier cache architecture: `LocalJsonStore` metadata index with 30-day negative caching, and disk media cache (`<cacheDir>/animated_artwork/`) with automatic LRU eviction based on user-configured limits.
      - Seamless master `.m3u8` variant parser extracting single-file continuous `.mp4` loop containers for offline caching and battery savings.
      - Network policy gating using native `isNetworkMetered()`.
  - **Rendering Pipeline (`AnimatedArtworkWidget`)**:
    - Implemented [`lib/features/artwork/presentation/widgets/animated_artwork_widget.dart`](file:///home/hiteshsuthar/projects/looper_music/lib/features/artwork/presentation/widgets/animated_artwork_widget.dart) using `video_player`:
      - Audio strictly disabled (`setVolume(0.0)`).
      - Seamless hardware looping (`setLooping(true)`).
      - Lifecycle and visibility management: auto-pauses when app is backgrounded or inactive.
      - First-frame crossfade: static cover displays instantaneously, smoothly crossfading to motion loop when first frame is rendered.
  - **Surface Integrations**:
    - **Expanded Player (`ForegroundAlbumArt`)**: Now Playing card seamlessly plays the motion artwork loop.
    - **Immersive Backdrop (`BlurredBackgroundArt`)**: Full-bleed ambient motion backdrop behind lyrics and controls when enabled.
    - **Collection Detail (`CollectionHeader` & `OnlineCollectionScreen`)**: Displays motion artwork in the header for albums, playlists, and artists.
    - **Mini Player (`MiniPlayerContent`)**: Micro animated artwork in bottom navigation bar.
    - **Manual Link Option**: "Link animated artwork" in playlist options sheet.
    - **Settings**: Dedicated "Animated artworks" section in Settings > Online music (Mode selector, immersive background toggle, custom server URL, cache limit slider, cache clear button).
  - **Unit Tests**:
    - Created [`test/animated_artwork_test.dart`](file:///home/hiteshsuthar/projects/looper_music/test/animated_artwork_test.dart) verifying settings serialization, metadata roundtrip, TTL expiration, and best media resolution.

### I. Inzx Architecture & Feature Study Documentation
- Produced comprehensive architectural and implementation study in [`docs/online/21-inzx-features-and-architecture.md`](file:///home/hiteshsuthar/projects/looper_music/docs/online/21-inzx-features-and-architecture.md).
- Analyzed [`nirmaleeswar30/Inzx`](https://github.com/nirmaleeswar30/Inzx) (Flutter YouTube Music client) covering:
  - Real-time collaborative Jam sessions via Supabase Realtime with clock drift compensation.
  - Multi-source audio streaming with JioSaavn 320 kbps fallback and lossless FLAC matching.
  - Word/syllable-level synced lyrics with AI translation and transliteration/romanization.
  - AutoEQ headphone calibration presets mapped to mpv parametric equalizer filters.
  - Dynamic visualizer player themes (Cinematic, Ripple, Canvas).
  - Last.fm and ListenBrainz scrobbling integration.

## 3. Verification & Checks
- All unit and integration tests passing:
  - `test/account_feed_and_mood_test.dart` (6 tests)
  - `test/home_layout_test.dart` (4 tests)
  - `test/online_hardening_test.dart` (19 tests)
  - `test/lyrics_services_sheet_test.dart` (3 tests)
  - `test/online_lyrics_and_downloads_test.dart` (37 tests)
  - `test/microg_auth_test.dart` (6 tests)
  - `test/online_parsers_test.dart` (10 tests)
- Flutter analyze reports 0 issues across the entire project (`No issues found!`).
