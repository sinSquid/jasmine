import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// A static gradient: long image lists do not keep shimmer tickers running.
class ReaderImagePlaceholder extends StatelessWidget {
  const ReaderImagePlaceholder(
      {Key? key, this.width, this.height, this.statusScale = 1})
      : super(key: key);

  final double? width;
  final double? height;
  final double statusScale;

  @override
  Widget build(BuildContext context) {
    // Reader canvases can be black even when the surrounding app is light.
    // Neutral gray remains visible against both without a bright loading flash.
    const color = Color(0xFF8A8A8A);
    return SizedBox(
      width: width,
      height: height,
      child: Semantics(
        label: '图片加载中',
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                color.withValues(alpha: 0.10),
                color.withValues(alpha: 0.18),
                color.withValues(alpha: 0.10),
              ],
            ),
          ),
          child: LayoutBuilder(builder: (context, constraints) {
            final scale =
                statusScale.isFinite && statusScale > 0 ? statusScale : 1.0;
            final size = (24 * scale)
                .clamp(0.0, constraints.biggest.shortestSide)
                .toDouble();
            return Center(
              child: Icon(Icons.image_outlined,
                  size: size, color: color.withValues(alpha: 0.65)),
            );
          }),
        ),
      ),
    );
  }
}

/// Keeps the displayed frame while a sharper version of the same image loads.
/// Change [identity] when switching images or invalidating all their versions.
class FadingReaderImage extends StatefulWidget {
  const FadingReaderImage({
    Key? key,
    required this.image,
    required this.identity,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
    this.alignment = Alignment.center,
    this.statusScale = 1,
    this.onReload,
    this.onImageSize,
    this.initialImageProvider,
  }) : super(key: key);

  /// Null reserves the image's layout while its file or metadata is loading.
  final ImageProvider? image;
  final Object identity;
  final double? width;
  final double? height;
  final BoxFit fit;
  final AlignmentGeometry alignment;

  /// Compensates for an externally scaled reader canvas without scaling pixels.
  final double statusScale;
  final VoidCallback? onReload;

  /// Reports the first primary frame's decoded pixel dimensions after layout.
  /// Cached fallback frames and later quality upgrades are not reported.
  final ValueChanged<Size>? onImageSize;

  /// An optional existing cache entry to show until [image] has a frame.
  /// A cache miss never starts a download or decode for this provider.
  final ImageProvider? initialImageProvider;

  @override
  State<FadingReaderImage> createState() => _FadingReaderImageState();
}

