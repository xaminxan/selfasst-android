import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../models/message.dart';

class MessageBubble extends StatelessWidget {
  final Message message;
  final VoidCallback? onSaveSkill;

  const MessageBubble({super.key, required this.message, this.onSaveSkill});

  void _copyToClipboard(BuildContext context) {
    Clipboard.setData(ClipboardData(text: message.content));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制'), duration: Duration(seconds: 1)),
    );
  }

  void _showContextMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('复制'),
              onTap: () {
                Navigator.pop(ctx);
                _copyToClipboard(context);
              },
            ),
            if (message.role != 'user' && message.content.isNotEmpty && onSaveSkill != null)
              ListTile(
                leading: const Icon(Icons.auto_awesome),
                title: const Text('总结为 Skill'),
                subtitle: const Text('将这条回复保存为经验技能'),
                onTap: () {
                  Navigator.pop(ctx);
                  onSaveSkill!();
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == 'user';
    final isProcessing = message.status == 'processing' && message.content.isEmpty;

    return GestureDetector(
      onLongPress: () => _showContextMenu(context),
      child: Align(
        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.85,
          ),
          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
          decoration: BoxDecoration(
            color: isUser
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(isUser ? 16 : 4),
              bottomRight: Radius.circular(isUser ? 4 : 16),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isProcessing)
                _buildProcessingBubble(context)
              else if (!isUser && message.content.isNotEmpty)
                // Render markdown with code highlighting for assistant messages
                MarkdownBody(
                  data: _cleanContent(message.content),
                  selectable: true,
                  styleSheet: MarkdownStyleSheet(
                    p: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontSize: 15,
                      height: 1.5,
                    ),
                    code: TextStyle(
                      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    codeblockDecoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    h1: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface),
                    h2: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface),
                    h3: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface),
                    listBullet: TextStyle(color: Theme.of(context).colorScheme.primary),
                    blockquoteDecoration: BoxDecoration(
                      border: Border(left: BorderSide(color: Theme.of(context).colorScheme.primary, width: 3)),
                      color: Theme.of(context).colorScheme.surfaceContainerLow,
                    ),
                    blockquotePadding: const EdgeInsets.fromLTRB(12, 4, 8, 4),
                    horizontalRuleDecoration: BoxDecoration(
                      border: Border(top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant))),
                  ),
                )
              else if (isUser)
                SelectableText(
                  message.content,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onPrimary,
                    fontSize: 15,
                    height: 1.4,
                  ),
                ),
              if (!isProcessing && message.content.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    _formatTime(message.createdAt),
                    style: TextStyle(
                      color: isUser
                          ? Theme.of(context).colorScheme.onPrimary.withValues(alpha: 0.7)
                          : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
                      fontSize: 11,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProcessingBubble(BuildContext context) {
    final steps = message.progressSteps;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 16, height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: Theme.of(context).colorScheme.primary),
            ),
            const SizedBox(width: 8),
            Text('思考中...', style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
              fontSize: 14, fontStyle: FontStyle.italic,
            )),
          ],
        ),
        if (steps.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final step in steps.take(6))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('• ', style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.primary)),
                        Flexible(
                          child: Text(
                            step.length > 80 ? '${step.substring(0, 80)}...' : step,
                            style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (steps.length > 6)
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Text(
                      '... 还有 ${steps.length - 6} 步',
                      style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4)),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  /// Defense-in-depth: strip agent internals if any slip past server clean.
  String _cleanContent(String content) {
    var cleaned = content;
    cleaned = cleaned.replaceAll(
      RegExp(r'<(thinking|think|summary|history|tool_use|tool_result|tool_call|file_content)>[\s\S]*?</\1>',
          caseSensitive: false),
      '',
    );
    cleaned = cleaned.replaceAll(RegExp(r'\[(Output|Cache|Debug|WORKING MEMORY|SYSTEM)\][^\n]*\n?'), '');
    cleaned = cleaned.replaceAll(RegExp(r'\*{0,2}LLM Running[^\n]*\n?'), '');
    cleaned = cleaned.replaceAll(RegExp(r'\*{0,2}Turn \d+[^\n]*\n?'), '');
    cleaned = cleaned.replaceAll(RegExp(r'^🛠️\s*.*$', multiLine: true), '');
    cleaned = cleaned.replaceAll(RegExp(r'^📥\s*args:.*$', multiLine: true), '');
    cleaned = cleaned.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return cleaned.trim();
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final msgDate = DateTime(dt.year, dt.month, dt.day);
    final time = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    if (msgDate == today) return time;
    return '${dt.month}/${dt.day} $time';
  }
}