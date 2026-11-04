import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
///
/// Com [loop], o quadro depois do último segue em frente: a lista repete
/// os primeiros itens e um salto invisível devolve o offset ao ciclo
/// equivalente. Não há animação de volta para o início.
/// [autoAdvance] espera [autoAdvanceInterval], pausa com o ponteiro em
/// cima ou pressionado, e fica desligado nos testes de widget.
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
    this.loop = false,
    this.autoAdvance = false,
  });

  /// Espera entre um avanço automático e o seguinte.
  static const autoAdvanceInterval = Duration(seconds: 5);

  /// Permite o timer sob o binding de teste. O padrão é falso: um timer
  /// periódico não deixa o `pumpAndSettle` terminar e fica pendente no fim.
  @visibleForTesting
  static bool debugAllowAutoAdvanceInTests = false;

  final String id;
  final double height;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final double gap;
  final bool showDots;
  final double preferredItemWidth;

  /// Repete os itens para a frente, sem rebobinar.
  final bool loop;

  /// Anda um quadro sozinho, sempre para a frente.
  final bool autoAdvance;

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
  bool _closed = false;
  bool _hovering = false;
  bool _recenterQueued = false;
  int _pointers = 0;
  Timer? _autoTimer;

  /// Cópias à frente. Uma basta para o ciclo; as outras seguram um
  /// arrasto longo antes do salto que alinha de novo.
  static const _loopCopies = 6;

  bool _repeats(CarouselLayout layout) {
    return widget.loop && widget.itemCount > layout.perView;
  }

  int _slotCount(CarouselLayout layout) {
    if (!_repeats(layout)) {
      return widget.itemCount;
    }
    return widget.itemCount * _loopCopies;
  }

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _closed) {
        return;
      }
      _syncAuto();
      setState(() {});
    });
  }

  @override
  void didUpdateWidget(ArrowCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.autoAdvance != widget.autoAdvance ||
        oldWidget.itemCount != widget.itemCount ||
        oldWidget.loop != widget.loop) {
      _syncAuto();
    }
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
    _closed = true;
    _autoTimer?.cancel();
    _autoTimer = null;
    _controller.removeListener(_onScroll);
    _controller.dispose();
    super.dispose();
  }

  bool get _autoEnabled {
    if (!widget.autoAdvance || widget.itemCount <= 1 || _closed) {
      return false;
    }
    final tests = WidgetsBinding.instance.runtimeType.toString().contains(
      'Test',
    );
    if (tests && !ArrowCarousel.debugAllowAutoAdvanceInTests) {
      return false;
    }
    final layout = _layout;
    if (layout != null && layout.perView >= widget.itemCount) {
      return false;
    }
    return true;
  }

  void _syncAuto() {
    final run = _autoEnabled && !_hovering && _pointers == 0 && mounted;
    if (!run) {
      _autoTimer?.cancel();
      _autoTimer = null;
      return;
    }
    _autoTimer ??= Timer(ArrowCarousel.autoAdvanceInterval, () {
      unawaited(_handleAuto());
    });
  }

  Future<void> _handleAuto() async {
    _autoTimer = null;
    if (!mounted || _closed || !_autoEnabled || _hovering || _pointers > 0) {
      return;
    }
    await _page(1);
    if (!mounted || _closed) {
      return;
    }
    _syncAuto();
  }

  void _onHover(bool hovering) {
    if (_hovering == hovering) {
      return;
    }
    _hovering = hovering;
    _syncAuto();
  }

  void _onPointerDown(PointerDownEvent event) {
    _pointers += 1;
    _syncAuto();
  }

  void _onPointerEnd(PointerEvent event) {
    if (_pointers == 0) {
      return;
    }
    _pointers -= 1;
    _syncAuto();
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
    if (widget.itemCount <= 1) {
      return false;
    }
    if (widget.loop) {
      if (layout.perView >= widget.itemCount) {
        return false;
      }
      if (!_ready()) {
        return direction > 0;
      }
      final max = _controller.position.maxScrollExtent;
      if (max <= 1) {
        return false;
      }
      final pixels = _controller.position.pixels;
      if (direction < 0) {
        return pixels > 1;
      }
      return pixels < max - 1;
    }
    if (layout.stops <= 1) {
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

  int _maxIndex(CarouselLayout layout) {
    if (_repeats(layout)) {
      return math.max(0, _slotCount(layout) - layout.perView);
    }
    return math.max(0, layout.stops - 1);
  }

  int _indexFor(CarouselLayout layout, double pixels) {
    if (layout.stride <= 1) {
      return 0;
    }
    if (!widget.loop && layout.stops <= 1) {
      return 0;
    }
    return (pixels / layout.stride).round().clamp(0, _maxIndex(layout));
  }

  /// Quando a cópia seguinte já entrou, devolve o offset para o mesmo
  /// quadro no primeiro ciclo. O que está na tela não muda.
  void _queueRecenter() {
    if (!widget.loop || _recenterQueued || _closed || !mounted) {
      return;
    }
    final layout = _layout;
    if (layout == null || !_ready() || widget.itemCount <= 1) {
      return;
    }
    final stride = layout.stride;
    if (stride <= 1) {
      return;
    }
    final leading = (_controller.position.pixels / stride).round();
    if (leading < widget.itemCount) {
      return;
    }
    _recenterQueued = true;
    // O quadro seguinte pinta a cópia. O salto fica para o frame de
    // depois, senão a animação que chegou ali é cancelada no mesmo frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _closed) {
        _recenterQueued = false;
        return;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _recenterQueued = false;
        if (!mounted || _closed || !_ready() || _layout == null) {
          return;
        }
        final step = _layout!.stride;
        if (step <= 1 || !_controller.hasClients) {
          return;
        }
        final pixels = _controller.position.pixels;
        final index = (pixels / step).round();
        if (index < widget.itemCount) {
          return;
        }
        final shifts = index ~/ widget.itemCount;
        final target = pixels - shifts * widget.itemCount * step;
        if ((pixels - target).abs() < 0.5 || target < -0.5) {
          return;
        }
        _holdIndex = true;
        _controller.jumpTo(
          target.clamp(0.0, _controller.position.maxScrollExtent),
        );
        _index = _indexFor(_layout!, _controller.position.pixels);
        _holdIndex = false;
        if (mounted) {
          setState(() {});
        }
      });
    });
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
    final index = _index.clamp(0, _maxIndex(layout));
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
    if (layout == null || _closed || !_canGo(direction, layout) || !_ready()) {
      return;
    }
    final current = _indexFor(layout, _controller.position.pixels);
    final targetIndex = (current + direction).clamp(0, _maxIndex(layout));
    final limit = widget.loop
        ? _controller.position.maxScrollExtent
        : _travelLimit(layout);
    final target = (targetIndex * layout.stride).clamp(0.0, limit);
    try {
      await _controller.animateTo(
        target,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    } catch (_) {
      return;
    }
    if (_closed || !mounted) {
      return;
    }
    _queueRecenter();
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
            child: MouseRegion(
              onEnter: (_) => _onHover(true),
              onExit: (_) => _onHover(false),
              child: Listener(
                onPointerDown: _onPointerDown,
                onPointerUp: _onPointerEnd,
                onPointerCancel: _onPointerEnd,
                child: Stack(
                  children: [
                    NotificationListener<Notification>(
                      onNotification: (notification) {
                        if (notification is ScrollEndNotification) {
                          _queueRecenter();
                        }
                        if (notification is ScrollMetricsNotification &&
                            mounted &&
                            !_holdIndex) {
                          setState(() {});
                        }
                        return false;
                      },
                      child: ScrollConfiguration(
                        behavior: ScrollConfiguration.of(context).copyWith(
                          scrollbars: false,
                          dragDevices: {
                            ...ScrollConfiguration.of(context).dragDevices,
                            PointerDeviceKind.mouse,
                          },
                        ),
                        child: ListView.builder(
                          controller: _controller,
                          scrollDirection: Axis.horizontal,
                          physics: _ItemSnapPhysics(
                            stride: _stride,
                            parent: const ClampingScrollPhysics(),
                          ),
                          padding: EdgeInsets.zero,
                          scrollCacheExtent: ScrollCacheExtent.pixels(
                            _repeats(layout) ? layout.stride : 800,
                          ),
                          itemExtent: layout.stride,
                          itemCount: _slotCount(layout),
                          itemBuilder: (context, index) {
                            final logical = _repeats(layout)
                                ? index % widget.itemCount
                                : index;
                            return Padding(
                              padding: EdgeInsets.only(right: widget.gap),
                              child: SizedBox(
                                key: AppKeys.carouselItem(widget.id, index),
                                width: layout.itemWidth,
                                height: widget.height,
                                child: widget.itemBuilder(context, logical),
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
            ),
          ),
        );
        if (!widget.showDots) {
          return carousel;
        }
        final repeating = _repeats(layout);
        final pages = repeating ? math.max(1, widget.itemCount) : layout.stops;
        final leading = _ready()
            ? _indexFor(layout, _controller.position.pixels)
            : _index;
        final current = repeating
            ? leading % pages
            : leading.clamp(0, pages - 1);
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
        backgroundColor: Theme.of(context).colorScheme.surface,
        foregroundColor: Theme.of(context).colorScheme.primary,
        minimumSize: const Size(44, 44),
        fixedSize: const Size(44, 44),
        side: BorderSide(color: Theme.of(context).colorScheme.outline),
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
    final scheme = Theme.of(context).colorScheme;
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
              color: index == current ? scheme.tertiary : scheme.outlineVariant,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: index == current ? scheme.onTertiary : scheme.outline,
              ),
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
