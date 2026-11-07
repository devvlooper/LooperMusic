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

class AnimatedArtworkSettings {
  final AnimatedArtworkMode mode;
  final bool immersiveBackground;
  final int cacheLimitMB;

  const AnimatedArtworkSettings({
    this.mode = AnimatedArtworkMode.wifiOnly,
    this.immersiveBackground = false,
    this.cacheLimitMB = 300,
  });

  AnimatedArtworkSettings copyWith({
    AnimatedArtworkMode? mode,
    bool? immersiveBackground,
    int? cacheLimitMB,
  }) {
    return AnimatedArtworkSettings(
      mode: mode ?? this.mode,
      immersiveBackground: immersiveBackground ?? this.immersiveBackground,
      cacheLimitMB: cacheLimitMB ?? this.cacheLimitMB,
    );
  }

  Map<String, dynamic> toJson() => {
        'mode': mode.name,
        'immersiveBackground': immersiveBackground,
        'cacheLimitMB': cacheLimitMB,
      };

  factory AnimatedArtworkSettings.fromJson(Map<String, dynamic> json) {
    return AnimatedArtworkSettings(
      mode: AnimatedArtworkMode.values.firstWhere(
        (m) => m.name == json['mode'],
        orElse: () => AnimatedArtworkMode.wifiOnly,
      ),
      immersiveBackground: json['immersiveBackground'] as bool? ?? false,
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
  });

  bool get isExpired {
    // Negative cache expires after 30 days. Positive cache lasts 90 days.
    final ttlDays = hasMotion ? 90 : 30;
    final expiresAt = fetchedAt + (ttlDays * 24 * 60 * 60 * 1000);
    return DateTime.now().millisecondsSinceEpoch > expiresAt;
  }

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
    );
  }
}
