// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter/material.dart';

/// Owns the text, focus and derived query state of the map search surface.
class CampusMapSearchController extends ChangeNotifier {
  CampusMapSearchController({
    TextEditingController? textController,
    FocusNode? focusNode,
  }) : textController = textController ?? TextEditingController(),
       focusNode = focusNode ?? FocusNode();

  final TextEditingController textController;
  final FocusNode focusNode;

  String _query = '';
  String get query => _query;

  void updateQuery(String value) {
    if (_query == value) return;
    _query = value;
    notifyListeners();
  }

  void clearAfterSelection() {
    textController.clear();
    focusNode.unfocus();
    updateQuery('');
  }

  @override
  void dispose() {
    textController.dispose();
    focusNode.dispose();
    super.dispose();
  }
}
