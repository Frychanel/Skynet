import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// ======================================================
//  Sky Neural Engine.net  -  Chat con DeepSeek
// ======================================================

const String kApiUrl = 'https://api.deepseek.com/chat/completions';
const String kModel = 'deepseek-chat';
const String kPrefKey = 'deepseek_api_key';

const String kSystemPrompt =
    'Eres Sky Neural Engine, un asistente con personalidad madura, '
    'directa y leal. Tratas al usuario como "hermano" (nunca como "amo"). '
    'Respondes en el idioma en que te hablen, claro y sin rodeos.';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SkyApp());
}

class SkyApp extends StatelessWidget {
  const SkyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sky Neural Engine',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorSchemeSeed: Colors.cyan,
        useMaterial3: true,
      ),
      home: const ChatScreen(),
    );
  }
}

class ChatMessage {
  final String role; // 'user' | 'assistant'
  final String content;
  final bool isError;
  ChatMessage(this.role, this.content, {this.isError = false});
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final List<ChatMessage> _messages = [];
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  String _apiKey = '';
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadKey();
  }

  Future<void> _loadKey() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _apiKey = (prefs.getString(kPrefKey) ?? '').trim());
    if (_apiKey.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _askKey());
    }
  }

  Future<void> _saveKey(String key) async {
    // Limpia espacios, saltos de línea y comillas que se cuelan al pegar
    final clean = key.replaceAll(RegExp(r'[\s"\x27]'), '');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kPrefKey, clean);
    setState(() => _apiKey = clean);
  }

  Future<void> _askKey() async {
    final ctrl = TextEditingController(text: _apiKey);
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Llave de DeepSeek'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(hintText: 'sk-...'),
          autocorrect: false,
          enableSuggestions: false,
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await _saveKey(ctrl.text);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _loading) return;

    if (_apiKey.isEmpty) {
      _askKey();
      return;
    }

    setState(() {
      _messages.add(ChatMessage('user', text));
      _input.clear();
      _loading = true;
    });
    _scrollDown();

    final reply = await _callDeepSeek();

    setState(() {
      _messages.add(reply);
      _loading = false;
    });
    _scrollDown();
  }

  Future<ChatMessage> _callDeepSeek() async {
    // Historial sin mensajes de error
    final history = _messages
        .where((m) => !m.isError)
        .map((m) => {'role': m.role, 'content': m.content})
        .toList();

    final body = jsonEncode({
      'model': kModel,
      'messages': [
        {'role': 'system', 'content': kSystemPrompt},
        ...history,
      ],
      'stream': false,
    });

    try {
      final res = await http
          .post(
            Uri.parse(kApiUrl),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $_apiKey',
            },
            body: body,
          )
          .timeout(const Duration(seconds: 60));

      final decoded = utf8.decode(res.bodyBytes);

      if (res.statusCode == 200) {
        final data = jsonDecode(decoded);
        final content = data['choices'][0]['message']['content'] as String;
        return ChatMessage('assistant', content.trim());
      }

      // Errores explicados
      String why;
      switch (res.statusCode) {
        case 401:
          why = 'Llave inválida. Revisa que esté bien copiada.';
          break;
        case 402:
          why = 'Sin saldo en DeepSeek. Revisa tu recarga en platform.deepseek.com.';
          break;
        case 422:
        case 400:
          why = 'Petición mal formada (modelo o formato).';
          break;
        case 429:
          why = 'Demasiadas peticiones. Espera un momento.';
          break;
        case 500:
        case 503:
          why = 'El servidor de DeepSeek está saturado o caído. Intenta luego.';
          break;
        default:
          why = 'Error inesperado.';
      }
      return ChatMessage(
        'assistant',
        'Error ${res.statusCode}: $why\n\n$decoded',
        isError: true,
      );
    } on SocketException catch (e) {
      return ChatMessage(
        'assistant',
        'Sin conexión: la app no pudo salir a internet.\n'
        'Revisa el permiso INTERNET en el AndroidManifest y tu red.\n\n$e',
        isError: true,
      );
    } on TimeoutException {
      return ChatMessage(
        'assistant',
        'Se tardó demasiado en responder (60 s). Intenta de nuevo.',
        isError: true,
      );
    } catch (e) {
      return ChatMessage('assistant', 'Error: $e', isError: true);
    }
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sky Neural Engine'),
        actions: [
          IconButton(
            icon: const Icon(Icons.key),
            tooltip: 'Cambiar llave',
            onPressed: _askKey,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Borrar chat',
            onPressed: () => setState(_messages.clear),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.all(12),
              itemCount: _messages.length + (_loading ? 1 : 0),
              itemBuilder: (context, i) {
                if (i == _messages.length) {
                  return const Padding(
                    padding: EdgeInsets.all(12),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  );
                }
                final m = _messages[i];
                final mine = m.role == 'user';
                return Align(
                  alignment:
                      mine ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.all(12),
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.8,
                    ),
                    decoration: BoxDecoration(
                      color: m.isError
                          ? Colors.red.shade900
                          : mine
                              ? Colors.cyan.shade800
                              : Colors.grey.shade800,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: SelectableText(m.content),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      minLines: 1,
                      maxLines: 5,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        hintText: 'Escribe, hermano...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton.filled(
                    icon: const Icon(Icons.send),
                    onPressed: _loading ? null : _send,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
