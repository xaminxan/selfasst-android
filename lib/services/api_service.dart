import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/io.dart';

class ApiService {
  String baseUrl;
  String token;

  ApiService({required this.baseUrl, required this.token});

  IOWebSocketChannel? _wsChannel;
  final _messageController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;

  Map<String, String> get headers => {
    'Authorization': 'Bearer $token',
    'Content-Type': 'application/json',
  };

  String get baseUrlPath => baseUrl;

  Future<bool> healthCheck() async {
    try {
      final resp = await http.get(
        Uri.parse('$baseUrl/v1/ping'),
        headers: headers,
      ).timeout(const Duration(seconds: 5));
      return resp.statusCode == 200;
    } catch (e) {
      debugPrint('healthCheck error: $e');
      return false;
    }
  }

  /// Send message and get message_id immediately
  Future<Map<String, dynamic>?> sendMessage(String message, {String? conversationId, String mode = ''}) async {
    try {
      final body = jsonEncode({
        'message': message,
        if (conversationId != null) 'conversation_id': conversationId,
        if (mode.isNotEmpty) 'mode': mode,
      });

      final resp = await http.post(
        Uri.parse('$baseUrl/v1/chat'),
        headers: headers,
        body: body,
      ).timeout(const Duration(seconds: 30));

      if (resp.statusCode == 200) {
        return jsonDecode(resp.body);
      }
      return null;
    } catch (e) {
      debugPrint('sendMessage error: $e');
      return null;
    }
  }

  /// Poll for response until status is 'delivered' or 'failed'
  Future<Map<String, dynamic>?> pollResponse(String msgId, {int maxWaitSeconds = 300}) async {
    final deadline = DateTime.now().add(Duration(seconds: maxWaitSeconds));

    while (DateTime.now().isBefore(deadline)) {
      try {
        final resp = await http.get(
          Uri.parse('$baseUrl/v1/chat/$msgId'),
          headers: headers,
        ).timeout(const Duration(seconds: 10));

        if (resp.statusCode == 200) {
          final data = jsonDecode(resp.body);
          final status = data['status'];

          if (status == 'delivered' || status == 'failed') {
            return data;
          }
        }
      } catch (e) {
        debugPrint('pollResponse error: $e');
      }

      // Wait 2 seconds before next poll
      await Future.delayed(const Duration(seconds: 2));
    }
    return null;
  }

  Future<void> connectWebSocket() async {
    try {
      final wsUrl = baseUrl.replaceFirst('http', 'ws');
      final ws = await io.WebSocket.connect(
        '$wsUrl/ws',
        headers: {'Authorization': 'Bearer $token'},
      );
      _wsChannel = IOWebSocketChannel(ws);

      _wsChannel!.stream.listen(
        (data) {
          try {
            final json = jsonDecode(data);
            _messageController.add(json);
          } catch (e) {
            debugPrint('WebSocket JSON parse error: $e');
          }
        },
        onError: (error) {
          debugPrint('WebSocket error: $error');
          Future.delayed(const Duration(seconds: 5), connectWebSocket);
        },
        onDone: () {
          Future.delayed(const Duration(seconds: 5), connectWebSocket);
        },
      );
    } catch (e) {
      debugPrint('WebSocket connect error: $e');
      Future.delayed(const Duration(seconds: 5), connectWebSocket);
    }
  }

  void disconnectWebSocket() {
    _wsChannel?.sink.close();
    _wsChannel = null;
  }

  Future<bool> configureLLM({
    String? apiKey, String? apiBase, String? model,
    double? temperature, int? maxTokens,
  }) async {
    try {
      final body = <String, dynamic>{};
      if (apiKey != null) body['api_key'] = apiKey;
      if (apiBase != null) body['api_base'] = apiBase;
      if (model != null) body['model'] = model;
      if (temperature != null) body['temperature'] = temperature;
      if (maxTokens != null) body['max_tokens'] = maxTokens;

      final resp = await http.post(
        Uri.parse('$baseUrl/v1/config/llm'),
        headers: headers,
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 10));

      return resp.statusCode == 200;
    } catch (e) {
      debugPrint('configureLLM error: $e');
      return false;
    }
  }

  /// Save a skill (L3) to the server
  Future<bool> saveSkill(String name, String content, {String description = ''}) async {
    try {
      final resp = await http.post(
        Uri.parse('$baseUrl/v1/skill/save'),
        headers: headers,
        body: jsonEncode({
          'name': name,
          'content': content,
          'description': description,
        }),
      ).timeout(const Duration(seconds: 10));
      return resp.statusCode == 200;
    } catch (e) {
      debugPrint('saveSkill error: $e');
      return false;
    }
  }

  /// Send a message and stream the response via SSE
  /// Returns a stream of text deltas as they arrive from the server.
  Stream<String> sendMessageStream(String message, {String? conversationId, String mode = ''}) {
    final controller = StreamController<String>.broadcast();

    try {
      final body = jsonEncode({
        'message': message,
        if (conversationId != null) 'conversation_id': conversationId,
        if (mode.isNotEmpty) 'mode': mode,
      });

      http.post(
        Uri.parse('$baseUrl/v1/chat/stream'),
        headers: headers,
        body: body,
      ).then((resp) {
        if (resp.statusCode == 200) {
          final lines = resp.body.split('\n');
          for (final line in lines) {
            if (line.startsWith('data: ')) {
              try {
                final data = jsonDecode(line.substring(6));
                final type = data['type'];
                final content = data['content'] ?? '';
                if (type == 'delta') {
                  controller.add(content);
                } else if (type == 'replace') {
                  // Server rewrote cleaned content (e.g. new turn) — full replace
                  controller.add('[REPLACE]$content');
                } else if (type == 'progress') {
                  // Progress step update — prefix so UI can distinguish
                  controller.add('[PROGRESS]$content');
                } else if (type == 'done') {
                  // Prefer server's cleaned final text over accumulated stream noise
                  controller.add('[DONE]$content');
                } else if (type == 'error') {
                  controller.addError(Exception(content.isEmpty ? 'SSE error' : content));
                }
              } catch (e) {
                debugPrint('SSE JSON parse error: $e');
              }
            }
          }
          controller.close();
        } else {
          controller.addError(Exception('HTTP ${resp.statusCode}'));
          controller.close();
        }
      }).catchError((e) {
        controller.addError(e);
        controller.close();
      });
    } catch (e) {
      controller.addError(e);
      controller.close();
    }

    return controller.stream;
  }

  Future<List<Map<String, dynamic>>> getHistory({String? conversationId, String mode = '', int limit = 50}) async {
    try {
      final uri = Uri.parse('$baseUrl/v1/history').replace(
        queryParameters: {
          if (conversationId != null) 'conversation_id': conversationId,
          if (mode.isNotEmpty) 'mode': mode,
          'limit': limit.toString(),
        },
      );
      final resp = await http.get(uri, headers: headers).timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        return List<Map<String, dynamic>>.from(data['messages'] ?? []);
      }
      return [];
    } catch (e) {
      debugPrint('getHistory error: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getConversations() async {
    try {
      final resp = await http.get(
        Uri.parse('$baseUrl/v1/conversations'),
        headers: headers,
      ).timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        return List<Map<String, dynamic>>.from(data['conversations'] ?? []);
      }
      return [];
    } catch (e) {
      debugPrint('getConversations error: $e');
      return [];
    }
  }

  void dispose() {
    disconnectWebSocket();
    _messageController.close();
  }
}
