part of '../order_creation_dialog.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Shared Widgets & Helpers — Inline quantity/copy fields, formatQuantity
// ─────────────────────────────────────────────────────────────────────────────

String _formatQuantity(double qty) {
  if (qty == qty.toInt()) {
    return qty.toInt().toString();
  }
  return qty.toStringAsFixed(3).replaceAll(RegExp(r'\.?0+$'), '');
}

class _InlineQuantityField extends StatefulWidget {
  final double quantity;
  final ValueChanged<double> onChanged;
  final VoidCallback? onRemove;
  final bool hasBorder;
  const _InlineQuantityField({
    required this.quantity,
    required this.onChanged,
    this.onRemove,
    this.hasBorder = true,
  });

  @override
  State<_InlineQuantityField> createState() => _InlineQuantityFieldState();
}

class _InlineQuantityFieldState extends State<_InlineQuantityField> {
  late TextEditingController _controller;
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _formatQuantity(widget.quantity));
    _focusNode = FocusNode();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(_InlineQuantityField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.quantity != widget.quantity && !_focusNode.hasFocus) {
      _controller.text = _formatQuantity(widget.quantity);
    }
  }

  void _onFocusChange() {
    if (_focusNode.hasFocus) {
      _controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _controller.text.length,
      );
    } else {
      _submitValue();
    }
  }

  void _submitValue() {
    final text = _controller.text.replaceAll(',', '.');
    final val = double.tryParse(text);
    if (val != null) {
      if (val <= 0.0001) {
        if (widget.onRemove != null) {
          widget.onRemove!();
        } else {
          widget.onChanged(0.0);
        }
      } else {
        widget.onChanged(val);
      }
    } else {
      _controller.text = _formatQuantity(widget.quantity);
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 58,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: widget.hasBorder ? Border.all(color: _kBorder) : null,
      ),
      child: TextField(
        controller: _controller,
        focusNode: _focusNode,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textAlign: TextAlign.center,
        style: const TextStyle(
            fontWeight: FontWeight.w800, fontSize: 13, color: _kText),
        maxLines: 1,
        decoration: const InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.zero,
          border: InputBorder.none,
        ),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'^\d*[.,]?\d*')),
        ],
        onSubmitted: (_) {
          _submitValue();
          _focusNode.unfocus();
        },
      ),
    );
  }
}

class _InlineCopyCountField extends StatefulWidget {
  final int value;
  final ValueChanged<int> onChanged;

  const _InlineCopyCountField({
    required this.value,
    required this.onChanged,
  });

  @override
  State<_InlineCopyCountField> createState() => _InlineCopyCountFieldState();
}

class _InlineCopyCountFieldState extends State<_InlineCopyCountField> {
  late TextEditingController _controller;
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value.toString());
    _focusNode = FocusNode();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(_InlineCopyCountField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value && !_focusNode.hasFocus) {
      _controller.text = widget.value.toString();
    }
  }

  void _onFocusChange() {
    if (_focusNode.hasFocus) {
      _controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _controller.text.length,
      );
    } else {
      _submitValue();
    }
  }

  void _submitValue() {
    final val = int.tryParse(_controller.text);
    if (val != null && val >= 1) {
      widget.onChanged(val);
    } else {
      _controller.text = widget.value.toString();
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const Color bgColor = Colors.white;
    const Color borderColor = _kBorder;
    const Color textColor = _kText;

    return Container(
      width: 36,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      child: TextField(
        controller: _controller,
        focusNode: _focusNode,
        enabled: true,
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        style: const TextStyle(
            fontSize: 13, fontWeight: FontWeight.bold, color: textColor),
        maxLines: 1,
        decoration: const InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.zero,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          disabledBorder: InputBorder.none,
          errorBorder: InputBorder.none,
          focusedErrorBorder: InputBorder.none,
          filled: false,
        ),
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
        ],
        onSubmitted: (_) {
          _submitValue();
          _focusNode.unfocus();
        },
      ),
    );
  }
}
