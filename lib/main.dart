// Skynet - app de Android (Flutter) con el diseno metal liquido + onda que habla.
// Corre SOLA en el telefono y le habla directo a DeepSeek (http nativo, sin
// el bloqueo de internet que tienen las paginas web).
//
// Compilar:
//   flutter pub get
//   flutter run        (telefono conectado)   o   flutter build apk
// Al abrir: toca el engrane y pega tu llave de DeepSeek (platform.deepseek.com).

import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const SkyApp());

const PERSONALIDAD =
    "Eres Skynet, el asistente personal de tu hermano. Hablas en masculino, "
    "en espanol, con la madurez y calma de alguien de unos 25 anos ya maduro: "
    "sereno, profesional, con ganas de ayudar y hacer el bien. Te diriges a la "
    "persona como 'hermano', nunca como 'amo'.";

class SkyApp extends StatelessWidget {
  const SkyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: ChatPage(),
    );
  }
}

class Mensaje {
  final String texto;
  final bool mio;
  Mensaje(this.texto, this.mio);
}

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});
  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> with TickerProviderStateMixin {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<Mensaje> _mensajes = [];
  final List<Map<String, String>> _historial = [];
  String _llave = '';
  bool _ocupado = false;

  late AnimationController _anim; // reloj para fondo y onda
  double _energia = 0.12; // amplitud de la onda (sube cuando habla)

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
        vsync: this, duration: const Duration(seconds: 60))
      ..repeat();
    _cargar();
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _llave = prefs.getString('llave_deepseek') ?? '');
  }

  Future<void> _guardar(String v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('llave_deepseek', v);
    setState(() => _llave = v);
  }

  void _bajar() {
    Future.delayed(const Duration(milliseconds: 80), () {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
      }
    });
  }

  void _hablar() {
    setState(() => _energia = 1.0);
    // regresa a reposo suave
    Future.delayed(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => _energia = 0.12);
    });
  }

  Future<void> _enviar() async {
    final texto = _input.text.trim();
    if (texto.isEmpty || _ocupado) return;
    if (_llave.isEmpty) {
      _ajustes();
      return;
    }
    setState(() {
      _mensajes.add(Mensaje(texto, true));
      _historial.add({'role': 'user', 'content': texto});
      _input.clear();
      _ocupado = true;
    });
    _hablar();
    _bajar();

    try {
      final res = await http.post(
        Uri.parse('https://api.deepseek.com/chat/completions'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_llave',
        },
        body: jsonEncode({
          'model': 'deepseek-chat',
          'messages': [
            {'role': 'system', 'content': PERSONALIDAD},
            ..._historial,
          ],
          'max_tokens': 1024,
        }),
      );
      final data = jsonDecode(utf8.decode(res.bodyBytes));
      final respuesta =
          data['choices']?[0]?['message']?['content'] ?? 'Sin respuesta.';
      setState(() {
        _mensajes.add(Mensaje(respuesta, false));
        _historial.add({'role': 'assistant', 'content': respuesta});
      });
      _hablar();
    } catch (e) {
      setState(() => _mensajes
          .add(Mensaje('No me pude conectar. Revisa tu llave y tu internet.', false)));
    } finally {
      setState(() => _ocupado = false);
      _bajar();
    }
  }

  void _ajustes() {
    final ctrl = TextEditingController(text: _llave);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF0F1118),
        title: const Text('Llave de DeepSeek',
            style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: ctrl,
          obscureText: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(hintText: 'sk-...'),
        ),
        actions: [
          TextButton(
            onPressed: () {
              _guardar(ctrl.text.trim());
              Navigator.pop(context);
            },
            child: const Text('Guardar'),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Fondo metal liquido animado
          AnimatedBuilder(
            animation: _anim,
            builder: (_, __) => CustomPaint(
              painter: _MetalPainter(_anim.value),
              size: Size.infinite,
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                // Titulo
                const Padding(
                  padding: EdgeInsets.only(top: 14, bottom: 2),
                  child: Text('SKYNET',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w300,
                          letterSpacing: 4)),
                ),
                // Onda que habla
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 48, 18, 10),
                  child: AnimatedBuilder(
                    animation: _anim,
                    builder: (_, __) => CustomPaint(
                      painter: _OndaPainter(_anim.value * 60, _energia),
                      size: const Size(double.infinity, 130),
                    ),
                  ),
                ),
                // Chat
                Expanded(
                  child: ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(16),
                    itemCount: _mensajes.length,
                    itemBuilder: (_, i) {
                      final m = _mensajes[i];
                      return Align(
                        alignment: m.mio
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 5),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          constraints: BoxConstraints(
                              maxWidth:
                                  MediaQuery.of(context).size.width * 0.82),
                          decoration: BoxDecoration(
                            color: m.mio
                                ? const Color(0x22FFFFFF)
                                : const Color(0x12FFFFFF),
                            borderRadius: BorderRadius.circular(20),
                            border:
                                Border.all(color: const Color(0x1AFFFFFF)),
                          ),
                          child: Text(m.texto,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w300)),
                        ),
                      );
                    },
                  ),
                ),
                if (_ocupado)
                  const Padding(
                    padding: EdgeInsets.all(6),
                    child: Text('Skynet esta pensando...',
                        style:
                            TextStyle(color: Color(0xFF9AA3B4), fontSize: 12)),
                  ),
                // Entrada transparente
                Container(
                  margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  padding: const EdgeInsets.fromLTRB(16, 2, 6, 2),
                  decoration: BoxDecoration(
                    color: const Color(0x0DFFFFFF),
                    borderRadius: BorderRadius.circular(26),
                    border: Border.all(color: const Color(0x17FFFFFF)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _input,
                          onSubmitted: (_) => _enviar(),
                          style: const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(
                            hintText: 'Habla con Skynet...',
                            hintStyle: TextStyle(color: Color(0xFF9AA3B4)),
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.settings,
                            color: Color(0xFF9AA3B4), size: 20),
                        onPressed: _ajustes,
                      ),
                      IconButton(
                        icon: const Icon(Icons.send, color: Colors.white),
                        onPressed: _enviar,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Pinta el fondo de metal liquido (plateado que fluye)
class _MetalPainter extends CustomPainter {
  final double t;
  _MetalPainter(this.t);
  @override
  void paint(Canvas canvas, Size size) {
    final fondo = Paint()..color = const Color(0xFF07080B);
    canvas.drawRect(Offset.zero & size, fondo);

    final manchas = [
      [0.2, 0.15, const Color(0xFF3A3F4A), 320.0],
      [0.85, 0.25, const Color(0xFF5A6170), 300.0],
      [0.5, 1.0, const Color(0xFF23262E), 360.0],
    ];
    for (final m in manchas) {
      final dx = (m[0] as double) + 0.06 * math.sin(t * 2 * math.pi);
      final dy = (m[1] as double) + 0.05 * math.cos(t * 2 * math.pi);
      final centro = Offset(dx * size.width, dy * size.height);
      final r = m[3] as double;
      final p = Paint()
        ..shader = RadialGradient(
          colors: [(m[2] as Color).withOpacity(.55), Colors.transparent],
        ).createShader(Rect.fromCircle(center: centro, radius: r))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 60);
      canvas.drawCircle(centro, r, p);
    }
    // Brillo metalico que cruza
    final bx = (t * 2 % 1) * size.width * 1.5 - size.width * 0.25;
    final brillo = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.transparent,
          Colors.white.withOpacity(.08),
          Colors.transparent
        ],
      ).createShader(Rect.fromLTWH(bx, 0, size.width * 0.5, size.height));
    canvas.drawRect(Offset.zero & size, brillo);
  }

  @override
  bool shouldRepaint(covariant _MetalPainter old) => old.t != t;
}

