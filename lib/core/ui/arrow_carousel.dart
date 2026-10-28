import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:scapematch/app/theme.dart';
import 'package:scapematch/core/ui/app_keys.dart';

/// Largura em que um quadro ainda se lê. A faixa cabe um ou dois quadros
/// inteiros, o que essa largura permitir na tela.
const carouselPreferredItemWidth = 250.0;

/// Quanto da faixa um carrossel ocupa, em quadros inteiros.
///
/// Um quadro só preenche a largura visível: o vão fica depois da borda, e o
/// próximo quadro não aparece cortado. Dois ou mais dividem a largura e o
/// vão, sem sobra. Cada parada anda um quadro.
class CarouselLayout {
  const CarouselLayout({
    required this.itemWidth,
    required this.gap,
    required this.perView,
    required this.stops,
  });

  final double itemWidth;
  final double gap;
  final int perView;
  final int stops;

  double get stride => itemWidth + gap;

  static CarouselLayout fit({
    required double viewport,
    required int itemCount,
    double gap = 12,
    double preferredItemWidth = carouselPreferredItemWidth,
  }) {
    final count = math.max(1, itemCount);
    final safeGap = math.max(0.0, gap);
    if (viewport <= 1) {
      final width = preferredItemWidth > 1 ? preferredItemWidth : 280.0;
      return CarouselLayout(
        itemWidth: width,
        gap: safeGap,
        perView: 1,
        stops: count,
      );
    }
    final preferred = preferredItemWidth.clamp(1.0, viewport);
    var perView = ((viewport + safeGap) / (preferred + safeGap)).floor();
    if (perView < 1) {
      perView = 1;
    }
    if (perView > count) {
      perView = count;
    }
    final itemWidth = perView == 1
        ? viewport
        : (viewport - ((perView - 1) * safeGap)) / perView;
    return CarouselLayout(
      itemWidth: itemWidth,
      gap: safeGap,
      perView: perView,
      stops: math.max(1, count - perView + 1),
    );
  }
}

/// Faixa horizontal que descansa sempre em quadros inteiros.
///
/// A seta anda um quadro, com animação, e some na ponta. Soltar o dedo
/// alinha no quadro mais próximo. Os pontos, quando aparecem, são essas
/// paradas — contadas pela largura, não pela estimativa da lista.
class ArrowCarousel extends StatefulWidget {
  const ArrowCarousel({
    super.key,
    required this.id,
    required this.height,
    required this.itemCount,
    required this.itemBuilder,
    this.gap = 12,
    this.showDots = false,
    this.preferredItemWidth = carouselPreferredItemWidth,
  });

  final String id;
  final double height;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final double gap;
  final bool showDots;
  final double preferredItemWidth;

  @override
  State<ArrowCarousel> createState() => _ArrowCarouselState();
}

