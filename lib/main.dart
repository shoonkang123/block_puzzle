import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

class Piece {
  final List<Point<int>> cells; // (x,y)
  final int colorId;
  Piece(this.cells, this.colorId);
  int get w => cells.map((p) => p.x).reduce(max) + 1;
  int get h => cells.map((p) => p.y).reduce(max) + 1;
}

final List<Color> kColors = [
  Colors.red,
  Colors.pink,
  Colors.purple,
  Colors.orange,
  Colors.cyan,
];

final List<List<Point<int>>> kShapes = [
  [Point(0, 0)],
  [Point(0, 0), Point(1, 0)],
  [Point(0, 0), Point(0, 1)],
  [Point(0, 0), Point(1, 0), Point(2, 0)],
  [Point(0, 0), Point(0, 1), Point(0, 2)],
  [Point(0, 0), Point(1, 0), Point(0, 1)],
  [Point(0, 0), Point(1, 0), Point(1, 1)],
  [Point(0, 0), Point(1, 0), Point(0, 1), Point(1, 1)],
  [Point(0, 0), Point(0, 1), Point(0, 2), Point(1, 2)],
];

class GamePage extends StatefulWidget {
  const GamePage({super.key});
  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage> {
  static const int n = 8;

  // ✅ 너가 확정한 값
  static const double LEFT = 14;
  static const double TOP = 14;
  static const double RIGHT = 14;
  static const double BOTTOM = 14;
  static const double GAP = 2;

  final List<List<int>> board = List.generate(n, (_) => List.filled(n, 0));

  final GlobalKey _rootKey = GlobalKey(); // ✅ 화면 로컬 변환
  final GlobalKey _boardKey = GlobalKey();
  final GlobalKey _trayKey = GlobalKey();

  ui.Image? tileImg;
  final _rng = Random();
  late List<Piece> pieces;

  int? draggingIndex;
  Offset? dragPosGlobal;

  // ✅ “손가락이 피스를 잡은 위치” 오프셋
  Offset? grabOffsetInPiece; // piece local 좌표 (px)

  @override
  void initState() {
    super.initState();
    pieces = _roll3();
    _loadTile();
  }

  List<Piece> _roll3() => List.generate(3, (_) => _randomPiece());
  Piece _randomPiece() {
    final shape = kShapes[_rng.nextInt(kShapes.length)];
    final colorId = 1 + _rng.nextInt(kColors.length);
    return Piece(shape, colorId);
  }

  Future<void> _loadTile() async {
    final data = await rootBundle.load('assets/images/tile.png');
    final bytes = data.buffer.asUint8List();
    final img = await decodeImageFromList(bytes);
    setState(() => tileImg = img);
  }

  Rect _gridRect(Size boardSize) => Rect.fromLTRB(
    LEFT,
    TOP,
    boardSize.width - RIGHT,
    boardSize.height - BOTTOM,
  );

  // ===== 트레이에서 어떤 피스 눌렀는지 + grabOffset 계산 =====
  int? _hitTestTrayAndGrab(Offset globalPos) {
    final trayBox = _trayKey.currentContext?.findRenderObject() as RenderBox?;
    if (trayBox == null) return null;

    final local = trayBox.globalToLocal(globalPos);
    final size = trayBox.size;

    final slotW = size.width / 3.0;
    final idx = (local.dx / slotW).floor();
    if (idx < 0 || idx > 2) return null;

    final slot = Rect.fromLTWH(idx * slotW, 0, slotW, size.height);
    final piece = pieces[idx];

    final maxDim = max(piece.w, piece.h);
    final pTile = min(slot.width, slot.height) / (maxDim + 1.4);
    const g = 2.0;

    final pw = piece.w * pTile + (piece.w - 1) * g;
    final ph = piece.h * pTile + (piece.h - 1) * g;
    final origin = Offset(slot.center.dx - pw / 2, slot.center.dy - ph / 2);
    final rect = Rect.fromLTWH(origin.dx, origin.dy, pw, ph);

    if (!rect.contains(local)) return null;

    // ✅ 손가락이 피스 내부 어디를 잡았는지 저장
    grabOffsetInPiece = local - origin; // piece local(px)
    return idx;
  }

  void _onPanStart(DragStartDetails d) {
    final idx = _hitTestTrayAndGrab(d.globalPosition);
    if (idx == null) return;

    setState(() {
      draggingIndex = idx;
      dragPosGlobal = d.globalPosition;
    });
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (draggingIndex == null) return;
    setState(() => dragPosGlobal = d.globalPosition);
  }

  void _onPanEnd(DragEndDetails d) {
    if (draggingIndex == null) return;

    final idx = draggingIndex!;
    final piece = pieces[idx];

    bool placed = false;

    final boardBox = _boardKey.currentContext?.findRenderObject() as RenderBox?;
    if (boardBox != null && dragPosGlobal != null) {
      final boardLocal = boardBox.globalToLocal(dragPosGlobal!);
      final boardSize = boardBox.size;
      final grid = _gridRect(boardSize);

      final tile = (grid.width - GAP * (n - 1)) / n;
      final pw = piece.w * tile + (piece.w - 1) * GAP;
      final ph = piece.h * tile + (piece.h - 1) * GAP;

      // ✅ “중심”이 아니라 grabOffset 기준으로 origin 계산
      final grab = grabOffsetInPiece ?? Offset(pw / 2, ph / 2);
      final origin = boardLocal - grab;

      final snap = _snapOriginToCell(origin, piece, grid);
      if (snap != null) {
        final (baseRow, baseCol) = snap;
        if (_canPlace(piece, baseRow, baseCol)) {
          _place(piece, baseRow, baseCol);
          placed = true;
        }
      }
    }

    setState(() {
      draggingIndex = null;
      dragPosGlobal = null;
      grabOffsetInPiece = null;

      if (placed) pieces[idx] = _randomPiece();
    });
  }

  // ✅ origin(피스 좌상단)을 그리드에 스냅
  (int, int)? _snapOriginToCell(Offset origin, Piece piece, Rect grid) {
    final tile = (grid.width - GAP * (n - 1)) / n;
    final step = tile + GAP;

    final dx = origin.dx - grid.left;
    final dy = origin.dy - grid.top;

    // ✅ round/floor 취향인데, 정확히 붙이려면 round가 보통 더 좋음
    final col = (dx / step).round();
    final row = (dy / step).round();

    if (row < 0 || col < 0) return null;
    if (row + piece.h > n || col + piece.w > n) return null;

    return (row, col);
  }

  bool _canPlace(Piece piece, int baseRow, int baseCol) {
    for (final cell in piece.cells) {
      final r = baseRow + cell.y;
      final c = baseCol + cell.x;
      if (board[r][c] != 0) return false;
    }
    return true;
  }

  void _place(Piece piece, int baseRow, int baseCol) {
    for (final cell in piece.cells) {
      board[baseRow + cell.y][baseCol + cell.x] = piece.colorId;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomSafe = MediaQuery.of(context).viewPadding.bottom;

    return Scaffold(
      body: GestureDetector(
        key: _rootKey,
        behavior: HitTestBehavior.opaque,
        onPanStart: _onPanStart,
        onPanUpdate: _onPanUpdate,
        onPanEnd: _onPanEnd,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset('assets/images/background.png', fit: BoxFit.cover),

            SafeArea(
              top: true,
              bottom: false,
              child: LayoutBuilder(
                builder: (context, cons) {
                  final boardSide =
                  min(cons.maxWidth * 0.98, cons.maxHeight * 0.66);

                  // ✅ 너가 원하는 위치
                  final boardTop = cons.maxHeight * 0.20;

                  final trayH = max(140.0, cons.maxHeight * 0.22);
                  final trayBottom = bottomSafe + 6;

                  return Stack(
                    children: [
                      Positioned(
                        top: boardTop,
                        left: (cons.maxWidth - boardSide) / 2,
                        width: boardSide,
                        height: boardSide,
                        child: Container(
                          key: _boardKey,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.asset('assets/images/board.png',
                                  fit: BoxFit.fill),
                              CustomPaint(
                                painter: BoardPainter(
                                  board: board,
                                  tileImg: tileImg,
                                  left: LEFT,
                                  top: TOP,
                                  right: RIGHT,
                                  bottom: BOTTOM,
                                  gap: GAP,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: trayBottom,
                        height: trayH,
                        child: Container(
                          key: _trayKey,
                          child: CustomPaint(
                            painter: TrayPainter(pieces: pieces, tileImg: tileImg),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),

            // ✅ 드래그 프리뷰: 이제 “화면 로컬 좌표”로 그려서 안 사라짐
            if (draggingIndex != null && dragPosGlobal != null)
              Positioned.fill(
                child: CustomPaint(
                  painter: DragOverlayPainter(
                    rootKey: _rootKey,
                    globalPos: dragPosGlobal!,
                    piece: pieces[draggingIndex!],
                    tileImg: tileImg,
                    boardKey: _boardKey,
                    grabOffsetInPiece: grabOffsetInPiece,
                    left: LEFT,
                    top: TOP,
                    right: RIGHT,
                    bottom: BOTTOM,
                    gap: GAP,
                    n: n,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class BoardPainter extends CustomPainter {
  final List<List<int>> board;
  final ui.Image? tileImg;
  final double left, top, right, bottom, gap;

  BoardPainter({
    required this.board,
    required this.tileImg,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    required this.gap,
  });

  static const double trim = 0.0; // tile.png 여백 있으면 0.08~0.12

  @override
  void paint(Canvas canvas, Size size) {
    const n = 8;

    final grid = Rect.fromLTRB(left, top, size.width - right, size.height - bottom);
    final tile = (grid.width - gap * (n - 1)) / n;
    final step = tile + gap;

    // 빈칸 가이드 (맞추기 쉬움)
    final emptyStroke = Paint()
      ..color = Colors.white.withValues(alpha: 0.12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (int r = 0; r < n; r++) {
      for (int c = 0; c < n; c++) {
        final x = grid.left + c * step;
        final y = grid.top + r * step;
        canvas.drawRect(Rect.fromLTWH(x, y, tile, tile), emptyStroke);
      }
    }

    // 놓인 블록(색 반영)
    for (int r = 0; r < n; r++) {
      for (int c = 0; c < n; c++) {
        final id = board[r][c];
        if (id == 0) continue;
        final color = kColors[(id - 1) % kColors.length];
        final x = grid.left + c * step;
        final y = grid.top + r * step;
        _drawTile(canvas, Rect.fromLTWH(x, y, tile, tile), color);
      }
    }
  }

  void _drawTile(Canvas canvas, Rect dst, Color tint) {
    final img = tileImg;
    if (img == null) {
      canvas.drawRect(dst, Paint()..color = tint);
      return;
    }
    final w = img.width.toDouble();
    final h = img.height.toDouble();
    final trimX = w * trim;
    final trimY = h * trim;
    final src = Rect.fromLTWH(trimX, trimY, w - trimX * 2, h - trimY * 2);

    final paint = Paint()..colorFilter = ColorFilter.mode(tint, BlendMode.modulate);
    canvas.drawImageRect(img, src, dst, paint);
  }

  @override
  bool shouldRepaint(covariant BoardPainter oldDelegate) => true;
}

class TrayPainter extends CustomPainter {
  final List<Piece> pieces;
  final ui.Image? tileImg;
  TrayPainter({required this.pieces, required this.tileImg});

  static const double trim = 0.0;

  @override
  void paint(Canvas canvas, Size size) {
    final slotW = size.width / 3;

    for (int i = 0; i < 3; i++) {
      final slot = Rect.fromLTWH(i * slotW, 0, slotW, size.height);
      final piece = pieces[i];

      final maxDim = max(piece.w, piece.h);
      final pTile = min(slot.width, slot.height) / (maxDim + 1.4);
      const g = 2.0;

      final pw = piece.w * pTile + (piece.w - 1) * g;
      final ph = piece.h * pTile + (piece.h - 1) * g;
      final origin = Offset(slot.center.dx - pw / 2, slot.center.dy - ph / 2);

      for (final cell in piece.cells) {
        final x = origin.dx + cell.x * (pTile + g);
        final y = origin.dy + cell.y * (pTile + g);
        _drawTile(canvas, Rect.fromLTWH(x, y, pTile, pTile),
            kColors[(piece.colorId - 1) % kColors.length]);
      }
    }
  }

  void _drawTile(Canvas canvas, Rect dst, Color tint) {
    final img = tileImg;
    if (img == null) {
      canvas.drawRect(dst, Paint()..color = tint);
      return;
    }
    final w = img.width.toDouble();
    final h = img.height.toDouble();
    final trimX = w * trim;
    final trimY = h * trim;
    final src = Rect.fromLTWH(trimX, trimY, w - trimX * 2, h - trimY * 2);

    final paint = Paint()..colorFilter = ColorFilter.mode(tint, BlendMode.modulate);
    canvas.drawImageRect(img, src, dst, paint);
  }

  @override
  bool shouldRepaint(covariant TrayPainter oldDelegate) => true;
}

class DragOverlayPainter extends CustomPainter {
  final GlobalKey rootKey;
  final Offset globalPos;
  final Piece piece;
  final ui.Image? tileImg;
  final GlobalKey boardKey;
  final Offset? grabOffsetInPiece;

  final double left, top, right, bottom, gap;
  final int n;

  DragOverlayPainter({
    required this.rootKey,
    required this.globalPos,
    required this.piece,
    required this.tileImg,
    required this.boardKey,
    required this.grabOffsetInPiece,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    required this.gap,
    required this.n,
  });

  static const double trim = 0.0;

  @override
  void paint(Canvas canvas, Size size) {
    final rootBox = rootKey.currentContext?.findRenderObject() as RenderBox?;
    if (rootBox == null) return;

    // ✅ global -> 화면 로컬
    final screenPos = rootBox.globalToLocal(globalPos);

    // 보드의 tile 크기에 맞춰 프리뷰도 동일 크기로
    final boardBox = boardKey.currentContext?.findRenderObject() as RenderBox?;
    if (boardBox == null) return;

    final boardSize = boardBox.size;
    final grid = Rect.fromLTRB(left, top, boardSize.width - right, boardSize.height - bottom);
    final tile = (grid.width - gap * (n - 1)) / n;

    final pw = piece.w * tile + (piece.w - 1) * gap;
    final ph = piece.h * tile + (piece.h - 1) * gap;

    final grab = grabOffsetInPiece ?? Offset(pw / 2, ph / 2);
    final origin = screenPos - grab;

    final tint = kColors[(piece.colorId - 1) % kColors.length].withValues(alpha: 0.90);

    for (final cell in piece.cells) {
      final x = origin.dx + cell.x * (tile + gap);
      final y = origin.dy + cell.y * (tile + gap);
      _drawTile(canvas, Rect.fromLTWH(x, y, tile, tile), tint);
    }
  }

  void _drawTile(Canvas canvas, Rect dst, Color tint) {
    final img = tileImg;
    if (img == null) {
      canvas.drawRect(dst, Paint()..color = tint);
      return;
    }
    final w = img.width.toDouble();
    final h = img.height.toDouble();
    final trimX = w * trim;
    final trimY = h * trim;
    final src = Rect.fromLTWH(trimX, trimY, w - trimX * 2, h - trimY * 2);

    final paint = Paint()..colorFilter = ColorFilter.mode(tint, BlendMode.modulate);
    canvas.drawImageRect(img, src, dst, paint);
  }

  @override
  bool shouldRepaint(covariant DragOverlayPainter oldDelegate) => true;
}
