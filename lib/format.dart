import 'package:intl/intl.dart';

String money(double v, String symbol) {
  final f = NumberFormat.currency(symbol: symbol, decimalDigits: 2);
  return f.format(v);
}

String num2(double v) {
  if (v == v.roundToDouble()) return v.toStringAsFixed(0);
  return v.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
}
