/// Which APK set this app updates from: `online` here, `offline` in the
/// offline Looper Player build. Must match the release asset names.
const apkEdition = 'online';

/// One APK attached to a GitHub release.
class ApkAsset {
  final String name;
  final String url;
  final int size;

  /// Lower-case hex SHA-256 as published by GitHub, or null for releases
  /// uploaded before GitHub started recording asset digests.
  final String? sha256;

  const ApkAsset({
    required this.name,
    required this.url,
    required this.size,
    this.sha256,
  });
}

/// The parts of a GitHub `releases/latest` response the updater uses.
class GithubRelease {
  final String tag;
  final String name;
  final String htmlUrl;
  final String notes;
  final String? publishedAt;
  final List<ApkAsset> apks;

  const GithubRelease({
    required this.tag,
    this.name = '',
    required this.htmlUrl,
    required this.notes,
    this.publishedAt,
    required this.apks,
  });

  factory GithubRelease.fromJson(
    Map<String, dynamic> json, {
    required String fallbackHtmlUrl,
  }) {
    final apks = <ApkAsset>[];
    for (final asset in (json['assets'] as List?) ?? const []) {
      if (asset is! Map) continue;
      final name = asset['name'];
      final url = asset['browser_download_url'];
      final size = asset['size'];
      if (name is! String || url is! String || size is! int) continue;
      if (!name.toLowerCase().endsWith('.apk')) continue;
      final digest = asset['digest'];
      apks.add(
        ApkAsset(
          name: name,
          url: url,
          size: size,
          sha256: digest is String && digest.startsWith('sha256:')
              ? digest.substring(7).toLowerCase()
              : null,
        ),
      );
    }
    return GithubRelease(
      tag: (json['tag_name'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      htmlUrl: (json['html_url'] as String?) ?? fallbackHtmlUrl,
      notes: ((json['body'] as String?) ?? '').trim(),
      publishedAt: json['published_at'] as String?,
      apks: apks,
    );
  }

  /// A build uploaded by hand to the repo's `media/<edition>/` folder, from a
  /// GitHub `contents` listing. The version comes from the APK names
  /// (`looper-player-v3.0.1-arm64-v8a-online-release.apk`); tag is empty
  /// when the folder holds no versioned APK.
  factory GithubRelease.fromContents(
    List<dynamic> json, {
    required String htmlUrl,
  }) {
    final apks = <ApkAsset>[];
    var tag = '';
    for (final file in json) {
      if (file is! Map || file['type'] != 'file') continue;
      final name = file['name'];
      final url = file['download_url'];
      final size = file['size'];
      if (name is! String || url is! String || size is! int) continue;
      if (!name.toLowerCase().endsWith('.apk')) continue;
      final version = RegExp(r'-v(\d+(?:\.\d+)+)-').firstMatch(name)?.group(1);
      if (version == null) continue;
      // Stale APKs left beside the new ones: keep only the newest version.
      if (tag.isNotEmpty && isNewerVersion(version, tag)) continue;
      if (tag.isEmpty || isNewerVersion(tag, version)) apks.clear();
      tag = version;
      apks.add(ApkAsset(name: name, url: url, size: size));
    }
    return GithubRelease(tag: tag, htmlUrl: htmlUrl, notes: '', apks: apks);
  }

  /// The APK to install on a device whose ABIs are [abis], most preferred
  /// first (Android's `Build.SUPPORTED_ABIS`): the first per-ABI split that
  /// matches, else the universal APK, else null.
  ///
  /// Releases carry both editions (`...-arm64-v8a-online-release.apk` and
  /// `...-offline-release.apk`); only [apkEdition]'s APKs are considered.
  /// A release with no labelled APKs (before the split) uses its unlabelled ones.
  static bool _labelled(ApkAsset a, String edition) =>
      a.name.toLowerCase().contains('-$edition-');

  /// The release carries the other edition's APKs but not ours yet: the
  /// online APKs are uploaded by hand after the release workflow finishes.
  bool get waitingForMyApk =>
      apks.any((a) => _labelled(a, 'online') || _labelled(a, 'offline')) &&
      !apks.any((a) => _labelled(a, apkEdition));

  ApkAsset? apkFor(List<String> abis) {
    const labelled = _labelled;
    final mine = apks.where((a) => labelled(a, apkEdition)).toList();
    final pool = mine.isNotEmpty
        ? mine
        : apks
              .where((a) => !labelled(a, 'online') && !labelled(a, 'offline'))
              .toList();
    for (final abi in abis) {
      final marker = '-${abi.toLowerCase()}-';
      for (final apk in pool) {
        if (apk.name.toLowerCase().contains(marker)) return apk;
      }
    }
    for (final apk in pool) {
      if (apk.name.toLowerCase().contains('universal')) return apk;
    }
    return null;
  }
}

/// Whether version [latest] (a release tag such as `2.6` or `v2.7.1-rc.1`) is
/// newer than [current]. Compares the dotted numbers only; missing parts
/// count as zero, so `2.6` equals `2.6.0`.
bool isNewerVersion(String current, String latest) {
  List<int> parts(String version) {
    // Start at the first number ('release-2.0.0' -> '2.0.0'), then drop build
    // metadata and pre-release identifiers.
    final match = RegExp(r'^\D*(\d+\..*)').firstMatch(version);
    var clean = match != null ? match.group(1)! : version;
    clean = clean.split('+')[0].split('-')[0];
    clean = clean.replaceAll(RegExp(r'[^0-9.]'), '');
    return clean.split('.').map((e) => int.tryParse(e) ?? 0).toList();
  }

  final currentParts = parts(current);
  final latestParts = parts(latest);
  final length = currentParts.length > latestParts.length
      ? currentParts.length
      : latestParts.length;
  for (int i = 0; i < length; i++) {
    final c = i < currentParts.length ? currentParts[i] : 0;
    final l = i < latestParts.length ? latestParts[i] : 0;
    if (l > c) return true;
    if (l < c) return false;
  }
  return false;
}
