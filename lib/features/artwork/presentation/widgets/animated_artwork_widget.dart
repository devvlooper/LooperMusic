import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:looper_player/features/artwork/data/animated_artwork_service.dart';
import 'package:looper_player/features/artwork/data/youtube_video_artwork.dart';
import 'package:looper_player/features/artwork/domain/animated_artwork_models.dart';
import 'package:looper_player/features/playback/presentation/providers/playback/playback_notifier.dart';
import 'package:video_player/video_player.dart';

/// Central host managing reference-counted [VideoPlayerController] instances
/// per media source (Doc 20 §5.3, fixes bugs A15-A17).
class MotionArtworkHost {
  static final Map<String, _HostEntry> _active = {};
  // mediaSource (as given to the widget) -> playFrom (the cached file).
  static final Map<String, String> _alias = {};

  /// The already-playing controller for [source], acquired synchronously, or
  /// null when none is live yet. A widget mounted mid-transition (a Hero
  /// landing, a flight shuttle, the Fluid Player's morph) paints the same
  /// texture on its first frame instead of its still art.
  static (VideoPlayerController, String)? acquireLive(String source) {
    final String playFrom = _alias[source] ?? source;
    final _HostEntry? entry = _active[playFrom];
    if (entry == null || !entry.ready) return null;
    entry.cancelDisposeTimer();
    entry.refCount++;
    return (entry.controller, playFrom);
  }

  static Future<VideoPlayerController?> acquire(
    String playFrom, {
    required bool isLocal,
    required bool muted,
    required bool loop,
    required bool autoPlay,
    String? alias,
    Map<String, String> headers = const {},
  }) async {
    if (alias != null) _alias[alias] = playFrom;
    _HostEntry? entry = _active[playFrom];
    if (entry != null) {
      entry.cancelDisposeTimer();
      entry.refCount++;
      try {
        await entry.initFuture;
        if (autoPlay && !entry.controller.value.isPlaying) {
          entry.controller.play();
        }
        return entry.controller;
      } catch (_) {
        return null;
      }
    }

    final VideoPlayerController controller;
    if (isLocal) {
      final file = File(playFrom);
      if (!file.existsSync()) return null;
      controller = VideoPlayerController.file(
        file,
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );
    } else {
      controller = VideoPlayerController.networkUrl(
        Uri.parse(playFrom),
        httpHeaders: headers,
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );
    }

    final completer = Completer<void>();
    entry = _HostEntry(
      controller: controller,
      initFuture: completer.future,
      refCount: 1,
    );
    _active[playFrom] = entry;

    try {
      await controller.initialize();
      if (muted) await controller.setVolume(0.0);
      await controller.setLooping(loop);
      if (autoPlay) await controller.play();
      entry.ready = true;
      completer.complete();
      return controller;
    } catch (e) {
      _active.remove(playFrom);
      completer.completeError(e);
      controller.dispose();
      return null;
    }
  }

  /// A widget showing [playFrom] appeared (+1), disappeared (-1) or just
  /// took hold of it (0). With nothing on screen the video stops decoding;
  /// the expanded player stays mounted behind the music bar. Deferred because
  /// this runs during build and the controller notifies its listeners.
  static void updateShowing(
    String playFrom,
    int change, {
    required bool shouldPlay,
  }) {
    final entry = _active[playFrom];
    if (entry == null) return;
    entry.showing += change;
    scheduleMicrotask(() {
      if (!identical(_active[playFrom], entry) || !entry.ready) return;
      final value = entry.controller.value;
      if (entry.showing <= 0) {
        if (value.isPlaying) entry.controller.pause();
      } else if (shouldPlay && !value.isPlaying) {
        entry.controller.play();
      }
    });
  }

  /// Shared by every widget showing [playFrom], so they correct it only once.
  static VideoResyncGate? resyncGate(String playFrom) =>
      _active[playFrom]?.resync;

  static void release(String playFrom) {
    final entry = _active[playFrom];
    if (entry == null) return;
    entry.refCount--;
    if (entry.refCount <= 0) {
      entry.startDisposeTimer(() {
        _active.remove(playFrom);
        _alias.removeWhere((_, v) => v == playFrom);
        entry.controller.dispose();
      });
    }
  }
}

/// Spaces out the seeks that keep a streamed video on the song. A seek drops
/// the video's buffer, so on a slow connection seeking at a fixed rate means
/// it never finishes buffering. Each correction doubles the wait (2 s to 16 s)
/// until the video has stayed in step for a full wait.
class VideoResyncGate {
  static const _shortest = Duration(seconds: 2);
  static const _longest = Duration(seconds: 16);

  Duration _wait = _shortest;
  DateTime? _next;

  bool tryClaim(DateTime now) {
    if (_next != null && now.isBefore(_next!)) return false;
    _next = now.add(_wait);
    _wait = _wait * 2 > _longest ? _longest : _wait * 2;
    return true;
  }

  void inStep(DateTime now) {
    if (_next == null || !now.isBefore(_next!)) _wait = _shortest;
  }
}

