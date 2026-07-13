part of '../sales_page.dart';

class _AnimatedCartTab extends ConsumerStatefulWidget {
  const _AnimatedCartTab();

  @override
  ConsumerState<_AnimatedCartTab> createState() => _AnimatedCartTabState();
}

class _AnimatedCartTabState extends ConsumerState<_AnimatedCartTab> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  int _lastCount = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _animation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween<double>(begin: 1.0, end: 1.3), weight: 30),
      TweenSequenceItem(tween: Tween<double>(begin: 1.3, end: 0.9), weight: 30),
      TweenSequenceItem(tween: Tween<double>(begin: 0.9, end: 1.0), weight: 40),
    ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cartCount = ref.watch(salesFlowProvider.select(
      (state) => state.cartQuantities.values.fold(0, (a, b) => a + b),
    ));

    if (cartCount > _lastCount) {
      _controller.forward(from: 0.0);
    }
    _lastCount = cartCount;

    return ScaleTransition(
      scale: _animation,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          const Icon(Icons.shopping_basket_rounded, size: 20),
          if (cartCount > 0)
            Positioned(
              top: -6,
              right: -8,
              child: Container(
                width: 16,
                height: 16,
                decoration: const BoxDecoration(
                  color: Color(0xFFDC2626), // _kRed
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    '$cartCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
