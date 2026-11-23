import 'dart:collection';
import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:looper_player/core/utils/motion.dart';
import 'package:looper_player/features/artwork/data/animated_artwork_service.dart';
import 'package:looper_player/features/artwork/domain/animated_artwork_models.dart';
import 'package:looper_player/features/artwork/presentation/widgets/animated_artwork_widget.dart';
import 'package:looper_player/features/library/domain/models/models.dart';
import 'package:looper_player/ui/android/shell/smooth_blur.dart';
import 'package:looper_player/ui/widgets/player/player_background_switcher.dart';

/// The song's art, blurred, filling its box. The blur is drawn once per song
/// and box size into a small image that every copy (main screen, music bar,
/// player) reuses. A live ImageFiltered re-blurred the whole screen on every
/// frame: Impeller has no raster cache, so RepaintBoundary didn't help.
class BlurredBackgroundArt extends ConsumerWidget {
  final Song song;

  /// Scale applied around the blurred art (the player zooms in slightly).
  final double zoom;

  /// Plays the song's motion art instead when Immersive Background is on.
  /// Off for the player, which shows motion in its top art instead.
  final bool motion;

  /// Blur strength in logical pixels of the box, saturation (0 = grey,
  /// 1 = unchanged) and edge mode of the baked image.
  final double sigma;
  final double saturation;
  final TileMode tileMode;

  /// Pixels per logical pixel of the baked image; null fits it to a
  /// 256 px long side. Pass the device pixel ratio to bake exactly what a
  /// live ImageFiltered would draw: shown 1:1, since upscaling a strongly
  /// blurred bake shows the blur's own low-res grid.
  final double? resolution;

  /// Zoom applied to the art before the blur, around [artAlignment] (the
  /// live version's Transform.scale under the ImageFiltered).
  final double artZoom;
  final Alignment artAlignment;

  /// Shows the theme gradient until the image is ready (else nothing).
  final bool placeholder;

  /// Fades to each new image instead of cutting (the now playing screen).
  final bool crossfade;
  const BlurredBackgroundArt({
    required this.song,
    this.zoom = 1.0,
    this.motion = true,
    this.sigma = _kSigma,
    this.saturation = 1.0,
    this.tileMode = TileMode.clamp,
    this.resolution,
    this.artZoom = 1.0,
    this.artAlignment = Alignment.center,
    this.placeholder = true,
    this.crossfade = false,
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = song.artPath;
    final Widget staticArt = (path != null && path.isNotEmpty)
        ? RepaintBoundary(
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (!constraints.hasBoundedWidth ||
                    !constraints.hasBoundedHeight ||
                    constraints.biggest.isEmpty) {
                  return const SizedBox.shrink();
                }
                final Widget art = _BlurredArtImage(
                  path: path,
                  size: constraints.biggest,
                  style: (
                    sigma,
                    saturation,
                    tileMode,
                    resolution,
                    artZoom,
                    artAlignment,
                  ),
                  placeholder: placeholder,
                  crossfade: crossfade,
                );
                return zoom == 1.0
                    ? art
                    : Transform.scale(scale: zoom, child: art);
              },
            ),
          )
        : const SizedBox.shrink();

    final motionSettings = ref.watch(animatedArtworkSettingsProvider);
    if (!motion ||
        !motionSettings.immersiveBackground ||
        motionSettings.mode == AnimatedArtworkMode.never) {
      return staticArt;
    }

    final motionAsync = ref.watch(animatedArtworkForSongProvider(song));
    final mediaSource =
        motionAsync.asData?.value?.bestTallMedia ??
        motionAsync.asData?.value?.bestSquareMedia;

    return AnimatedArtworkWidget(
      mediaSource: mediaSource,
      staticFallback: staticArt,
      fit: BoxFit.cover,
    );
  }
}

typedef _BlurStyle = (
  double sigma,
  double saturation,
  TileMode tileMode,
  double? resolution,
  double artZoom,
  Alignment artAlignment,
);

class _BlurredArtImage extends StatefulWidget {
  final String path;
  final Size size;
  final _BlurStyle style;
  final bool placeholder;
  final bool crossfade;
  const _BlurredArtImage({
    required this.path,
    required this.size,
    required this.style,
    required this.placeholder,
    required this.crossfade,
  });