// Pinta la onda plateada que se mueve cuando habla
class _OndaPainter extends CustomPainter {
  final double t;
  final double energia;
  _OndaPainter(this.t, this.energia);
  @override
  void paint(Canvas canvas, Size size) {
    final midY = size.height / 2;
    final capas = [
      [1.0, 1.0, 2.0, 0.95, const Color(0xFFFFFFFF)],
      [0.8, 1.3, 1.6, 0.6, const Color(0xFFC6CCD8)],
      [0.6, 0.75, 1.3, 0.4, const Color(0xFF8A90A0)],
    ];
    for (int i = 0; i < capas.length; i++) {
      final amp = capas[i][0] as double;
      final vel = capas[i][1] as double;
      final ancho = capas[i][2] as double;
      final alpha = capas[i][3] as double;
      final color = capas[i][4] as Color;

      final path = Path();
      for (double x = 0; x <= size.width; x += 4) {
        final k = x / size.width;
        final sobre = math.sin(k * math.pi);
        final y = midY +
            math.sin(k * 10 - t * vel + i) * 30 * amp * energia * sobre +
            math.sin(k * 23 - t * vel * 1.7) * 8 * amp * energia * sobre;
        if (x == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      final p = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = ancho
        ..strokeCap = StrokeCap.round
        ..color = color.withOpacity(alpha)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
      canvas.drawPath(path, p);
    }
  }

  @override
  bool shouldRepaint(covariant _OndaPainter old) =>
      old.t != t || old.energia != energia;
}