class _HostEntry {
  final VideoPlayerController controller;
  final Future<void> initFuture;
  final VideoResyncGate resync = VideoResyncGate();
  int refCount;
  int showing = 0;
  bool ready = false;
  Timer? _disposeTimer;

  _HostEntry({
    required this.controller,
    required this.initFuture,
    required this.refCount,
  });

  void cancelDisposeTimer() {
    _disposeTimer?.cancel();
    _disposeTimer = null;
  }

  void startDisposeTimer(VoidCallback onDispose) {
    _disposeTimer?.cancel();
    _disposeTimer = Timer(const Duration(seconds: 10), onDispose);
  }
}

class AnimatedArtworkWidget extends ConsumerStatefulWidget {
  final String? mediaSource; // Local file path or network m3u8/mp4 URL
  final Widget staticFallback;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final bool muted;
  final bool loop;
  final bool autoPlay;

  const AnimatedArtworkWidget({
    super.key,
    required this.mediaSource,
    required this.staticFallback,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.muted = true,
    this.loop = true,
    this.autoPlay = true,
  });

  @override
  ConsumerState<AnimatedArtworkWidget> createState() =>
      _AnimatedArtworkWidgetState();
}

class _AnimatedArtworkWidgetState extends ConsumerState<AnimatedArtworkWidget>
    with WidgetsBindingObserver {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _hasFirstFrame = false;
  String? _activeSource;

  /// The source this widget holds a host reference on. [_activeSource] is
  /// set before the load finishes; releasing that dropped another widget's
  /// reference, and the host then disposed its video 10 s later.
  String? _heldSource;

  /// False while hidden: a covered route, an off tab, the collapsed player.
  bool _tickersOn = true;
  bool _countedShowing = false;
  Timer? _firstFrameTimer;
  bool _built = false;

  /// A YouTube video that follows the song's position.
  Timer? _syncTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initPlayer();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tickersOn = TickerMode.valuesOf(context).enabled;
    _syncShowing();
  }

  bool get _shouldPlay =>
      widget.autoPlay && ref.read(playbackProvider).isPlaying;

  void _syncShowing() {
    final source = _heldSource;
    if (source == null) return;
    final change = _tickersOn == _countedShowing ? 0 : (_tickersOn ? 1 : -1);
    _countedShowing = _tickersOn;
    MotionArtworkHost.updateShowing(
      source,
      change,
      shouldPlay: _tickersOn && _shouldPlay,
    );
  }

  @override
  void didUpdateWidget(covariant AnimatedArtworkWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mediaSource != widget.mediaSource) {
      _initPlayer();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_controller == null || !_isInitialized) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      _controller?.pause();
    } else if (state == AppLifecycleState.resumed) {
      // Not while the song is paused: the video would run ahead of it.
      if (mounted && _tickersOn && _shouldPlay) {
        _controller?.play();
      }
    }
  }

  Future<void> _initPlayer() async {
    final source = widget.mediaSource;
    if (source == null || source.isEmpty) {
      _disposeCurrentController();
      if (mounted) {
        setState(() {
          _isInitialized = false;
          _hasFirstFrame = false;
          _activeSource = null;
        });
      }
      return;
    }

    if (source == _activeSource && _controller != null) {
      return;
    }

    // Check settings and network permission
    final settings = ref.read(animatedArtworkSettingsProvider);
    if (settings.mode == AnimatedArtworkMode.never) {
      _disposeCurrentController();
      return;
    }

    // Already playing elsewhere (the real artwork, a shuttle): show that
    // texture from this widget's first frame, no still art and no fade.
    final live = MotionArtworkHost.acquireLive(source);
    if (live != null) {
      _disposeCurrentController();
      _controller = live.$1;
      _activeSource = live.$2;
      _heldSource = live.$2;
      _syncShowing();
      _controller!.addListener(_videoListener);
      _isInitialized = true;
      _hasFirstFrame = true;
      // From initState the first build is still ahead; no setState needed.
      if (_built) setState(() {});
      return;
    }

    var playFrom = source;
    final youtube = YoutubeVideoArtwork.infoFor(source);
    if (youtube != null) {
      // Streamed, never cached whole: a music video is tens of MB.
      if (!await AnimatedArtworkService.instance.isNetworkPermitted() ||
          !mounted ||
          widget.mediaSource != source) {
        _disposeCurrentController();
        return;
      }
    } else if (source.startsWith('http')) {
      final permitted = await AnimatedArtworkService.instance
          .isNetworkPermitted();
      if (!permitted && mounted) {
        _disposeCurrentController();
        return;
      }
      // Play from the cached file so the loop never stalls on the network;
      // the still art shows meanwhile. Streams only if the download fails.
      _disposeCurrentController();
      _activeSource = source;
      playFrom =
          await AnimatedArtworkService.instance.localFileFor(source) ?? source;
      if (!mounted || widget.mediaSource != source) return;
    }
    final isLocal = !playFrom.startsWith('http');
    if (isLocal) {
      await AnimatedArtworkService.instance.ensureTimeline(playFrom);
      if (!mounted || widget.mediaSource != source) return;
    }

    _disposeCurrentController();
    _activeSource = playFrom;

    try {
      final controller = await MotionArtworkHost.acquire(
        playFrom,
        isLocal: isLocal,
        muted: widget.muted,
        loop: youtube != null ? !youtube.synced : widget.loop,
        autoPlay: widget.autoPlay,
        alias: source,
        headers: youtube == null ? const {} : {'User-Agent': youtube.userAgent},
      );

      if (!mounted ||
          _activeSource != playFrom ||
          _heldSource != null ||
          controller == null) {
        if (controller != null) MotionArtworkHost.release(playFrom);
        return;
      }

      _controller = controller;
      _heldSource = playFrom;
      _syncShowing();
      controller.addListener(_videoListener);
      if (youtube?.synced ?? false) _startSync();

      final val = controller.value;
      final alreadyPresented =
          val.isInitialized && (val.position > Duration.zero || val.isPlaying);

      if (mounted) {
        setState(() {
          _isInitialized = val.isInitialized;
          _hasFirstFrame = alreadyPresented;
        });
      }

      if (!_hasFirstFrame) {
        _firstFrameTimer?.cancel();
        _firstFrameTimer = Timer(const Duration(milliseconds: 800), () {
          if (mounted &&
              _controller != null &&
              !_hasFirstFrame &&
              _controller!.value.isInitialized) {
            setState(() {
              _hasFirstFrame = true;
            });
          }
        });
      }
    } catch (_) {
      _disposeCurrentController();
    }
  }

  void _videoListener() {
    final c = _controller;
    if (c == null || !mounted || _hasFirstFrame) return;
    final value = c.value;
    // Only present once decoder has produced and painted the first frame (Bug A14)
    if (value.isInitialized &&
        (value.position > Duration.zero || value.isPlaying)) {
      _firstFrameTimer?.cancel();
      setState(() {
        _hasFirstFrame = true;
      });
    }
  }

  /// Keeps a synced YouTube video within 400 ms of the song: it starts at
  /// the song's position and is nudged back after seeks and stalls, never
  /// while it is still buffering.
  void _startSync() {
    _syncTimer?.cancel();
    void check() {
      final c = _controller;
      final source = _activeSource;
      if (c == null || source == null || !mounted) return;
      if (!_tickersOn) return;
      if (!c.value.isInitialized || c.value.isBuffering) return;
      final song = ref.read(playbackProvider).position;
      final drift = (c.value.position - song).abs();
      final gate = MotionArtworkHost.resyncGate(source);
      final now = DateTime.now();
      if (drift <= const Duration(milliseconds: 400)) {
        gate?.inStep(now);
      } else if (song < c.value.duration && (gate?.tryClaim(now) ?? true)) {
        // The seek itself takes a moment; land slightly ahead.
        c.seekTo(song + const Duration(milliseconds: 150));
      }
    }

    check();
    _syncTimer = Timer.periodic(const Duration(seconds: 1), (_) => check());
  }

  void _disposeCurrentController() {
    _syncTimer?.cancel();
    _syncTimer = null;
    _firstFrameTimer?.cancel();
    _firstFrameTimer = null;
    _controller?.removeListener(_videoListener);
    if (_heldSource != null) {
      if (_countedShowing) {
        MotionArtworkHost.updateShowing(_heldSource!, -1, shouldPlay: false);
      }
      _countedShowing = false;
      MotionArtworkHost.release(_heldSource!);
    }
    _heldSource = null;
    _controller = null;
    _activeSource = null;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _disposeCurrentController();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _built = true;
    // Follow the music playback state (Doc 20 §5.3 Bug A15)
    ref.listen(playbackProvider.select((s) => s.isPlaying), (prev, isPlaying) {
      if (_controller == null || !_isInitialized) return;
      if (isPlaying) {
        if (widget.autoPlay && _tickersOn && !_controller!.value.isPlaying) {
          _controller?.play();
        }
      } else {
        if (_controller!.value.isPlaying) {
          _controller?.pause();
        }
      }
    });

    final child = Stack(
      fit: StackFit.expand,
      children: [
        // Static fallback always present underneath for instantaneous rendering
        widget.staticFallback,

        // Video texture fading in smoothly upon first rendered frame
        if (_isInitialized && _controller != null)
          AnimatedOpacity(
            opacity: _hasFirstFrame ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeInOut,
            child: SizedBox.expand(
              child: FittedBox(
                fit: widget.fit,
                clipBehavior: Clip.hardEdge,
                child: SizedBox(
                  width: _controller!.value.size.width > 0
                      ? _controller!.value.size.width
                      : 100,
                  height: _controller!.value.size.height > 0
                      ? _controller!.value.size.height
                      : 100,
                  child: VideoPlayer(_controller!),
                ),
              ),
            ),
          ),
      ],
    );

    if (widget.borderRadius != null) {
      return ClipRRect(borderRadius: widget.borderRadius!, child: child);
    }

    return child;
  }
}
