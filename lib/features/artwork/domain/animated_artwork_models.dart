import 'package:looper_player/features/settings/domain/app_defaults.dart';

enum AnimatedArtworkMode {
  always,
  wifiOnly,
  never;

  String get label {
    switch (this) {
      case AnimatedArtworkMode.always:
        return 'Always';
      case AnimatedArtworkMode.wifiOnly:
        return 'Wi-Fi only';
      case AnimatedArtworkMode.never:
        return 'Never';
    }
  }
}

/// Where moving artwork comes from.
enum AnimatedArtworkSource {
  /// Apple Music motion covers.
  apple,

  /// The song's own YouTube Music video, for online songs.
  youtube,

  /// Apple's motion cover when there is one, else the YouTube video (the
  /// default).
  appleThenYoutube;

  bool get usesApple => this != youtube;
  bool get usesYoutube => this != apple;
}

class AnimatedArtworkSettings {
  final AnimatedArtworkMode mode;
  final AnimatedArtworkSource source;
  final bool immersiveBackground;
  final bool animateAlbumCover;
  final Map<String, bool> animateAlbumCoverByStyle;
  final bool ambientGlow;
  final int cacheLimitMB;

  const AnimatedArtworkSettings({
    this.mode = AnimatedArtworkMode.always,
    this.source = AnimatedArtworkSource.appleThenYoutube,
    this.immersiveBackground = AppDefaults.animatedArtworkImmersiveBackground,
    this.animateAlbumCover = AppDefaults.animatedArtworkAnimateAlbumCover,
    this.animateAlbumCoverByStyle = const {},
    this.ambientGlow = AppDefaults.animatedArtworkAmbientGlow,
    this.cacheLimitMB = AppDefaults.animatedArtworkCacheLimitMB,
  });

  static String normalizeStyle(String? style) => switch (style) {
    'arc' => 'arc',
    'linear' => 'linear',
    'card' || 'box' => 'card',
    _ => 'classic',
  };

  bool isAlbumCoverAnimated(String? style) {
    final key = normalizeStyle(style);
    return animateAlbumCoverByStyle[key] ?? animateAlbumCover;
  }

  AnimatedArtworkSettings withAlbumCoverForStyle(String? style, bool enabled) {
    final key = normalizeStyle(style);
    final updated = Map<String, bool>.from(animateAlbumCoverByStyle);
    updated[key] = enabled;
    return copyWith(
      animateAlbumCoverByStyle: updated,
      animateAlbumCover: key == 'classic' ? enabled : animateAlbumCover,
    );
  }

  AnimatedArtworkSettings copyWith({
    AnimatedArtworkMode? mode,
    AnimatedArtworkSource? source,
    bool? immersiveBackground,
    bool? animateAlbumCover,
    Map<String, bool>? animateAlbumCoverByStyle,
    bool? ambientGlow,
    int? cacheLimitMB,
  }) {
    return AnimatedArtworkSettings(
      mode: mode ?? this.mode,
      source: source ?? this.source,
      immersiveBackground: immersiveBackground ?? this.immersiveBackground,
      animateAlbumCover: animateAlbumCover ?? this.animateAlbumCover,
      animateAlbumCoverByStyle:
          animateAlbumCoverByStyle ?? this.animateAlbumCoverByStyle,
      ambientGlow: ambientGlow ?? this.ambientGlow,
      cacheLimitMB: cacheLimitMB ?? this.cacheLimitMB,
    );
  }

  Map<String, dynamic> toJson() => {
    'mode': mode.name,
    'source': source.name,
    'immersiveBackground': immersiveBackground,
    'animateAlbumCover': animateAlbumCover,
    'animateAlbumCoverByStyle': animateAlbumCoverByStyle,
    'ambientGlow': ambientGlow,
    'cacheLimitMB': cacheLimitMB,
  };

