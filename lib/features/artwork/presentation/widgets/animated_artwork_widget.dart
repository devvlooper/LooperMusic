import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:looper_player/features/artwork/data/animated_artwork_service.dart';
import 'package:looper_player/features/artwork/domain/animated_artwork_models.dart';
import 'package:video_player/video_player.dart';

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initPlayer();
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
      if (widget.autoPlay && mounted) {
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

    final isLocal = !source.startsWith('http');
    if (!isLocal) {
      final permitted = await AnimatedArtworkService.instance.isNetworkPermitted();
      if (!permitted && mounted) {
        _disposeCurrentController();
        return;
      }
    }

    _disposeCurrentController();
    _activeSource = source;

    try {
      final VideoPlayerController controller;
      if (isLocal) {
        final file = File(source);
        if (!file.existsSync()) return;
        controller = VideoPlayerController.file(
          file,
          videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
        );
      } else {
        controller = VideoPlayerController.networkUrl(
          Uri.parse(source),
          videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
        );
      }

      _controller = controller;

      await controller.initialize();
      if (!mounted || _controller != controller) {
        controller.dispose();
        return;
      }

      if (widget.muted) {
        await controller.setVolume(0.0);
      }
      if (widget.loop) {
        await controller.setLooping(true);
      }

      controller.addListener(_videoListener);

      if (widget.autoPlay) {
        await controller.play();
      }

      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }
    } catch (_) {
      _disposeCurrentController();
    }
  }

  void _videoListener() {
    if (_controller == null || !mounted) return;
    if (!_hasFirstFrame &&
        _controller!.value.isInitialized &&
        _controller!.value.position > Duration.zero) {
      setState(() {
        _hasFirstFrame = true;
      });
    }
  }

  void _disposeCurrentController() {
    _controller?.removeListener(_videoListener);
    _controller?.pause();
    _controller?.dispose();
    _controller = null;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _disposeCurrentController();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final child = Stack(
      fit: StackFit.expand,
      children: [
        // Static fallback always present underneath for instantaneous rendering
        widget.staticFallback,

        // Video texture fading in smoothly upon first rendered frame
        if (_isInitialized && _controller != null)
          AnimatedOpacity(
            opacity: _hasFirstFrame ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
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
      return ClipRRect(
        borderRadius: widget.borderRadius!,
        child: child,
      );
    }

    return child;
  }
}
