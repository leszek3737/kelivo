abstract interface class MarkdownSettings {
  bool get enableMathRendering;
  bool get enableDollarLatex;
  String? get codeFontFamily;
  bool get codeFontIsGoogle;
  String? get appFontFamily;
  bool get appFontIsGoogle;
  bool get mobileCodeBlockWrap;
  bool get autoCollapseCodeBlock;
  int get autoCollapseCodeBlockLines;
}
