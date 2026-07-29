import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../main.dart';
import '../models/message.dart';
import '../services/api_service.dart';
import '../services/background_poller.dart';
import '../services/message_store.dart';
import '../widgets/message_bubble.dart';
import 'settings_screen.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _unreadDividerKey = GlobalKey();
  final _speech = stt.SpeechToText();
  bool _isListening = false;
  String _lastWords = '';
  ApiService? _api;
  List<Message> _messages = [];
  bool _isConnected = false;
  String? _conversationId;
  AppLifecycleState? _lastState;
  int _unreadCount = 0;
  int? _firstUnreadIndex;
  String? _lastSeenMessageId;
  bool _showUnreadBadge = false;
  final _messageStore = MessageStore();
  Timer? _syncTimer;
  Timer? _connectivityTimer;
  String? _responseCreatedAt;
  String _mode = ''; // '' for general, 'coding' for coding
  bool _isLoadingHistory = false;

  String get _modeKey => _mode.isEmpty ? 'general' : _mode;
  String get _modeLabel => _mode == 'coding' ? '编程助手' : '个人助手';
  IconData get _modeIcon => _mode == 'coding' ? Icons.code : Icons.person_outline;
  String get _placeholder => _mode == 'coding' ? '输入编程任务...' : '输入消息...';

  @override
  void initState() {
    super.initState();
    _lastState = AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    _loadLastSeen();
    _loadCachedMessages();
    _loadConfig();
    _syncTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) _syncMessages();
    });
  }

  Future<void> _loadCachedMessages() async {
    try {
      final cached = await _messageStore.getMessages(mode: _modeKey, limit: 100);
      if (cached.isNotEmpty && mounted) {
        setState(() => _messages = cached);
        _scrollToBottom(animate: false);
      }
    } catch (e) {
      debugPrint('_loadCachedMessages error: $e');
    }
  }

  Future<void> _saveMessage(Message msg) async {
    try {
      await _messageStore.insertMessage(msg, mode: _modeKey);
    } catch (e) {
      debugPrint('_saveMessage error: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lastState = state;
    if (state == AppLifecycleState.resumed) {
      _syncMessages();
    } else if (state == AppLifecycleState.paused) {
      _saveLastSeen();
    }
  }

  Future<void> _loadLastSeen() async {
    final prefs = await SharedPreferences.getInstance();
    _lastSeenMessageId = prefs.getString('last_seen_msg_id_$_modeKey');
  }

  Future<void> _saveLastSeen() async {
    if (_messages.isNotEmpty) {
      final lastMsg = _messages.last;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_seen_msg_id_$_modeKey', lastMsg.id);
      _lastSeenMessageId = lastMsg.id;
    }
  }

  void _markAllAsSeen() {
    _saveLastSeen();
    setState(() {
      _unreadCount = 0;
      _firstUnreadIndex = null;
      _showUnreadBadge = false;
    });
  }

  void _calculateUnread() {
    if (_lastSeenMessageId == null || _messages.isEmpty) {
      _unreadCount = 0;
      _firstUnreadIndex = null;
      _showUnreadBadge = false;
      return;
    }

    int seenIndex = -1;
    for (int i = _messages.length - 1; i >= 0; i--) {
      if (_messages[i].id == _lastSeenMessageId) {
        seenIndex = i;
        break;
      }
    }

    if (seenIndex < 0) {
      _unreadCount = 0;
      _firstUnreadIndex = null;
      _showUnreadBadge = false;
      return;
    }

    final newMessages = _messages.sublist(seenIndex + 1);
    final newAssistantMessages =
        newMessages.where((m) => m.role == 'assistant' && m.content.isNotEmpty).length;

    if (newAssistantMessages > 0) {
      _unreadCount = newAssistantMessages;
      _firstUnreadIndex = seenIndex + 1; // 指向第一条未读消息
      _showUnreadBadge = true;
    } else {
      _unreadCount = 0;
      _firstUnreadIndex = null;
      _showUnreadBadge = false;
    }
  }

  Future<void> _switchMode(String newMode) async {
    if (newMode == _mode) return;
    // Save state for current mode
    _saveLastSeen();
    setState(() {
      _mode = newMode;
      _messages = [];
      _conversationId = null;
      _responseCreatedAt = null;
      _unreadCount = 0;
      _showUnreadBadge = false;
      _isLoadingHistory = true;
    });
    // Load messages for new mode
    _loadLastSeen();
    _loadCachedMessages();
    await _syncMessages();
    if (mounted) setState(() => _isLoadingHistory = false);
  }

  Future<void> _loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final baseUrl = prefs.getString('server_url') ?? 'http://10.10.10.200:8001';
    final token = prefs.getString('api_token') ?? 'simon123';

    _api?.dispose();
    _api = ApiService(baseUrl: baseUrl, token: token);

    // Retry health check up to 5 times with 2s delay (handles slow DNS / server startup)
    _isConnected = false;
    for (int i = 0; i < 5; i++) {
      _isConnected = await _api!.healthCheck();
      if (_isConnected) break;
      await Future.delayed(const Duration(seconds: 2));
    }

    // If still disconnected, retry more aggressively: every 5s for 30s
    if (!_isConnected) {
      _retryConnect();
    }

    await _syncMessages();

    _api!.messageStream.listen((data) {
      if (data['type'] == 'message') {
        final msgData = data['data'];
        final msg = Message.fromMap(msgData);
        if (msg.content.isNotEmpty) {
          final exists = _messages.any((m) => m.id == msg.id);
          if (!exists) {
            BackgroundPoller.removePending(msg.id);
            setState(() => _messages.add(msg));
            _saveMessage(msg);
            _scrollToBottom();
            if (_lastState != AppLifecycleState.resumed && _lastState != null) {
              showNotification('GenericAgent',
                  msg.content.length > 80 ? '${msg.content.substring(0, 80)}...' : msg.content);
            }
          }
        }
      }
    });

    _api!.connectWebSocket();

    // Periodic connectivity check — every 10s, re-check if disconnected
    _connectivityTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
      if (!_isConnected && _api != null && mounted) {
        final ok = await _api!.healthCheck();
        if (ok && mounted) {
          setState(() => _isConnected = true);
          _api!.connectWebSocket();
        }
      }
    });

    setState(() {});
  }

  Future<void> _syncMessages() async {
    if (_api == null) return;
    try {
      final serverMsgs = await _api!.getHistory(conversationId: _conversationId, mode: _mode, limit: 100);
      // If the API call succeeded, the server is reachable
      if (!_isConnected && mounted) {
        setState(() => _isConnected = true);
        _api!.connectWebSocket();
      }
      if (serverMsgs.isNotEmpty && mounted) {
        final newMessages = serverMsgs
            .map((m) => Message.fromMap(m))
            .where((m) => m.content.isNotEmpty)
            .toList();

        final serverIds = newMessages.map((m) => m.id).toSet();
        final localOnly = _messages
            .where((m) => !serverIds.contains(m.id))
            .toList();

        setState(() {
          _messages = [...localOnly, ...newMessages];
          _messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        });

        try {
          await _messageStore.clearAll(mode: _modeKey);
          for (final msg in _messages) {
            await _messageStore.insertMessage(msg, mode: _modeKey);
          }
        } catch (e) {
          debugPrint('_syncMessages cache clear error: $e');
        }

        _calculateUnread();
        _scrollToBottom(animate: false);
      }
    } catch (e) {
      debugPrint('_syncMessages outer error: $e');
    }
  }

  /// Aggressive retry: health check every 5s for up to 30s
  void _retryConnect() {
    int attempts = 0;
    Timer.periodic(const Duration(seconds: 5), (timer) {
      attempts++;
      if (_isConnected || attempts > 6 || !mounted) {
        timer.cancel();
        return;
      }
      _api!.healthCheck().then((ok) {
        if (ok && mounted) {
          setState(() => _isConnected = true);
          _api!.connectWebSocket();
          timer.cancel();
        }
      });
    });
  }

  void _scrollToBottom({bool animate = true}) {
    void doScroll() {
      if (!mounted || !_scrollController.hasClients) return;
      final target = _scrollController.position.maxScrollExtent;
      if (animate) {
        _scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      } else {
        _scrollController.jumpTo(target);
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      doScroll();
      Future.delayed(const Duration(milliseconds: 50), doScroll);
      Future.delayed(const Duration(milliseconds: 200), doScroll);
    });
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _api == null) return;

    _controller.clear();
    _markAllAsSeen();

    final userMsg = Message(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      role: 'user',
      content: text,
      status: 'sent',
      createdAt: DateTime.now(),
    );
    setState(() => _messages.add(userMsg));
    _saveMessage(userMsg);
    _scrollToBottom();

    final result = await _api!.sendMessage(text, conversationId: _conversationId, mode: _mode);

    if (result == null) {
      final errMsg = Message(
        id: 'err_${DateTime.now().millisecondsSinceEpoch}',
        role: 'assistant',
        content: '发送失败，请检查连接。',
        status: 'failed',
        createdAt: DateTime.now(),
      );
      setState(() => _messages.add(errMsg));
      _saveMessage(errMsg);
      return;
    } else {
      _responseCreatedAt = result['created_at'] as String?;
      if (_responseCreatedAt != null) {
        try {
          final serverTime = DateTime.parse(_responseCreatedAt!);
          if (serverTime.isAfter(DateTime(2000))) {
            final updated = Message(
              id: userMsg.id,
              role: 'user',
              content: userMsg.content,
              status: userMsg.status,
              createdAt: serverTime.toLocal(),
            );
            final idx = _messages.indexWhere((m) => m.id == userMsg.id);
            if (idx >= 0) {
              setState(() => _messages[idx] = updated);
              _saveMessage(updated);
            }
          }
        } catch (e) {
          debugPrint('_sendMessage server time parse error: $e');
        }
      }
    }

    final msgId = result['message_id'];
    final userMsgId = result['user_msg_id'];
    _conversationId = result['conversation_id'];

    if (userMsgId != null) {
      final userIdx = _messages.indexWhere((m) => m.id == userMsg.id);
      if (userIdx >= 0) {
        final updatedUserMsg = Message(
          id: userMsgId,
          role: 'user',
          content: text,
          status: 'sent',
          createdAt: userMsg.createdAt,
        );
        setState(() => _messages[userIdx] = updatedUserMsg);
        _saveMessage(updatedUserMsg);
      }
    }

    final placeholder = Message(
      id: msgId,
      role: 'assistant',
      content: '',
      status: 'processing',
      createdAt: _responseCreatedAt != null
          ? DateTime.parse(_responseCreatedAt!).toLocal()
          : DateTime.now(),
    );
    setState(() => _messages.add(placeholder));
    _saveMessage(placeholder);
    _scrollToBottom();

    BackgroundPoller.addPending(msgId);
    _pollForResponse(msgId);
  }

  Future<void> _pollForResponse(String msgId) async {
    final deadline = DateTime.now().add(const Duration(seconds: 600));

    while (DateTime.now().isBefore(deadline) && mounted) {
      try {
        final httpResp = await http.get(
          Uri.parse('${_api!.baseUrlPath}/v1/chat/$msgId'),
          headers: _api!.headers,
        ).timeout(const Duration(seconds: 10));

        if (httpResp.statusCode == 200) {
          final data = jsonDecode(httpResp.body);
          final status = data['status'];

          if (status == 'delivered' || status == 'failed') {
            BackgroundPoller.removePending(msgId);
            if (mounted) {
              final content = data['content'] ?? '';
              final idx = _messages.indexWhere((m) => m.id == msgId);
              if (idx >= 0) {
                final polled = Message(
                  id: msgId,
                  role: 'assistant',
                  content: content.isEmpty ? 'No response received.' : content,
                  status: status,
                  createdAt: data['created_at'] != null
                      ? DateTime.parse(data['created_at']).toLocal()
                      : _responseCreatedAt != null
                          ? DateTime.parse(_responseCreatedAt!).toLocal()
                          : DateTime.now(),
                );
                setState(() => _messages[idx] = polled);
                _saveMessage(polled);
                _scrollToBottom();
                if (_lastState != AppLifecycleState.resumed && _lastState != null && content.isNotEmpty) {
                  showNotification('GenericAgent',
                      content.length > 80 ? '${content.substring(0, 80)}...' : content);
                }
              }
            }
            return;
          }

          // Update progress steps from polling response
          if (mounted) {
            final progress = data['progress'];
            if (progress != null) {
              final steps = progress['steps'];
              if (steps is List && steps.isNotEmpty) {
                final stepTexts = steps.map<String>((s) {
                  final icon = s['icon'] ?? '';
                  final text = s['text'] ?? '';
                  return '$icon $text';
                }).toList();
                final idx = _messages.indexWhere((m) => m.id == msgId);
                if (idx >= 0) {
                  final current = _messages[idx];
                  final updated = current.copyWith(progressSteps: stepTexts);
                  setState(() => _messages[idx] = updated);
                  _scrollToBottom();
                }
              }
            }
          }
        }
      } catch (e) {
        debugPrint('_pollForReply error: $e');
      }

      await Future.delayed(const Duration(seconds: 2));
    }

    // Timeout
    BackgroundPoller.removePending(msgId);
    if (mounted) {
      final idx = _messages.indexWhere((m) => m.id == msgId);
      if (idx >= 0) {
        final timeout = Message(
          id: msgId,
          role: 'assistant',
          content: '请求超时，请重试。',
          status: 'failed',
          createdAt: DateTime.now(),
        );
        setState(() => _messages[idx] = timeout);
        _saveMessage(timeout);
      }
    }
  }

  void _openSettings() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
    _loadConfig();
  }

  Future<void> _startListening() async {
    final available = await _speech.initialize();
    if (available) {
      try {
        await _speech.listen(
          onResult: (result) {
            setState(() {
              _lastWords = result.recognizedWords;
              _controller.text = _lastWords;
              _controller.selection = TextSelection.fromPosition(
                TextPosition(offset: _lastWords.length),
              );
            });
          },
          onDone: () {
            if (mounted) setState(() => _isListening = false);
          },
          listenFor: const Duration(seconds: 30),
          localeId: 'zh_CN',
        );
        setState(() => _isListening = true);
      } catch (e) {
        debugPrint('_startListening error: $e');
        if (mounted) setState(() => _isListening = false);
      }
    }
  }

  void _stopListening() {
    _speech.stop();
    setState(() => _isListening = false);
    if (_lastWords.isNotEmpty) {
      _sendMessage();
    }
  }

  Future<void> _showSaveSkillDialog(Message msg) async {
    final nameController = TextEditingController();
    final descController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('总结为 Skill'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Skill 名称',
                hintText: '例如：健康日报生成',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descController,
              decoration: const InputDecoration(
                labelText: '描述（可选）',
                hintText: '这个技能的作用是什么',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 8),
            Text(
              '内容将保存到 NAS 的 memory/ 目录下作为 L3 技能',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('保存')),
        ],
      ),
    );

    if (result == true && nameController.text.trim().isNotEmpty) {
      final ok = await _api?.saveSkill(
        nameController.text.trim(),
        msg.content,
        description: descController.text.trim(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ok == true ? 'Skill 已保存到 NAS' : '保存失败'),
            backgroundColor: ok == true ? Colors.green : Colors.red,
          ),
        );
      }
    }
    nameController.dispose();
    descController.dispose();
  }

  void _clearChat() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空聊天'),
        content: const Text('清空所有消息？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () async {
              setState(() => _messages.clear());
              await _messageStore.clearAll(mode: _modeKey);
              _markAllAsSeen();
              if (mounted) Navigator.pop(ctx);
            },
            child: const Text('清空'),
          ),
        ],
      ),
    );
  }

  void _jumpToUnread() {
    final ctx = _unreadDividerKey.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
        alignment: 0.2,
      );
      return;
    }
    _scrollToBottom(animate: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_modeIcon, size: 20, color: _mode == 'coding' ? Colors.green : Colors.blue),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => _switchMode(_mode == 'coding' ? '' : 'coding'),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _modeLabel,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.swap_horiz, size: 16, color: Colors.grey[600]),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: _isConnected ? Colors.green.withValues(alpha: 0.1) : Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _isConnected ? '已连接' : '未连接',
                style: TextStyle(fontSize: 10, color: _isConnected ? Colors.green : Colors.red),
              ),
            ),
          ],
        ),
        actions: [
          if (_showUnreadBadge && _unreadCount > 0)
            Center(
              child: GestureDetector(
                onTap: _jumpToUnread,
                child: Container(
                  margin: const EdgeInsets.only(right: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.arrow_upward, size: 14),
                      const SizedBox(width: 4),
                      Text('$_unreadCount', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
            ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _syncMessages, tooltip: '刷新'),
          IconButton(icon: const Icon(Icons.delete_outline), onPressed: _clearChat, tooltip: '清空'),
          IconButton(icon: const Icon(Icons.settings), onPressed: _openSettings, tooltip: '设置'),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _isLoadingHistory
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(_modeIcon, size: 64, color: Colors.grey[400]),
                        const SizedBox(height: 16),
                        Text(_modeLabel, style: TextStyle(fontSize: 18, color: Colors.grey[600])),
                        const SizedBox(height: 8),
                        Text(_isConnected ? '服务器已就绪' : '服务器未连接',
                            style: TextStyle(fontSize: 14, color: _isConnected ? Colors.green : Colors.red)),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _messages.length + (_showUnreadBadge && _firstUnreadIndex != null ? 1 : 0),
                    itemBuilder: (ctx, i) {
                      int msgIndex = i;
                      bool isDivider = false;

                      if (_showUnreadBadge && _firstUnreadIndex != null && i == _firstUnreadIndex! + 1) {
                        isDivider = true;
                        msgIndex = i - 1;
                      } else if (_showUnreadBadge && _firstUnreadIndex != null && i > _firstUnreadIndex! + 1) {
                        msgIndex = i - 1;
                      }

                      if (isDivider) {
                        return _buildUnreadDivider();
                      }

                      if (msgIndex >= _messages.length) {
                        return const SizedBox.shrink();
                      }

                      return MessageBubble(
                        message: _messages[msgIndex],
                        onSaveSkill: _messages[msgIndex].role == 'assistant' && _messages[msgIndex].content.isNotEmpty
                            ? () => _showSaveSkillDialog(_messages[msgIndex])
                            : null,
                      );
                    },
                  ),
          ),
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              boxShadow: [BoxShadow(blurRadius: 4, color: Colors.black.withValues(alpha: 0.1))],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      decoration: InputDecoration(
                        hintText: _placeholder,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                        filled: true,
                        fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      ),
                      maxLines: null,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 4),
                  _isListening
                      ? IconButton.filled(
                          onPressed: _stopListening,
                          icon: const Icon(Icons.stop, size: 20),
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.red,
                          ),
                        )
                      : IconButton(
                          onPressed: _startListening,
                          icon: const Icon(Icons.mic, size: 20),
                        ),
                  const SizedBox(width: 4),
                  IconButton.filled(onPressed: _sendMessage, icon: const Icon(Icons.send, size: 20)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUnreadDivider() {
    return Padding(
      key: _unreadDividerKey,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          const Expanded(child: Divider(thickness: 1)),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3)),
            ),
            child: Text(
              '$_unreadCount 条新消息',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
          const Expanded(child: Divider(thickness: 1)),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    _connectivityTimer?.cancel();
    _saveLastSeen();
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    _scrollController.dispose();
    _api?.dispose();
    super.dispose();
  }
}