  @override
  State<_BlurredArtImage> createState() => _BlurredArtImageState();
}

class _BlurredArtImageState extends State<_BlurredArtImage>
    with SingleTickerProviderStateMixin {
  ui.Image? _image;
  Object? _request;

  // Crossfade: _image fades in over _previous (or the placeholder). An image
  // arriving mid-fade waits in _pending, so a fast skip never jumps.
  ui.Image? _previous;
  ui.Image? _pending;
  bool _fading = false;
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: kPlayerBackgroundFade,
  )..addStatusListener(_onFadeStatus);
  late final Animation<double> _fadeCurve = CurvedAnimation(
    parent: _fade,
    curve: kPlayerBackgroundCurve,
  );
  bool _fadeCreated = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_BlurredArtImage old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path ||
        old.size != widget.size ||
        old.style != widget.style) {
      _load();
    }
  }

  // Keeps showing the previous image until the new one is ready.
  void _load() {
    final Future<ui.Image?> request = _blurredArt(
      widget.path,
      widget.size,
      widget.style,
    );
    _request = request;
    request.then((image) {
      if (mounted && identical(_request, request)) {
        _show(image);
      }
    });
  }

  void _show(ui.Image? image) {
    if (!widget.crossfade || image == null || Motion.reduced) {
      if (_fadeCreated) _fade.stop();
      setState(() {
        _image = image;
        _previous = _pending = null;
        _fading = false;
      });
      return;
    }
    if (_fading) {
      _pending = image;
      return;
    }
    if (identical(image, _image)) return;
    setState(() {
      _previous = _image;
      _image = image;
      _fading = true;
    });
    _fadeCreated = true;
    _fade.forward(from: 0);
  }

  void _onFadeStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || !mounted) return;
    final ui.Image? next = _pending;
    setState(() {
      _previous = _pending = null;
      _fading = false;
    });
    if (next != null) _show(next);
  }

  @override
  void dispose() {
    if (_fadeCreated) _fade.dispose();
    super.dispose();
  }

  Widget _raw(ui.Image image, [Animation<double>? opacity]) => RawImage(
    image: image,
    opacity: opacity,
    fit: BoxFit.fill,
    width: double.infinity,
    height: double.infinity,
    filterQuality: FilterQuality.low,
  );

  @override
  Widget build(BuildContext context) {
    final image = _image;
    if (image == null) return _placeholder(context);
    if (!_fading) return _raw(image);
    final previous = _previous;
    return Stack(
      fit: StackFit.expand,
      children: [
        previous != null ? _raw(previous) : _placeholder(context),
        _raw(image, _fadeCurve),
      ],
    );
  }

  Widget _placeholder(BuildContext context) {
    if (!widget.placeholder) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            theme.colorScheme.primary.withValues(alpha: 0.3),
            theme.colorScheme.surface,
          ],
        ),
      ),
    );
  }
}

const double _kSigma = 18; // blur strength, in logical pixels
const double _kLongSide = 256; // pixels on the cached image's long side
final LinkedHashMap<String, Future<ui.Image?>> _cache = LinkedHashMap();

/// Small LRU so the main screen, music bar and player share one render.
Future<ui.Image?> _blurredArt(String path, Size size, _BlurStyle style) {
  final (sigma, saturation, tileMode, resolution, artZoom, artAlignment) =
      style;
  final double k = resolution ?? _kLongSide / math.max(size.width, size.height);
  final int w = math.max(1, (size.width * k).round());
  final int h = math.max(1, (size.height * k).round());
  final String key = '$path|${w}x$h|$style';
  final Future<ui.Image?>? hit = _cache.remove(key);
  if (hit != null) return _cache[key] = hit;
  if (_cache.length >= 8) _cache.remove(_cache.keys.first);
  // A screen-sized bake is ~10 MB: keep only the latest one (a widget still
  // showing an older one holds its own reference).
  if (resolution != null) {
    final String? old = _screenSizedKey;
    if (old != null) _cache.remove(old);
    _screenSizedKey = key;
  }
  return _cache[key] = _render(
    path,
    w,
    h,
    sigma * k,
    saturation,
    tileMode,
    artZoom,
    artAlignment,
    keepAspect: resolution != null,
  );
}

