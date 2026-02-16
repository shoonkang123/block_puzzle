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

class Cell {
  final int r;
  final int c;
  const Cell(this.r, this.c);
}

class Piece {
  final List<Cell> cells;
  final Color color;
  const Piece({required this.cells, required this.color});

  int get w => cells.map((e) => e.c).reduce(max) + 1;
  int get h => cells.map((e) => e.r).reduce(max) + 1;
}

class GamePage extends StatefulWidget {
  const GamePage({super.key});
  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage> {
  static const int n = 8;

  final List<List<int>> board = List.generate(n, (_) => List.filled(n, 0));

  late List<Piece> pieces;
  ui.Image? tileImg;

  Rect? _gridRect;
  double _gridTile = 0;
  double _gridStep = 0;

  // 트레이 슬롯(화면 local 좌표 기준)
  final List<Rect> _traySlotRects = [Rect.zero, Rect.zero, Rect.zero];

  // 드래그 상태
  int? draggingIndex;
  Piece? draggingPiece;
  Offset? dragGlobalPos;

  // ✅ 손가락 가림 방지(더 위로)
  static const double fingerLift = 110;

  // ✅ 너가 확정한 보드 맞춤값
  static const double LEFT = 14;
  static const double TOP = 14;
  static const double RIGHT = 14;
  static const double BOTTOM = 14;
  static const double GAP = 2;

  // (옵션) 빈 칸 보이게
  static const bool SHOW_EMPTY_CELLS = true;

  final _rng = Random();

  @override
  void initState() {
    super.initState();
    pieces = List.generate(3, (_) => _randomPiece());
    _loadTile();
  }

  Future<void> _loadTile() async {
    final data = await rootBundle.load('assets/images/tile.png');
    final bytes = data.buffer.asUint8List();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    setState(() => tileImg = frame.image);
  }

  Piece _randomPiece() {
    final shapes = <List<Cell>>[
      [const Cell(0, 0)],
      [const Cell(0, 0), const Cell(0, 1)],
      [const Cell(0, 0), const Cell(1, 0)],
      [const Cell(0, 0), const Cell(0, 1), const Cell(0, 2)],
      [const Cell(0, 0), const Cell(1, 0), const Cell(2, 0)],
      [const Cell(0, 0), const Cell(0, 1), const Cell(1, 0), const Cell(1, 1)],
      [const Cell(0, 0), const Cell(1, 0), const Cell(2, 0), const Cell(2, 1)],
      [const Cell(0, 1), const Cell(1, 1), const Cell(2, 1), const Cell(2, 0)],
      [const Cell(0, 0), const Cell(0, 1), const Cell(1, 1), const Cell(2, 1)],
      [const Cell(0, 0), const Cell(0, 1), const Cell(1, 0)],
    ];

    final colors = <Color>[
      const Color(0xFFFF3B30),
      const Color(0xFFAF52DE),
      const Color(0xFF0A84FF),
      const Color(0xFFFF2D55),
      const Color(0xFF30D158),
      const Color(0xFFFF9F0A),
    ];

    return Piece(
      cells: shapes[_rng.nextInt(shapes.length)],
      color: colors[_rng.nextInt(colors.length)],
    );
  }

  // =========================
  // 드래그 시작/이동/종료
  // =========================
  void _onPanStart(DragStartDetails d) {
    // ✅ 트레이 슬롯에서 시작했는지
    final local = d.localPosition;
    for (int i = 0; i < 3; i++) {
      if (_traySlotRects[i].contains(local)) {
        setState(() {
          draggingIndex = i;
          draggingPiece = pieces[i];

          // ✅ 시작 순간부터 손가락 위로 뜨게 보이도록 globalPos 저장
          dragGlobalPos = d.globalPosition;
          // ✅ 트레이 슬롯은 즉시 비우기(숨김)
          // -> painter에서 hideIndex로 처리됨
        });
        return;
      }
    }
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (draggingPiece == null) return;
    setState(() => dragGlobalPos = d.globalPosition);
  }

  void _onPanEnd(DragEndDetails d) {
    if (draggingPiece == null || draggingIndex == null) return;

    final placed = _tryPlaceOnBoard(draggingPiece!, dragGlobalPos);

    setState(() {
      if (placed) {
        // ✅ 성공한 경우에만 새 블록 생성
        pieces[draggingIndex!] = _randomPiece();
      }
      // 실패면 원래 블록이 그대로 다시 보임(숨김 해제)
      draggingIndex = null;
      draggingPiece = null;
      dragGlobalPos = null;
    });
  }

  bool _tryPlaceOnBoard(Piece piece, Offset? globalPos) {
    final rect = _gridRect;
    if (rect == null || globalPos == null) return false;

    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return false;

    // ✅ global -> local
    final p = box.globalToLocal(globalPos);

    if (!rect.contains(p)) return false;

    final dx = p.dx - rect.left;
    final dy = p.dy - rect.top;

    final tile = _gridTile;
    final step = _gridStep;
    if (tile <= 0 || step <= 0) return false;

    final col = (dx / step).floor();
    final row = (dy / step).floor();

    if (row < 0 || row >= n || col < 0 || col >= n) return false;

    // ✅ 틈 클릭/드롭 방지: 칸 내부일 때만
    final inTileX = (dx - col * step) <= tile;
    final inTileY = (dy - row * step) <= tile;
    if (!inTileX || !inTileY) return false;

    // 범위/충돌 체크
    for (final cell in piece.cells) {
      final rr = row + cell.r;
      final cc = col + cell.c;
      if (rr < 0 || rr >= n || cc < 0 || cc >= n) return false;
      if (board[rr][cc] != 0) return false;
    }

    // 배치(색 유지)
    final colorId = _colorToId(piece.color);
    for (final cell in piece.cells) {
      board[row + cell.r][col + cell.c] = colorId;
    }

    return true;
  }

  int _colorToId(Color c) {
    // 간단히 색 value 기반으로 1..N 반복 매핑
    final colors = <Color>[
      const Color(0xFFFF3B30),
      const Color(0xFFAF52DE),
      const Color(0xFF0A84FF),
      const Color(0xFFFF2D55),
      const Color(0xFF30D158),
      const Color(0xFFFF9F0A),
    ];
    final idx = colors.indexWhere((e) => e.value == c.value);
    return (idx == -1) ? 1 : (idx + 1);
  }

  // =========================
  // UI
  // =========================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(builder: (context, cons) {
        final w = cons.maxWidth;
        final h = cons.maxHeight;

        // 보드 정사각형 크기
        final boardSide = min(w * 0.96, h * 0.60);

        // ✅ 너가 좋아한 위치
        final boardTop = h * 0.20;

        // 트레이 높이(하단바 바로 위)
        final trayHeight = min(160.0, h * 0.19);

        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onPanStart: _onPanStart,
          onPanUpdate: _onPanUpdate,
          onPanEnd: _onPanEnd,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.asset('assets/images/background.png', fit: BoxFit.cover),

              // ===== 보드 =====
              Positioned(
                top: boardTop,
                left: (w - boardSide) / 2,
                width: boardSide,
                height: boardSide,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.asset('assets/images/board.png', fit: BoxFit.fill),
                    CustomPaint(
                      painter: BoardPainter(
                        board: board,
                        tileImg: tileImg,
                        showEmptyCells: SHOW_EMPTY_CELLS,
                        onGridComputed: (gridRect, tile, step) {
                          // gridRect는 보드 위젯 내부 좌표
                          final boardOffset = Offset((w - boardSide) / 2, boardTop);
                          _gridRect = gridRect.shift(boardOffset);
                          _gridTile = tile;
                          _gridStep = step;
                        },
                      ),
                    ),
                  ],
                ),
              ),

              // ===== 트레이 =====
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: SizedBox(
                      height: trayHeight,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          CustomPaint(
                            painter: TrayPainter(
                              pieces: pieces,
                              tileImg: tileImg,
                              hideIndex: draggingIndex, // ✅ 누르면 자리 비움
                            ),
                          ),
                          LayoutBuilder(
                            builder: (context, trayCons) {
                              // ✅ 트레이 슬롯 rect를 화면 local 좌표 기준으로 계산
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                final box = context.findRenderObject() as RenderBox?;
                                final parent = this.context.findRenderObject() as RenderBox?;
                                if (box == null || parent == null) return;

                                final topLeftGlobal = box.localToGlobal(Offset.zero);
                                final topLeftLocal = parent.globalToLocal(topLeftGlobal);

                                final trayW = trayCons.maxWidth;
                                final slotW = trayW / 3;
                                final slotH = trayCons.maxHeight;

                                for (int i = 0; i < 3; i++) {
                                  _traySlotRects[i] = Rect.fromLTWH(
                                    topLeftLocal.dx + i * slotW,
                                    topLeftLocal.dy,
                                    slotW,
                                    slotH,
                                  );
                                }
                              });
                              return const SizedBox.expand();
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // ===== 드래그 프리뷰(오버레이) =====
              if (draggingPiece != null && dragGlobalPos != null)
                CustomPaint(
                  painter: DragOverlayPainter(
                    piece: draggingPiece!,
                    globalPos: dragGlobalPos!,
                    tileImg: tileImg,
                    lift: fingerLift, // ✅ 더 위로 뜸
                    targetTile: _gridTile > 0 ? _gridTile : 42,
                    gap: GAP,
                  ),
                  child: const SizedBox.expand(),
                ),
            ],
          ),
        );
      }),
    );
  }
}