class _FadingReaderImageState extends State<FadingReaderImage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
  )..addStatusListener(_onFadeStatus);
  late final CurvedAnimation _opacity =
      CurvedAnimation(parent: _fade, curve: Curves.easeOutCubic);
  ImageInfo? _imageInfo;
  ImageStream? _stream;
  ImageStreamListener? _listener;
  ImageStream? _initialStream;
  ImageStreamListener? _initialListener;
  ImageConfiguration? _configuration;
  ImageProvider? _provider;
  var _generation = 0;
  var _failed = false;
  var _retrying = false;
  var _reduceMotion = false;
  var _identityGeneration = 0;
  var _placeholderShown = false;
  var _placeholderMarkScheduled = false;
  var _imageSizeReported = false;
  int? _imageSizeNotificationGeneration;

  double get _statusScale =>
      widget.statusScale.isFinite && widget.statusScale > 0
          ? widget.statusScale
          : 1;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (_reduceMotion && _imageInfo != null) _fade.value = 1;
    _resolve();
  }

  @override
  void didUpdateWidget(covariant FadingReaderImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final changedIdentity = oldWidget.identity != widget.identity;
    if (changedIdentity) {
      _identityGeneration++;
      _placeholderShown = false;
      _placeholderMarkScheduled = false;
      _imageSizeReported = false;
      _imageSizeNotificationGeneration = null;
      _replaceFrame(null);
      _fade.value = 0;
    }
    _resolve(force: changedIdentity);
  }

  void _onFadeStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && mounted) setState(() {});
  }

  void _resolve({bool force = false}) {
    final configuration = createLocalImageConfiguration(context,
        size: widget.width != null && widget.height != null
            ? Size(widget.width!, widget.height!)
            : null);
    if (!force &&
        configuration == _configuration &&
        _provider == widget.image) {
      return;
    }
    final generation = ++_generation;
    _configuration = configuration;
    _provider = widget.image;
    _failed = false;
    _retrying = false;
    _detachInitial();
    _detach(_stream, _listener);
    _stream = null;
    _listener = null;

    final provider = widget.image;
    if (provider == null) {
      _replaceFrame(null);
      _fade.value = 0;
      return;
    }
    final initial = widget.initialImageProvider;
    if (_imageInfo == null && initial != null && initial != provider) {
      _useCachedInitial(initial, configuration, generation);
    }
    final stream = provider.resolve(configuration);
    final listener = ImageStreamListener((info, synchronousCall) {
      if (!mounted || generation != _generation) {
        info.dispose();
        return;
      }
      _detachInitial();
      _scheduleImageSize(info);
      _showFrame(info, synchronousCall);
    }, onError: (Object error, StackTrace? stack) {
      if (!mounted || generation != _generation) return;
      setState(() => _failed = true);
    });
    _stream = stream;
    _listener = listener;
    stream.addListener(listener);
  }

  void _scheduleImageSize(ImageInfo info) {
    if (_imageSizeReported ||
        widget.onImageSize == null ||
        _imageSizeNotificationGeneration == _generation) {
      return;
    }
    final generation = _generation;
    final size =
        Size(info.image.width.toDouble(), info.image.height.toDouble());
    _imageSizeNotificationGeneration = generation;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (_imageSizeNotificationGeneration == generation) {
        _imageSizeNotificationGeneration = null;
      }
      if (!mounted || generation != _generation || _imageSizeReported) return;
      final onImageSize = widget.onImageSize;
      if (onImageSize == null) return;
      _imageSizeReported = true;
      onImageSize(size);
    });
  }

  Future<void> _useCachedInitial(ImageProvider provider,
      ImageConfiguration configuration, int generation) async {
    // Obtain the key once, then access the cache synchronously. Resolving this
    // provider again could instead start a fresh decode after a cache eviction.
    final Object key;
    try {
      key = await provider.obtainKey(configuration);
    } catch (_) {
      // The initial frame is optional; the primary provider owns load errors.
      return;
    }
    if (!mounted || generation != _generation || _imageInfo != null) return;
    final cache = PaintingBinding.instance.imageCache;
    final status = cache.statusForKey(key);
    if ((!status.live && !status.keepAlive) || status.pending) return;
    final completer = cache.putIfAbsent(key, () {
      // There is no asynchronous gap between statusForKey and putIfAbsent.
      throw StateError('The initial image must already be cached');
    });
    if (completer == null) return;
    final stream = ImageStream()..setCompleter(completer);
    final listener = ImageStreamListener((info, synchronousCall) {
      if (!mounted || generation != _generation || _imageInfo != null) {
        info.dispose();
      } else {
        _showFrame(info, true, clearError: false);
      }
      _detachInitial();
    }, onError: (Object error, StackTrace? stack) {
      // A failed optional cached frame does not replace the primary load state.
      _detachInitial();
    });
    _initialStream = stream;
    _initialListener = listener;
    stream.addListener(listener);
  }

  void _showFrame(ImageInfo info, bool synchronousCall,
      {bool clearError = true}) {
    final firstFrame = _imageInfo == null;
    setState(() {
      _replaceFrame(info);
      if (clearError) _failed = false;
    });
    if (firstFrame) {
      if (_reduceMotion || (synchronousCall && !_placeholderShown)) {
        _fade.value = 1;
      } else {
        _fade.forward(from: 0);
      }
    }
  }

  Future<void> _retry() async {
    if (_retrying) return;
    if (_imageInfo == null && widget.onReload != null) {
      widget.onReload!();
      return;
    }
    final generation = _generation;
    final provider = widget.image;
    if (provider == null) return;
    setState(() => _retrying = true);
    try {
      // Retain the displayed frame and file while evicting only the failed
      // resolution. Whole-image invalidation would throw away the fallback.
      await provider.evict(configuration: _configuration!);
      if (!mounted || generation != _generation) return;
      setState(() => _resolve(force: true));
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _retrying = false;
        _failed = true;
      });
    }
  }

  void _replaceFrame(ImageInfo? next) {
    final old = _imageInfo;
    _imageInfo = next;
    if (old != null) {
      // RawImage can still paint the previous frame until the next build.
      SchedulerBinding.instance.addPostFrameCallback((_) => old.dispose());
    }
  }

  void _detach(ImageStream? stream, ImageStreamListener? listener) {
    if (stream == null || listener == null) return;
    stream.completer?.addEphemeralErrorListener((error, stack) {
      // The request may finish after its reader has left; it has no UI owner.
    });
    stream.removeListener(listener);
  }

  void _detachInitial() {
    _detach(_initialStream, _initialListener);
    _initialStream = null;
    _initialListener = null;
  }

  @override
  void dispose() {
    _generation++;
    _detachInitial();
    _detach(_stream, _listener);
    _replaceFrame(null);
    _opacity.dispose();
    _fade.dispose();
    super.dispose();
  }

  Widget _scaledStatus(Widget Function(BoxConstraints constraints) builder,
      {Alignment alignment = Alignment.center}) {
    return LayoutBuilder(builder: (context, constraints) {
      final scaledConstraints = BoxConstraints(
        maxWidth: constraints.maxWidth / _statusScale,
        maxHeight: constraints.maxHeight / _statusScale,
      );
      return Align(
        alignment: alignment,
        child: Transform.scale(
          scale: _statusScale,
          alignment: alignment,
          child: ConstrainedBox(
            constraints: scaledConstraints,
            child: builder(scaledConstraints),
          ),
        ),
      );
    });
  }

  Widget _errorPanel(ColorScheme colors) => _scaledStatus((constraints) {
        if (constraints.maxWidth < 180 || constraints.maxHeight < 140) {
          return Material(
            color: colors.surface.withValues(alpha: 0.85),
            shape: const CircleBorder(),
            child: IconButton(
              tooltip: '图片加载失败，重试',
              onPressed: _retrying ? null : _retry,
              constraints: BoxConstraints.tightFor(
                width: constraints.maxWidth.clamp(0, 40).toDouble(),
                height: constraints.maxHeight.clamp(0, 40).toDouble(),
              ),
              padding: EdgeInsets.zero,
              icon: Icon(Icons.refresh,
                  size:
                      constraints.biggest.shortestSide.clamp(0, 20).toDouble()),
            ),
          );
        }
        return FittedBox(
          fit: BoxFit.scaleDown,
          child: Material(
            color: colors.surface.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.broken_image_outlined),
                  const Text('图片加载失败'),
                  TextButton.icon(
                    onPressed: _retrying ? null : _retry,
                    icon: const Icon(Icons.refresh),
                    label: const Text('重试'),
                  ),
                ],
              ),
            ),
          ),
        );
      });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final hasFrame = _imageInfo != null;
    if (!hasFrame &&
        !_failed &&
        !_placeholderShown &&
        !_placeholderMarkScheduled) {
      final identityGeneration = _identityGeneration;
      _placeholderMarkScheduled = true;
      // A provider may synchronously hit cache only after its file Future has
      // completed. If this placeholder already painted, that still needs a
      // transition; only an initially cached frame can skip it.
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!mounted || identityGeneration != _identityGeneration) return;
        _placeholderShown = true;
        _placeholderMarkScheduled = false;
      });
    }
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          FadeTransition(
            opacity: _opacity,
            child: RawImage(
              image: _imageInfo?.image,
              scale: _imageInfo?.scale ?? 1,
              width: widget.width,
              height: widget.height,
              fit: widget.fit,
              alignment: widget.alignment,
            ),
          ),
          if ((!hasFrame && !_failed) || (hasFrame && _fade.value < 1))
            Positioned.fill(
              child: IgnorePointer(
                child: FadeTransition(
                  opacity: ReverseAnimation(_opacity),
                  child: ReaderImagePlaceholder(statusScale: _statusScale),
                ),
              ),
            ),
          if (_failed && !hasFrame) Positioned.fill(child: _errorPanel(colors)),
          if (_failed && hasFrame)
            Positioned.fill(
              child: Padding(
                padding: EdgeInsets.all(8 * _statusScale),
                child: _scaledStatus(
                  (constraints) => Material(
                    color: colors.surface.withValues(alpha: 0.85),
                    shape: const CircleBorder(),
                    child: IconButton(
                      tooltip: '高清加载失败，重试',
                      onPressed: _retrying ? null : _retry,
                      icon: const Icon(Icons.refresh, size: 20),
                    ),
                  ),
                  alignment: Alignment.bottomRight,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