String? _screenSizedKey;

/// How much smaller than the screen the software blur works.
const int _kSoftBlurScale = 8;

Future<Uint8List> _smoothBlurOffThread(
  Uint8List rgba,
  int width,
  int height,
  double sigma,
  int outWidth,
  int outHeight,
) => Isolate.run(
  () => smoothBlur(rgba, width, height, sigma, outWidth, outHeight),
);

// Saturation matrix: 0 = grey, 1 = unchanged.
List<double> _saturationMatrix(double v) {
  const r = 0.2126, g = 0.7152, b = 0.0722;
  final i = 1 - v;
  return [
    r * i + v, g * i, b * i, 0, 0, //
    r * i, g * i + v, b * i, 0, 0, //
    r * i, g * i, b * i + v, 0, 0, //
    0, 0, 0, 1, 0,
  ];
}

/// Same picture the old live blur drew: art squashed to 80x80, cover-fitted,
/// blurred with solid (clamped) edges - transparent edges let the screen
/// behind show through - at a size scaled down by the
/// blur-to-size ratio so it upscales without visible steps.
/// [keepAspect] decodes 64 px wide at the art's own aspect instead, like the
/// styled player's live blur (OptimizedImage cacheWidth: 64).
Future<ui.Image?> _render(
  String path,
  int w,
  int h,
  double sigma,
  double saturation,
  TileMode tileMode,
  double artZoom,
  Alignment artAlignment, {
  required bool keepAspect,
}) async {
  try {
    final Uint8List bytes;
    if (path.startsWith('http://') || path.startsWith('https://')) {
      final file = await DefaultCacheManager().getSingleFile(path);
      bytes = await file.readAsBytes();
    } else {
      bytes = await File(path).readAsBytes();
    }
    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: keepAspect ? 64 : 80,
      targetHeight: keepAspect ? null : 80,
    );
    final ui.Image src = (await codec.getNextFrame()).image;
    codec.dispose();
    final Rect rect = Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble());
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    // Screen-sized bakes blur in software: at these strengths the GPU blur
    // shows its low-res grid as fine lines. The art is drawn small for it.
    final int smallW = math.max(1, (w / _kSoftBlurScale).round());
    final int smallH = math.max(1, (h / _kSoftBlurScale).round());
    if (keepAspect) canvas.scale(smallW / w, smallH / h);
    final Paint layer = Paint();
    if (!keepAspect) {
      layer.imageFilter = ui.ImageFilter.blur(
        sigmaX: sigma,
        sigmaY: sigma,
        tileMode: tileMode,
      );
    }
    if (saturation != 1.0) {
      layer.colorFilter = ColorFilter.matrix(_saturationMatrix(saturation));
    }
    // Unbounded, so the blur also reads the zoomed art past the edges, as
    // the live ImageFiltered did before its ClipRect.
    canvas.saveLayer(null, layer);
    if (artZoom != 1.0) {
      final Offset o = artAlignment.alongSize(rect.size);
      canvas
        ..translate(o.dx, o.dy)
        ..scale(artZoom)
        ..translate(-o.dx, -o.dy);
    }
    paintImage(
      canvas: canvas,
      rect: rect,
      image: src,
      fit: BoxFit.cover,
      filterQuality: FilterQuality.low,
    );
    canvas.restore();
    final picture = recorder.endRecording();
    final ui.Image drawn = keepAspect
        ? await picture.toImage(smallW, smallH)
        : await picture.toImage(w, h);
    picture.dispose();
    src.dispose();
    if (!keepAspect) return drawn;
    final ByteData? small = await drawn.toByteData();
    drawn.dispose();
    if (small == null) return null;
    final Uint8List pixels = await _smoothBlurOffThread(
      small.buffer.asUint8List(small.offsetInBytes, small.lengthInBytes),
      smallW,
      smallH,
      sigma * smallW / w,
      w,
      h,
    );
    final done = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      pixels,
      w,
      h,
      ui.PixelFormat.rgba8888,
      done.complete,
    );
    return await done.future;
  } catch (_) {
    return null;
  }
}