// =========================
// 보드 painter
// =========================
class BoardPainter extends CustomPainter {
  final List<List<int>> board;
  final ui.Image? tileImg;
  final bool showEmptyCells;
  final void Function(Rect gridRect, double tile, double step) onGridComputed;

  BoardPainter({
    required this.board,
    required this.tileImg,
    required this.showEmptyCells,
    required this.onGridComputed,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const int n = 8;

    final gridRect = Rect.fromLTRB(
      _GamePageState.LEFT,
      _GamePageState.TOP,
      size.width - _GamePageState.RIGHT,
      size.height - _GamePageState.BOTTOM,
    );

    final tile = (gridRect.width - _GamePageState.GAP * (n - 1)) / n;
    final step = tile + _GamePageState.GAP;

    onGridComputed(gridRect, tile, step);

    if (showEmptyCells) {
      final emptyFill = Paint()
        ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.04)
        ..style = PaintingStyle.fill;

      final emptyStroke = Paint()
        ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.22)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;

      for (int r = 0; r < n; r++) {
        for (int c = 0; c < n; c++) {
          final x = gridRect.left + c * step;
          final y = gridRect.top + r * step;
          final rect = Rect.fromLTWH(x, y, tile, tile);
          canvas.drawRect(rect, emptyFill);
          canvas.drawRect(rect, emptyStroke);
        }
      }
    }

