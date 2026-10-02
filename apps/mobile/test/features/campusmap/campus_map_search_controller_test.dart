// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:campus_koethen/features/campusmap/presentation/campus_map_search_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('query, text and focus are cleared together after a selection', () {
    final CampusMapSearchController controller = CampusMapSearchController();
    addTearDown(controller.dispose);
    int changes = 0;
    controller.addListener(() => changes++);

    controller.textController.text = 'A 1.01';
    controller.updateQuery('A 1.01');
    controller.clearAfterSelection();

    expect(controller.query, isEmpty);
    expect(controller.textController.text, isEmpty);
    expect(controller.focusNode.hasFocus, isFalse);
    expect(changes, 2);
  });
}
