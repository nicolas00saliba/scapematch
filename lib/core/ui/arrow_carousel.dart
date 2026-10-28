import 'package:flutter/material.dart';
import 'package:scapematch/app/theme.dart';
import 'package:scapematch/core/ui/app_keys.dart';

/// Faixa horizontal com swipe e setas que avançam uma página.
///
/// A seta some na ponta. O clique funciona com mouse, sem arrastar.
class ArrowCarousel extends StatefulWidget {
  const ArrowCarousel({
    super.key,
    required this.id,
    required this.height,
    required this.itemCount,
    required this.itemBuilder,
    this.gap = 12,
    this.showDots = false,
  });

  final String id;
  final double height;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final double gap;
  final bool showDots;

  @override
  State<ArrowCarousel> createState() => _ArrowCarouselState();
}

class _ArrowCarouselState extends State<ArrowCarousel> {
  final _controller = ScrollController();

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

  bool _canGo(int direction) {
    if (!_controller.hasClients ||
        !_controller.position.hasViewportDimension ||
        widget.itemCount == 0) {
      return false;
    }
    final position = _controller.position;
    if (position.maxScrollExtent <= 0) {
      return false;
    }
    if (direction < 0) {
      return position.pixels > 1;
    }
    return position.pixels < position.maxScrollExtent - 1;
  }

  Future<void> _page(int direction) async {
    if (!_canGo(direction)) {
      return;
    }
    final position = _controller.position;
    final target = (position.pixels + (direction * position.viewportDimension))
        .clamp(0.0, position.maxScrollExtent);
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
          ListView.separated(
            controller: _controller,
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.zero,
            itemCount: widget.itemCount,
            separatorBuilder: (context, index) => SizedBox(width: widget.gap),
            itemBuilder: widget.itemBuilder,
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        carousel,
        const SizedBox(height: 8),
        _Dots(controller: _controller, itemCount: widget.itemCount),
      ],
    );
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
  const _Dots({required this.controller, required this.itemCount});

  final ScrollController controller;
  final int itemCount;

  @override
  Widget build(BuildContext context) {
    final pages = _pageCount();
    final current = _currentPage(pages);
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

  int _pageCount() {
    if (!controller.hasClients || !controller.position.hasViewportDimension) {
      return 1;
    }
    final view = controller.position.viewportDimension;
    if (view <= 0) {
      return 1;
    }
    final total = controller.position.maxScrollExtent + view;
    final count = (total / view).ceil();
    if (count < 1) {
      return 1;
    }
    return count;
  }

  int _currentPage(int pages) {
    if (!controller.hasClients || !controller.position.hasViewportDimension) {
      return 0;
    }
    final view = controller.position.viewportDimension;
    if (view <= 0) {
      return 0;
    }
    final page = (controller.position.pixels / view).round();
    if (page < 0) {
      return 0;
    }
    if (page >= pages) {
      return pages - 1;
    }
    return page;
  }
}
