// Campus Köthen App · AGPL-3.0-only
// Copyright © 2026 Leviora Studio and Jona Loreen Sommer

import 'package:flutter/foundation.dart';

/// Serialises manual course refreshes and exposes their visible state.
class MoodleCourseRefreshController extends ChangeNotifier {
  bool _refreshing = false;
  Object? _error;
  bool _disposed = false;

  bool get refreshing => _refreshing;
  Object? get error => _error;

  Future<void> run(Future<void> Function() refresh) async {
    if (_refreshing) return;
    _refreshing = true;
    _error = null;
    _notifyListeners();
    try {
      await refresh();
    } catch (error) {
      _error = error;
    } finally {
      _refreshing = false;
      _notifyListeners();
    }
  }

  void _notifyListeners() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