    for (int r = 0; r < n; r++) {
      for (int c = 0; c < n; c++) {
        final id = board[r][c];
        if (id == 0) continue;

        final x = gridRect.left + c * step;
        final y = gridRect.top + r * step;
        final dst = Rect.fromLTWH(x, y, tile, tile);

        final color = _idToColor(id);

        if (tileImg != null) {
          final src = Rect.fromLTWH(0, 0, tileImg!.width.toDouble(), tileImg!.height.toDouble());
          final paint = Paint()
            ..isAntiAlias = true
            ..filterQuality = FilterQuality.high
            ..colorFilter = ColorFilter.mode(color, BlendMode.modulate);
          canvas.drawImageRect(tileImg!, src, dst, paint);
        } else {
          final p = Paint()..color = color.withValues(alpha: 0.85);
          canvas.drawRect(dst, p);
        }
      }
    }
  }

  Color _idToColor(int id) {
    final colors = <Color>[
      const Color(0xFFFF3B30),
      const Color(0xFFAF52DE),
      const Color(0xFF0A84FF),
      const Color(0xFFFF2D55),
      const Color(0xFF30D158),
      const Color(0xFFFF9F0A),
    ];
    return colors[(id - 1) % colors.length];
  }

  @override
  bool shouldRepaint(covariant BoardPainter oldDelegate) => true;
}

