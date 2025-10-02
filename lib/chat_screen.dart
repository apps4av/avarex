import 'package:avaremp/app_settings.dart';
import 'package:avaremp/constants.dart';
import 'package:avaremp/openai_service.dart';
import 'package:avaremp/progress_button_message_input_widget.dart';
import 'package:avaremp/storage.dart';
import 'package:flutter/material.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<StatefulWidget> createState() => ChatScreenState();
}

class ChatScreenState extends State<ChatScreen> {

  final TextEditingController _controller = TextEditingController();
  final List<Map<String, String>> _messages = [];
  bool _sending = false;
  String _error = '';

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppSettings settings = Storage().settings;
    final bool missingKey = settings.getOpenAIKey().isEmpty;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Constants.appBarBackgroundColor,
        title: const Text('AI Chat'),
      ),
      body: Column(
        children: <Widget>[
          if (missingKey)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: <Widget>[
                  const Expanded(
                    child: Text(
                      'OpenAI API key is not set. Configure to start chatting.',
                    ),
                  ),
                  TextButton(
                    onPressed: _openSettingsDialog,
                    child: const Text('Configure'),
                  )
                ],
              ),
            ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _messages.length,
              itemBuilder: (BuildContext context, int index) {
                final Map<String, String> msg = _messages[index];
                final bool isUser = msg['role'] == 'user';
                return Align(
                  alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isUser ? theme.colorScheme.primary : theme.colorScheme.surfaceVariant,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      msg['content'] ?? '',
                      style: TextStyle(
                        color: isUser ? Colors.white : theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          if (_error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(_error, style: const TextStyle(color: Colors.red)),
              ),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: <Widget>[
                  IconButton(
                    onPressed: _openSettingsDialog,
                    icon: const Icon(Icons.settings),
                    tooltip: 'Chat settings',
                  ),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      minLines: 1,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        hintText: 'Type a message...',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onSubmitted: (_) => _onSend(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _sending
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : IconButton(
                          onPressed: _onSend,
                          icon: const Icon(Icons.send),
                          tooltip: 'Send',
                        ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openSettingsDialog() {
    final AppSettings settings = Storage().settings;
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          content: ProgressButtonMessageInputWidget(
            'OpenAI Settings',
            'Model',
            settings.getOpenAIModel(),
            'API Key',
            settings.getOpenAIKey(),
            'Save',
            (List<String> args) async {
              try {
                await settings.setOpenAIModel(args[0]);
                await settings.setOpenAIKey(args[1]);
                return '';
              } catch (e) {
                return e.toString();
              }
            },
            (bool ok, String model, String key) {
              if (ok) {
                setState(() {});
                Navigator.of(context).pop();
              }
            },
            'Saved',
          ),
        );
      },
    );
  }

  Future<void> _onSend() async {
    final String text = _controller.text.trim();
    if (text.isEmpty || _sending) {
      return;
    }
    setState(() {
      _error = '';
      _sending = true;
      _messages.add({'role': 'user', 'content': text});
      _controller.clear();
    });

    try {
      final OpenAIService service = OpenAIService.fromSettings();
      final String reply = await service.chat(_messages);
      setState(() {
        _messages.add({'role': 'assistant', 'content': reply});
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
        });
      }
    }
  }
}

