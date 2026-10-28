import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:scapematch/app/theme.dart';
import 'package:scapematch/core/ui/app_keys.dart';

/// Faixa horizontal com swipe e setas.
///
/// Sem [pageExtent], a seta anda a largura visível. Com ele, anda essa
/// distância (um card mais o vão). A seta some na ponta. O clique funciona
/// com mouse, sem arrastar. Os pontos, quando aparecem, são as paradas que
/// a seta realmente alcança.
class ArrowCarousel extends StatefulWidget {
  const ArrowCarousel({
    super.key,
    required this.id,
    required this.height,
    required this.itemCount,
    required this.itemBuilder,
    this.gap = 12,
    this.showDots = false,
    this.pageExtent,
  });

  final String id;
  final double height;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final double gap;
  final bool showDots;

  /// Distância de cada toque na seta. Nulo usa a largura visível.
  final double? pageExtent;

  @override
  State<ArrowCarousel> createState() => _ArrowCarouselState();
}

class _ArrowCarouselState extends State<ArrowCarousel> {
  final _controller = ScrollController();
  Size? _mediaSize;
  TextScaler? _textScaler;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final media = MediaQuery.of(context);
    final sizeChanged = _mediaSize != media.size;
    final scaleChanged = _textScaler != media.textScaler;
    _mediaSize = media.size;
    _textScaler = media.textScaler;
    if (!sizeChanged && !scaleChanged) {
      return;
    }
    // O layout novo só existe depois deste frame. Sem isso, seta e ponto
    // ficam com a medida antiga até alguém arrastar.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_onScroll);
    _controller.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (mounted) {
      setState(() {});
    }
  }

  bool _ready() {
    return _controller.hasClients &&
        _controller.position.hasViewportDimension &&
        widget.itemCount > 0;
  }

  bool _canGo(int direction) {
    if (!_ready()) {
      return false;
    }
    final position = _controller.position;
    final limit = _travelLimit(position);
    if (limit <= 1) {
      return false;
    }
    if (direction < 0) {
      return position.pixels > 1;
    }
    return position.pixels < limit - 1;
  }

  /// A lista estima o fim antes de medir todos os cards e infla o extent.
  /// Com [ArrowCarousel.pageExtent], o fim real é o conteúdo conhecido.
  double _travelLimit(ScrollPosition position) {
    final known = _knownMaxScroll(position.viewportDimension);
    if (known == null) {
      return position.maxScrollExtent;
    }
    return math.min(known, position.maxScrollExtent);
  }

  double? _knownMaxScroll(double viewport) {
    final extent = widget.pageExtent;
    if (extent == null ||
        extent <= 0 ||
        widget.itemCount <= 0 ||
        viewport <= 0) {
      return null;
    }
    final content = widget.itemCount * extent - widget.gap;
    return math.max(0.0, content - viewport);
  }

  Future<void> _page(int direction) async {
    if (!_canGo(direction)) {
      return;
    }
    final position = _controller.position;
    final target =
        (position.pixels + (direction * _step(position, widget.pageExtent)))
            .clamp(0.0, _travelLimit(position));
    await _controller.animateTo(
      target,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final carousel = SizedBox(
      height: widget.height,
      child: Stack(
        children: [
          NotificationListener<ScrollMetricsNotification>(
            onNotification: (notification) {
              if (mounted) {
                setState(() {});
              }
              return false;
            },
            child: ListView.separated(
              controller: _controller,
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.zero,
              itemCount: widget.itemCount,
              separatorBuilder: (context, index) => SizedBox(width: widget.gap),
              itemBuilder: widget.itemBuilder,
            ),
          ),
          if (_canGo(-1))
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: Center(
                child: _CarouselArrow(
                  carouselId: widget.id,
                  forward: false,
                  onPressed: () => _page(-1),
                ),
              ),
            ),
          if (_canGo(1))
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              child: Center(
                child: _CarouselArrow(
                  carouselId: widget.id,
                  forward: true,
                  onPressed: () => _page(1),
                ),
              ),
            ),
        ],
      ),
    );
    if (!widget.showDots) {
      return carousel;
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = constraints.maxWidth;
        final maxScroll =
            _knownMaxScroll(viewport) ??
            (_ready() ? _controller.position.maxScrollExtent : 0.0);
        final step = _stepFor(viewport);
        final pages = _stopCount(maxScroll, step);
        final current = _stopIndex(maxScroll, step, pages);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            carousel,
            const SizedBox(height: 8),
            _Dots(pages: pages, current: current),
          ],
        );
      },
    );
  }

  double _stepFor(double viewport) {
    final extent = widget.pageExtent;
    if (extent != null && extent > 0) {
      return extent;
    }
    if (viewport > 0) {
      return viewport;
    }
    return 1;
  }

  int _stopIndex(double maxScroll, double step, int pages) {
    if (!_ready() || pages <= 1) {
      return 0;
    }
    final position = _controller.position;
    if (position.pixels >= maxScroll - 1) {
      return pages - 1;
    }
    var best = 0;
    var bestDistance = double.infinity;
    var offset = 0.0;
    for (var index = 0; index < pages; index++) {
      final distance = (position.pixels - offset).abs();
      if (distance < bestDistance) {
        bestDistance = distance;
        best = index;
      }
      offset = math.min(offset + step, maxScroll);
    }
    return best;
  }
}

class _CarouselArrow extends StatelessWidget {
  const _CarouselArrow({
    required this.carouselId,
    required this.forward,
    required this.onPressed,
  });

  final String carouselId;
  final bool forward;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final label = forward ? 'Próximo' : 'Anterior';
    return IconButton(
      key: forward
          ? AppKeys.carouselNext(carouselId)
          : AppKeys.carouselPrevious(carouselId),
      tooltip: label,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: AppColors.teal,
        minimumSize: const Size(44, 44),
        fixedSize: const Size(44, 44),
        side: const BorderSide(color: AppColors.line),
      ),
      icon: Icon(forward ? Icons.chevron_right : Icons.chevron_left),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.pages, required this.current});

  final int pages;
  final int current;

  @override
  Widget build(BuildContext context) {
    return Row(
      key: AppKeys.promoDots,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var index = 0; index < pages; index++)
          Container(
            width: index == current ? 16 : 7,
            height: 7,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            decoration: BoxDecoration(
              color: index == current ? AppColors.teal : AppColors.line,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
      ],
    );
  }
}

double _step(ScrollPosition position, double? pageExtent) {
  final extent = pageExtent;
  if (extent != null && extent > 0) {
    return extent;
  }
  final view = position.viewportDimension;
  if (view <= 0) {
    return 1;
  }
  return view;
}

/// Paradas que a seta alcança, inclusive a sobra menor que um passo.
int _stopCount(double maxScroll, double step) {
  if (maxScroll <= 1 || step <= 0) {
    return 1;
  }
  var pages = 1;
  var offset = 0.0;
  while (offset < maxScroll - 1 && pages < 64) {
    final next = math.min(offset + step, maxScroll);
    if (next <= offset + 0.5) {
      break;
    }
    offset = next;
    pages++;
  }
  return pages;
}