// =========================
// 트레이 painter
// =========================
class TrayPainter extends CustomPainter {
  final List<Piece> pieces;
  final ui.Image? tileImg;
  final int? hideIndex;

  TrayPainter({
    required this.pieces,
    required this.tileImg,
    required this.hideIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final slotW = size.width / 3;
    final slotH = size.height;

    for (int i = 0; i < 3; i++) {
      if (hideIndex == i) continue; // ✅ 누른 슬롯은 비워두기

      final slot = Rect.fromLTWH(i * slotW, 0, slotW, slotH);
      final piece = pieces[i];

      final tile = min(slot.width, slot.height) * 0.25;

      final totalW = piece.w * tile + (piece.w - 1) * _GamePageState.GAP;
      final totalH = piece.h * tile + (piece.h - 1) * _GamePageState.GAP;

      final startX = slot.left + (slot.width - totalW) / 2;
      final startY = slot.top + (slot.height - totalH) / 2;

      for (final cell in piece.cells) {
        final x = startX + cell.c * (tile + _GamePageState.GAP);
        final y = startY + cell.r * (tile + _GamePageState.GAP);
        final dst = Rect.fromLTWH(x, y, tile, tile);

        if (tileImg != null) {
          final src = Rect.fromLTWH(0, 0, tileImg!.width.toDouble(), tileImg!.height.toDouble());
          final paint = Paint()
            ..isAntiAlias = true
            ..filterQuality = FilterQuality.high
            ..colorFilter = ColorFilter.mode(piece.color, BlendMode.modulate);
          canvas.drawImageRect(tileImg!, src, dst, paint);
        } else {
          final p = Paint()..color = piece.color.withValues(alpha: 0.85);
          canvas.drawRect(dst, p);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant TrayPainter oldDelegate) => true;
}

// =========================
// 드래그 프리뷰 painter
// =========================
class DragOverlayPainter extends CustomPainter {
  final Piece piece;
  final Offset globalPos;
  final ui.Image? tileImg;
  final double lift;
  final double targetTile;
  final double gap;

  DragOverlayPainter({
    required this.piece,
    required this.globalPos,
    required this.tileImg,
    required this.lift,
    required this.targetTile,
    required this.gap,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // ✅ 터치한 곳보다 위로(손가락 안 가리게)
    final pos = globalPos + Offset(0, -lift);

    final totalW = piece.w * targetTile + (piece.w - 1) * gap;
    final totalH = piece.h * targetTile + (piece.h - 1) * gap;

    final startX = pos.dx - totalW / 2;
    final startY = pos.dy - totalH / 2;

    for (final cell in piece.cells) {
      final x = startX + cell.c * (targetTile + gap);
      final y = startY + cell.r * (targetTile + gap);
      final dst = Rect.fromLTWH(x, y, targetTile, targetTile);

      if (tileImg != null) {
        final src = Rect.fromLTWH(0, 0, tileImg!.width.toDouble(), tileImg!.height.toDouble());
        final paint = Paint()
          ..isAntiAlias = true
          ..filterQuality = FilterQuality.high
          ..colorFilter = ColorFilter.mode(piece.color, BlendMode.modulate);
        canvas.drawImageRect(tileImg!, src, dst, paint);
      } else {
        final p = Paint()..color = piece.color.withValues(alpha: 0.85);
        canvas.drawRect(dst, p);
      }
    }
  }

  @override
  bool shouldRepaint(covariant DragOverlayPainter oldDelegate) => true;
}
