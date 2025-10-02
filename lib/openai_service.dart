import 'dart:async';
import 'dart:convert';

import 'package:avaremp/storage.dart';
import 'package:http/http.dart' as http;

class OpenAIService {

  final String apiKey;
  final String model;

  OpenAIService(this.apiKey, this.model);

  static OpenAIService fromSettings() {
    final String key = Storage().settings.getOpenAIKey();
    final String model = Storage().settings.getOpenAIModel();
    return OpenAIService(key, model);
  }

  Future<String> chat(List<Map<String, String>> messages) async {
    if (apiKey.isEmpty) {
      throw Exception("OpenAI API key is not set");
    }
    final Uri uri = Uri.parse('https://api.openai.com/v1/chat/completions');
    final Map<String, dynamic> body = {
      'model': model,
      'messages': messages,
      'temperature': 0.7,
    };
    final http.Response resp = await http
        .post(
          uri,
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 60));

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      try {
        final Map<String, dynamic> data = jsonDecode(resp.body) as Map<String, dynamic>;
        final String message = (data['error']?['message'] ?? resp.reasonPhrase ?? 'Unknown error').toString();
        throw Exception(message);
      } catch (_) {
        throw Exception('HTTP ${resp.statusCode}: ${resp.reasonPhrase}');
      }
    }

    final Map<String, dynamic> data = jsonDecode(resp.body) as Map<String, dynamic>;
    final List<dynamic> choices = data['choices'] as List<dynamic>;
    if (choices.isEmpty) {
      return '';
    }
    final Map<String, dynamic> message = choices.first['message'] as Map<String, dynamic>;
    return (message['content'] ?? '').toString();
  }
}

