import 'dart:convert';

import 'package:avaremp/storage.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class ChatGptScreen extends StatefulWidget {
  const ChatGptScreen({super.key});

  @override
  State<ChatGptScreen> createState() => _ChatGptScreenState();
}

class _ChatMessage {
  final String role; // "user" | "assistant"
  final String content;

  _ChatMessage({required this.role, required this.content});
}

class _ChatSessionState {
  final List<_ChatMessage> messages = [];

  void addUserMessage(String text) {
    messages.add(_ChatMessage(role: "user", content: text));
  }

  void addAssistantMessage(String text) {
    messages.add(_ChatMessage(role: "assistant", content: text));
  }
}

class _ChatGptScreenState extends State<ChatGptScreen> {
  final TextEditingController _inputController = TextEditingController();
  final FocusNode _inputFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  final _ChatSessionState _session = _ChatSessionState();
  bool _isSending = false;

  @override
  void dispose() {
    _inputController.dispose();
    _inputFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final String text = _inputController.text.trim();
    if (text.isEmpty || _isSending) return;

    final String apiKey = Storage().settings.getOpenAiApiKey();
    if (apiKey.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Set OpenAI API key first.')),
      );
      return;
    }

    setState(() {
      _isSending = true;
      _session.addUserMessage(text);
      _inputController.clear();
    });

    await _scrollToBottom();

    try {
      final String model = Storage().settings.getChatModel();
      final uri = Uri.parse('https://api.openai.com/v1/chat/completions');

      final bool isGpt5 = model.toLowerCase().replaceAll('-', '') == 'gpt5' || model.toLowerCase().startsWith('gpt-5');

      final Map<String, dynamic> payload = {
        'model': model,
        'messages': _session.messages
            .map((m) => {
                  'role': m.role,
                  'content': m.content,
                })
            .toList(),
      };

      if (isGpt5) {
        payload['max_completion_tokens'] = 600;
        // temperature not supported for gpt-5; use default server-side
      } else {
        payload['max_tokens'] = 600;
        payload['temperature'] = 0.2;
      }

      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode(payload),
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> body = jsonDecode(response.body);
        final String reply = body['choices']?[0]?['message']?['content']?.toString() ?? 'No response';
        setState(() {
          _session.addAssistantMessage(reply);
        });
      } else {
        setState(() {
          _session.addAssistantMessage('Error ${response.statusCode}: ${response.body}');
        });
      }
    } catch (e) {
      setState(() {
        _session.addAssistantMessage('Error: $e');
      });
    } finally {
      setState(() {
        _isSending = false;
      });
      await _scrollToBottom();
    }
  }

  Future<void> _scrollToBottom() async {
    await Future.delayed(const Duration(milliseconds: 100));
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  Future<void> _setApiKeyDialog() async {
    final TextEditingController controller = TextEditingController(text: Storage().settings.getOpenAiApiKey());
    final formKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('OpenAI API Key'),
          content: Form(
            key: formKey,
            child: TextFormField(
              controller: controller,
              decoration: const InputDecoration(
                hintText: 'sk-... (kept locally)'
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'API key cannot be empty';
                }
                return null;
              },
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Storage().settings.setOpenAiApiKey(controller.text.trim());
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('API key saved locally.')),
                  );
                }
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _setModelDialog() async {
    final TextEditingController controller = TextEditingController(text: Storage().settings.getChatModel());
    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Chat Model'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(hintText: 'e.g. gpt5'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Storage().settings.setChatModel(controller.text.trim());
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Model updated.')),
                );
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ChatGPT'),
        actions: [
          IconButton(
            tooltip: 'Set API key',
            onPressed: _setApiKeyDialog,
            icon: const Icon(Icons.vpn_key),
          ),
          IconButton(
            tooltip: 'Chat model',
            onPressed: _setModelDialog,
            icon: const Icon(Icons.tune),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(12),
              itemCount: _session.messages.length,
              itemBuilder: (context, index) {
                final m = _session.messages[index];
                final bool isUser = m.role == 'user';
                return Align(
                  alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: isUser
                        ? () {
                            _inputController.text = m.content;
                            _inputController.selection = TextSelection.fromPosition(
                              TextPosition(offset: _inputController.text.length),
                            );
                            _inputFocusNode.requestFocus();
                          }
                        : null,
                    child: Container(
                      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isUser ? Theme.of(context).colorScheme.primary : Theme.of(context).cardColor,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: SelectableText(
                        m.content,
                        style: TextStyle(
                          color: isUser ? Colors.white : Theme.of(context).textTheme.bodyMedium?.color,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      focusNode: _inputFocusNode,
                      controller: _inputController,
                      minLines: 1,
                      maxLines: 6,
                      decoration: const InputDecoration(
                        hintText: 'Type your message...',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _isSending ? null : _send,
                    icon: _isSending ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send),
                    label: const Text('Send'),
                  )
                ],
              ),
            ),
          )
        ],
      ),
    );
  }
}