  factory AnimatedArtworkSettings.fromJson(Map<String, dynamic> json) {
    final byStyleRaw = json['animateAlbumCoverByStyle'];
    final Map<String, bool> byStyle;
    if (byStyleRaw is Map) {
      byStyle = byStyleRaw.map((k, v) => MapEntry(k.toString(), v == true));
    } else {
      byStyle = const {};
    }

    return AnimatedArtworkSettings(
      mode: AnimatedArtworkMode.values.firstWhere(
        (m) => m.name == json['mode'],
        orElse: () => AnimatedArtworkMode.never,
      ),
      source: AnimatedArtworkSource.values.firstWhere(
        (s) => s.name == json['source'],
        orElse: () => AnimatedArtworkSource.apple,
      ),
      immersiveBackground:
          json['immersiveBackground'] as bool? ??
          AppDefaults.animatedArtworkImmersiveBackground,
      animateAlbumCover:
          json['animateAlbumCover'] as bool? ??
          AppDefaults.animatedArtworkAnimateAlbumCover,
      animateAlbumCoverByStyle: byStyle,
      ambientGlow: json['ambientGlow'] as bool? ?? false,
      cacheLimitMB: json['cacheLimitMB'] as int? ?? 300,
    );
  }
}

class AnimatedArtwork {
  final String key;
  final String? artist;
  final String? album;
  final String? urlSquare;
  final String? urlTall;
  final String? localPathSquare;
  final String? localPathTall;
  final int fetchedAt;
  final bool hasMotion;
  // Artist banner only (doc 26 §3.2).
  final String? urlWide;
  final String? stillUrl;
  final String? logoUrl;
  final double? logoAspect;

  const AnimatedArtwork({
    required this.key,
    this.artist,
    this.album,
    this.urlSquare,
    this.urlTall,
    this.localPathSquare,
    this.localPathTall,
    required this.fetchedAt,
    required this.hasMotion,
    this.urlWide,
    this.stillUrl,
    this.logoUrl,
    this.logoAspect,
  });

  bool get isExpired {
    // Songs/albums: hit 90 days, miss 30 days. Artists: hit 24 h, miss 10 min.
    final ttl = key.startsWith('artist:')
        ? (hasMotion ? const Duration(hours: 24) : const Duration(minutes: 10))
        : Duration(days: hasMotion ? 90 : 30);
    return DateTime.now().millisecondsSinceEpoch >
        fetchedAt + ttl.inMilliseconds;
  }

  /// Artist header: wide video, else tall, else square.
  String? get bestWideMedia => urlWide ?? bestTallMedia;

  String? get bestSquareMedia =>
      (localPathSquare != null && localPathSquare!.isNotEmpty)
      ? localPathSquare
      : urlSquare;

  String? get bestTallMedia =>
      (localPathTall != null && localPathTall!.isNotEmpty)
      ? localPathTall
      : (urlTall ?? bestSquareMedia);

  AnimatedArtwork copyWith({
    String? key,
    String? artist,
    String? album,
    String? urlSquare,
    String? urlTall,
    String? localPathSquare,
    String? localPathTall,
    int? fetchedAt,
    bool? hasMotion,
  }) {
    return AnimatedArtwork(
      key: key ?? this.key,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      urlSquare: urlSquare ?? this.urlSquare,
      urlTall: urlTall ?? this.urlTall,
      localPathSquare: localPathSquare ?? this.localPathSquare,
      localPathTall: localPathTall ?? this.localPathTall,
      fetchedAt: fetchedAt ?? this.fetchedAt,
      hasMotion: hasMotion ?? this.hasMotion,
      urlWide: urlWide,
      stillUrl: stillUrl,
      logoUrl: logoUrl,
      logoAspect: logoAspect,
    );
  }

