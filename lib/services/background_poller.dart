import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import '../main.dart';

class BackgroundPoller {
  static Timer? _timer;
  static Set<String> _pendingIds = {};
  static bool _isPolling = false;
  // FIX #3: SSE-active tracking
  static final Set<String> _sseActiveIds = {};

  /// Mark a msgId as being handled by SSE (poller will skip it)
  static void markSseActive(String msgId) => _sseActiveIds.add(msgId);

  /// Unmark a msgId from SSE-active set
  static void unmarkSseActive(String msgId) => _sseActiveIds.remove(msgId);

  /// Start the background poller
  static void start() {
    _loadPendingIds();
    _adjustInterval();
  }

  /// Stop the background poller
  static void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Load pending message IDs from persistent storage
  static Future<void> _loadPendingIds() async {
    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList('pending_msg_ids') ?? [];
    _pendingIds = ids.toSet();
  }

  /// Save pending message IDs to persistent storage
  static Future<void> _savePendingIds() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('pending_msg_ids', _pendingIds.toList());
  }

  /// Add a message ID to the pending queue
  static void addPending(String msgId) {
    _pendingIds.add(msgId);
    _savePendingIds();
    _adjustInterval();
  }

  /// Remove a message ID from the pending queue
  static void removePending(String msgId) {
    _pendingIds.remove(msgId);
    _savePendingIds();
    _adjustInterval();
  }

  /// Check if there are pending messages
  static bool hasPending() => _pendingIds.isNotEmpty;

  /// Get the set of pending message IDs
  static Set<String> getPendingIds() => Set.unmodifiable(_pendingIds);

  /// Adjust polling interval based on pending state
  static void _adjustInterval() {
    _timer?.cancel();
    final interval = _pendingIds.isNotEmpty
        ? const Duration(seconds: 5)
        : const Duration(seconds: 30);
    _timer = Timer.periodic(interval, (_) => _poll());
  }

  /// Poll for new messages — both pending replies and server-initiated messages.
  static Future<void> _poll() async {
    if (_isPolling) return;
    _isPolling = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      final baseUrl = prefs.getString('server_url') ?? 'http://10.10.10.200:8001';
      final token = prefs.getString('api_token') ?? 'ga-dev-token-change-me';
      final headers = {'Authorization': 'Bearer $token'};

      // ── 1. Check pending replies (messages sent from this phone) ──
      if (_pendingIds.isNotEmpty) {
        for (final msgId in _pendingIds.toList()) {
          // FIX #3: Skip messages being handled by SSE
          if (_sseActiveIds.contains(msgId)) continue;

          try {
            final resp = await http.get(
              Uri.parse('$baseUrl/v1/chat/$msgId'),
              headers: headers,
            ).timeout(const Duration(seconds: 10));

            if (resp.statusCode == 200) {
              final data = jsonDecode(resp.body);
              final status = data['status'];
              final content = data['content'] ?? '';

              if (status == 'delivered' || status == 'failed') {
                if (content.isNotEmpty) {
                  final preview = content.length > 80
                      ? '${content.substring(0, 80)}...'
                      : content;
                  await showNotification('GenericAgent', preview);
                }
                removePending(msgId);
              }
            }
          } catch (e) {
            debugPrint('background poll pending error: $e');
          }
        }
      }

      // ── 2. Check for new server messages (other clients / scheduled tasks) ──
      final lastNotifiedId = prefs.getString('last_notified_msg_id') ?? '';
      try {
        final resp = await http.get(
          Uri.parse('$baseUrl/v1/history?limit=20'),
          headers: headers,
        ).timeout(const Duration(seconds: 10));

        if (resp.statusCode == 200) {
          final data = jsonDecode(resp.body);
          final messages = List<Map<String, dynamic>>.from(data['messages'] ?? []);
          // Server returns messages oldest-first.
          // The last element is the newest message in the batch.
          final newestId = messages.isNotEmpty
              ? (messages.last['id'] as String? ?? '')
              : '';

          if (newestId.isNotEmpty) {
            bool hitLastNotified = false;

            // Walk from oldest to newest; stop at the last notified message.
            for (final msg in messages) {
              final id = msg['id'] as String? ?? '';
              if (id.isEmpty) continue;
              if (id == lastNotifiedId) {
                hitLastNotified = true;
                break;
              }

              // Notify for new assistant messages that are delivered
              if (msg['role'] == 'assistant' &&
                  (msg['content'] as String? ?? '').isNotEmpty &&
                  msg['status'] == 'delivered') {
                final content = msg['content'] as String;
                final preview = content.length > 80
                    ? '${content.substring(0, 80)}...'
                    : content;
                await showNotification('GenericAgent', preview);
              }
            }

            // Remember the newest message so we don't re-notify.
            // On first run (lastNotifiedId is empty) always save.
            // On subsequent runs, save only if the last notified message
            // was not found in this batch (i.e. all messages are new).
            if (!hitLastNotified || lastNotifiedId.isEmpty) {
              await prefs.setString('last_notified_msg_id', newestId);
            }
          }
        }
      } catch (e) {
        debugPrint('background poll history error: $e');
      }
    } catch (e) {
      debugPrint('background poll outer error: $e');
    } finally {
      _isPolling = false;
    }
  }
}