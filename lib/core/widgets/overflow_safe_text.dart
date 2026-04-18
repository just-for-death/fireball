import 'package:flutter/material.dart';

/// One-line label used in [Row]s, [ListTile]s, and nav chrome — avoids layout overflow.
class FireballLineText extends StatelessWidget {
  const FireballLineText(
    this.data, {
    super.key,
    this.style,
    this.textAlign,
    this.semanticsLabel,
  });

  final String data;
  final TextStyle? style;
  final TextAlign? textAlign;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    return Text(
      data,
      style: style,
      textAlign: textAlign,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      softWrap: false,
      semanticsLabel: semanticsLabel,
    );
  }
}