  Map<String, dynamic> toJson() => {
    'key': key,
    'artist': artist,
    'album': album,
    'urlSquare': urlSquare,
    'urlTall': urlTall,
    'localPathSquare': localPathSquare,
    'localPathTall': localPathTall,
    'fetchedAt': fetchedAt,
    'hasMotion': hasMotion,
    if (urlWide != null) 'urlWide': urlWide,
    if (stillUrl != null) 'stillUrl': stillUrl,
    if (logoUrl != null) 'logoUrl': logoUrl,
    if (logoAspect != null) 'logoAspect': logoAspect,
  };

  factory AnimatedArtwork.fromJson(Map<String, dynamic> json) {
    return AnimatedArtwork(
      key: json['key'] as String? ?? '',
      artist: json['artist'] as String?,
      album: json['album'] as String?,
      urlSquare: json['urlSquare'] as String?,
      urlTall: json['urlTall'] as String?,
      localPathSquare: json['localPathSquare'] as String?,
      localPathTall: json['localPathTall'] as String?,
      fetchedAt: json['fetchedAt'] as int? ?? 0,
      hasMotion: json['hasMotion'] as bool? ?? false,
      urlWide: json['urlWide'] as String?,
      stillUrl: json['stillUrl'] as String?,
      logoUrl: json['logoUrl'] as String?,
      logoAspect: (json['logoAspect'] as num?)?.toDouble(),
    );
  }

  /// Reads an artist's `attributes` (doc 26 §3.2 table). Null unless there
  /// is a motion video or a name logo.
  static AnimatedArtwork? fromArtistEditorial(
    Map attrs, {
    required String key,
    String? artist,
    int? fetchedAt,
  }) {
    Map? pick(Map? m, List<String> keys) {
      for (final k in keys) {
        final v = m?[k];
        if (v is Map) return v;
      }
      return null;
    }

    // mzstatic template at its own size; png keeps logo transparency.
    String? fill(Map? img) {
      final t = img?['url']?.toString();
      if (t == null || t.isEmpty) return null;
      return t
          .replaceAll('{w}', '${(img!['width'] as num?)?.round() ?? 1080}')
          .replaceAll('{h}', '${(img['height'] as num?)?.round() ?? 1080}')
          .replaceAll('{c}', '')
          .replaceAll('{f}', 'png');
    }

    final ev = attrs['editorialVideo'] as Map?;
    final ea = attrs['editorialArtwork'] as Map?;
    final wide = pick(ev, const [
      'motionArtistWide16x9',
      'motionArtistFullscreen16x9',
      'motionDetailRaw',
    ]);
    final square = pick(ev, const [
      'motionArtistSquare1x1',
      'motionDetailSquare',
      'motionSquareVideo1x1',
    ]);
    final wideUrl = wide?['video']?.toString();
    final squareUrl = square?['video']?.toString();

    final logo = pick(ea, const [
      'musicContentColorLogoTrimmed',
      'musicContentLogoTrimmed',
    ]);
    final lw = (logo?['width'] as num?)?.toDouble();
    final lh = (logo?['height'] as num?)?.toDouble();
    final logoAspect = (lw != null && lh != null && lh > 0) ? lw / lh : null;
    final logoUrl = fill(logo);

    if (wideUrl == null && squareUrl == null && logoUrl == null) return null;

    // Square frame first: a phone banner is taller than wide, so it crops less.
    final frame =
        (square?['previewFrame'] as Map?) ?? (wide?['previewFrame'] as Map?);
    final banner = pick(ea, const [
      'bannerUber',
      'storeFlowcase',
      'subscriptionHero',
      'originalFlowcaseBrick',
    ]);

    return AnimatedArtwork(
      key: key,
      artist: artist,
      urlSquare: squareUrl,
      urlWide: wideUrl,
      stillUrl: fill(frame) ?? fill(banner),
      logoUrl: logoUrl,
      logoAspect: logoAspect,
      fetchedAt: fetchedAt ?? DateTime.now().millisecondsSinceEpoch,
      hasMotion: true,
    );
  }
}
