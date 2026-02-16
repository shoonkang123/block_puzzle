import 'package:flutter/material.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: const GamePage(),
      theme: ThemeData(useMaterial3: true),
    );
  }
}

class GamePage extends StatefulWidget {
  const GamePage({super.key});
  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage> {
  static const int n = 8;

  final List<List<int>> board = List.generate(n, (_) => List.filled(n, 0));
  Rect? _gridRect;

  void _onTapDown(TapDownDetails d) {
    final rect = _gridRect;
    if (rect == null) return;

    final p = d.localPosition;
    if (!rect.contains(p)) return;

    final dx = p.dx - rect.left;
    final dy = p.dy - rect.top;

    const gap = BoardPainter.GAP;
    final tile = (rect.width - gap * (n - 1)) / n;
    final step = tile + gap;

    final col = (dx / step).floor();
    final row = (dy / step).floor();
    if (row < 0 || row >= n || col < 0 || col >= n) return;

    // 틈 클릭 방지(칸만 클릭)
    final inTileX = (dx - col * step) <= tile;
    final inTileY = (dy - row * step) <= tile;
    if (!inTileX || !inTileY) return;

    setState(() {
      board[row][col] = board[row][col] == 0 ? 1 : 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset('assets/images/background.png', fit: BoxFit.cover),
          SafeArea(
            child: Center(
              child: LayoutBuilder(
                builder: (context, cons) {
                  final side = cons.maxWidth * 0.98;

                  return GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTapDown: _onTapDown,
                    child: SizedBox(
                      width: side,
                      height: side,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.asset('assets/images/board.png', fit: BoxFit.fill),
                          CustomPaint(
                            painter: BoardPainter(
                              board: board,
                              onGridRect: (r) => _gridRect = r,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class BoardPainter extends CustomPainter {
  final List<List<int>> board;
  final ValueChanged<Rect> onGridRect;

  BoardPainter({
    required this.board,
    required this.onGridRect,
  });

  // ===========================
  // ✅ 여기 숫자만 조절하면 됨
  // ===========================
  static const double LEFT = 14;
  static const double TOP = 14;
  static const double RIGHT = 14;
  static const double BOTTOM = 14;

  // 칸 사이 틈(gap)
  static const double GAP = 2;

  // ✅ 디버그용: 빈 칸 테두리/채움 표시 ON/OFF
  static const bool SHOW_EMPTY_CELLS = true;

  @override
  void paint(Canvas canvas, Size size) {
    const int n = 8;

    final gridRect = Rect.fromLTRB(
      LEFT,
      TOP,
      size.width - RIGHT,
      size.height - BOTTOM,
    );
    onGridRect(gridRect);

    final tile = (gridRect.width - GAP * (n - 1)) / n;
    final step = tile + GAP;

    // (1) gridRect 자체 박스
    final debugRectPaint = Paint()
      ..color = Colors.green.withOpacity(0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRect(gridRect, debugRectPaint);

    // (2) ✅ 빈 칸들도 눈에 보이게: 각 칸 outline + 살짝 채움(반투명)
    if (SHOW_EMPTY_CELLS) {
      final emptyFill = Paint()
        ..color = Colors.white.withOpacity(0.04)
        ..style = PaintingStyle.fill;

      final emptyStroke = Paint()
        ..color = Colors.white.withOpacity(0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;

      for (int r = 0; r < n; r++) {
        for (int c = 0; c < n; c++) {
          final x = gridRect.left + c * step;
          final y = gridRect.top + r * step;
          final cellRect = Rect.fromLTWH(x, y, tile, tile);

          // 빈 칸도 보이게
          canvas.drawRect(cellRect, emptyFill);
          canvas.drawRect(cellRect, emptyStroke);
        }
      }
    }

    // (3) 채워진 칸(빨강)
    final fillPaint = Paint()..color = Colors.red.withOpacity(0.75);

    for (int r = 0; r < n; r++) {
      for (int c = 0; c < n; c++) {
        if (board[r][c] == 1) {
          final x = gridRect.left + c * step;
          final y = gridRect.top + r * step;
          canvas.drawRect(Rect.fromLTWH(x, y, tile, tile), fillPaint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant BoardPainter oldDelegate) => true;
}