class _ArrowCarouselState extends State<ArrowCarousel> {
  final _controller = ScrollController(keepScrollOffset: false);
  final _stride = _CarouselStride();
  Size? _mediaSize;
  TextScaler? _textScaler;
  CarouselLayout? _layout;
  int _index = 0;
  bool _holdIndex = false;

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
    if (sizeChanged) {
      // A lista prende o offset antigo no fim novo. Segurar o índice
      // mantém o quadro em que a pessoa estava.
      _holdIndex = true;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      if (_holdIndex) {
        _realign();
      } else {
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
    if (!mounted || _holdIndex || _layout == null || !_ready()) {
      return;
    }
    final next = _indexFor(_layout!, _controller.position.pixels);
    if (next == _index) {
      final back = _canGo(-1, _layout!);
      final forward = _canGo(1, _layout!);
      if (back == _showingBack && forward == _showingForward) {
        return;
      }
    }
    setState(() {
      _index = next;
    });
  }

  bool _showingBack = false;
  bool _showingForward = false;

  bool _ready() {
    return _controller.hasClients &&
        _controller.position.hasViewportDimension &&
        widget.itemCount > 0;
  }

  bool _canGo(int direction, CarouselLayout layout) {
    if (layout.stops <= 1 || widget.itemCount <= 1) {
      return false;
    }
    if (!_ready()) {
      return direction > 0;
    }
    final pixels = _controller.position.pixels;
    final max = _travelLimit(layout);
    if (max <= 1) {
      return false;
    }
    if (direction < 0) {
      return pixels > 1;
    }
    return pixels < max - 1;
  }

  double _travelLimit(CarouselLayout layout) {
    final known = _maxFor(layout);
    if (!_ready()) {
      return known;
    }
    return math.min(known, _controller.position.maxScrollExtent);
  }

  double _maxFor(CarouselLayout layout) {
    if (layout.stops <= 1) {
      return 0;
    }
    return (layout.stops - 1) * layout.stride;
  }

  int _indexFor(CarouselLayout layout, double pixels) {
    if (layout.stride <= 1 || layout.stops <= 1) {
      return 0;
    }
    return (pixels / layout.stride).round().clamp(0, layout.stops - 1);
  }

  void _realign() {
    if (!_ready()) {
      _holdIndex = false;
      if (mounted) {
        setState(() {});
      }
      return;
    }
    final layout = CarouselLayout.fit(
      viewport: _controller.position.viewportDimension,
      itemCount: widget.itemCount,
      gap: widget.gap,
      preferredItemWidth: widget.preferredItemWidth,
    );
    final index = _index.clamp(0, layout.stops - 1);
    final target = (index * layout.stride).clamp(0.0, _travelLimit(layout));
    if ((_controller.position.pixels - target).abs() > 0.5) {
      _controller.jumpTo(target);
    }
    _index = index;
    _holdIndex = false;
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _page(int direction) async {
    final layout = _layout;
    if (layout == null || !_canGo(direction, layout) || !_ready()) {
      return;
    }
    final current = _indexFor(layout, _controller.position.pixels);
    final target = ((current + direction) * layout.stride).clamp(
      0.0,
      _travelLimit(layout),
    );
    await _controller.animateTo(
      target,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = CarouselLayout.fit(
          viewport: constraints.maxWidth,
          itemCount: widget.itemCount,
          gap: widget.gap,
          preferredItemWidth: widget.preferredItemWidth,
        );
        _layout = layout;
        // A Scrollable só troca a física se o tipo mudar. O passo vive
        // neste objeto, lido na hora de soltar o dedo.
        _stride.value = layout.stride;
        final canBack = _canGo(-1, layout);
        final canForward = _canGo(1, layout);
        _showingBack = canBack;
        _showingForward = canForward;
        final carousel = RepaintBoundary(
          key: AppKeys.carouselFrame(widget.id),
          child: SizedBox(
            height: widget.height,
            child: Stack(
              children: [
                NotificationListener<ScrollMetricsNotification>(
                  onNotification: (notification) {
                    if (mounted && !_holdIndex) {
                      setState(() {});
                    }
                    return false;
                  },
                  child: ScrollConfiguration(
                    behavior: ScrollConfiguration.of(context)
                        .copyWith(scrollbars: false),
                    child: ListView.builder(
                      controller: _controller,
                      scrollDirection: Axis.horizontal,
                      physics: _ItemSnapPhysics(
                        stride: _stride,
                        parent: const ClampingScrollPhysics(),
                      ),
                      padding: EdgeInsets.zero,
                      cacheExtent: 800,
                      itemExtent: layout.stride,
                      itemCount: widget.itemCount,
                      itemBuilder: (context, index) {
                        return Padding(
                          padding: EdgeInsets.only(right: widget.gap),
                          child: SizedBox(
                            key: AppKeys.carouselItem(widget.id, index),
                            width: layout.itemWidth,
                            height: widget.height,
                            child: widget.itemBuilder(context, index),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                if (canBack)
                  Positioned(
                    left: 0,
                    top: 0,
                    height: _arrowBand(widget.height),
                    child: Center(
                      child: _CarouselArrow(
                        carouselId: widget.id,
                        forward: false,
                        onPressed: () => _page(-1),
                      ),
                    ),
                  ),
                if (canForward)
                  Positioned(
                    right: 0,
                    top: 0,
                    height: _arrowBand(widget.height),
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
          ),
        );
        if (!widget.showDots) {
          return carousel;
        }
        final pages = layout.stops;
        final current = _ready()
            ? _indexFor(layout, _controller.position.pixels)
            : _index.clamp(0, pages - 1);
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
}

/// A seta fica na faixa da foto, para não cobrir título nem botão.
double _arrowBand(double height) => math.min(120, height);

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

/// O passo do snap. A [Scrollable] guarda a primeira física; este valor
/// muda quando a tela muda, sem criar outra posição de rolagem.
class _CarouselStride {
  double value = 1;
}

/// Soltar o arrasto alinha no quadro mais próximo. Não continua o impulso.
class _ItemSnapPhysics extends ScrollPhysics {
  const _ItemSnapPhysics({required this.stride, super.parent});

  final _CarouselStride stride;

  @override
  _ItemSnapPhysics applyTo(ScrollPhysics? ancestor) {
    return _ItemSnapPhysics(stride: stride, parent: buildParent(ancestor));
  }

  double _target(ScrollMetrics position) {
    final step = stride.value;
    final max = position.maxScrollExtent;
    if (step <= 1 || max <= 1) {
      return position.pixels.clamp(0.0, max);
    }
    final index = (position.pixels / step).round();
    final maxIndex = (max / step).round();
    return (index.clamp(0, maxIndex) * step).clamp(0.0, max);
  }

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    final tolerance = toleranceFor(position);
    final target = _target(position);
    if (velocity.abs() < tolerance.velocity &&
        (target - position.pixels).abs() < tolerance.distance) {
      return null;
    }
    return ScrollSpringSimulation(
      spring,
      position.pixels,
      target,
      0,
      tolerance: tolerance,
    );
  }
}
