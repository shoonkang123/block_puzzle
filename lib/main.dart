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

  // 보드 맞춤값
  static const double LEFT = 14;
  static const double TOP = 14;
  static const double RIGHT = 14;
  static const double BOTTOM = 14;
  static const double GAP = 2;

  // 손가락 가림 방지(프리뷰 위로)
  static const double fingerLift = 110;

  // 빈 칸 가이드
  static const bool SHOW_EMPTY_CELLS = true;

  final List<List<int>> board = List.generate(n, (_) => List.filled(n, 0));
  late List<Piece> pieces;

  ui.Image? tileImg;

  Rect? _gridRect;
  double _gridTile = 0;
  double _gridStep = 0;

  final List<Rect> _traySlotRects = [Rect.zero, Rect.zero, Rect.zero];

  int? draggingIndex;
  Piece? draggingPiece;
  Offset? dragGlobalPos;

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
  // 드래그
  // =========================
  void _onPanStart(DragStartDetails d) {
    final local = d.localPosition;
    for (int i = 0; i < 3; i++) {
      if (_traySlotRects[i].contains(local)) {
        setState(() {
          draggingIndex = i;
          draggingPiece = pieces[i];
          dragGlobalPos = d.globalPosition;
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

    final previewGlobalCenter = d.globalPosition + const Offset(0, -fingerLift);
    final placed = _tryPlaceOnBoardMatchPreview(draggingPiece!, previewGlobalCenter);

    setState(() {
      if (placed) pieces[draggingIndex!] = _randomPiece();
      draggingIndex = null;
      draggingPiece = null;
      dragGlobalPos = null;
    });
  }

  // ===== (A) 프리뷰(센터) -> 프리뷰 좌상단 계산 =====
  Offset _previewTopLeftFromCenterLocal(Piece piece, Offset centerLocal, double tile) {
    final totalW = piece.w * tile + (piece.w - 1) * GAP;
    final totalH = piece.h * tile + (piece.h - 1) * GAP;
    return Offset(centerLocal.dx - totalW / 2, centerLocal.dy - totalH / 2);
  }

  // ===== (B) 프리뷰 좌상단 -> 보드 스냅 baseRow/baseCol =====
  ({int row, int col})? _snapBaseFromPreviewTopLeft(Offset previewTopLeftLocal) {
    final rect = _gridRect;
    if (rect == null) return null;

    final step = _gridStep;
    if (step <= 0) return null;

    final gx = previewTopLeftLocal.dx - rect.left;
    final gy = previewTopLeftLocal.dy - rect.top;

    final baseCol = (gx / step).round();
    final baseRow = (gy / step).round();
    return (row: baseRow, col: baseCol);
  }

  // ===== (C) 놓을 수 있는지 체크 =====
  bool _canPlace(Piece piece, int baseRow, int baseCol) {
    if (baseRow < 0 || baseCol < 0) return false;
    if (baseRow + piece.h > n || baseCol + piece.w > n) return false;

    for (final cell in piece.cells) {
      final rr = baseRow + cell.r;
      final cc = baseCol + cell.c;
      if (board[rr][cc] != 0) return false;
    }
    return true;
  }

  // ===== (D) 실제 배치 =====
  bool _tryPlaceOnBoardMatchPreview(Piece piece, Offset previewGlobalCenter) {
    final rect = _gridRect;
    if (rect == null) return false;

    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return false;

    final tile = _gridTile;
    final step = _gridStep;
    if (tile <= 0 || step <= 0) return false;

    final centerLocal = box.globalToLocal(previewGlobalCenter);
    final topLeft = _previewTopLeftFromCenterLocal(piece, centerLocal, tile);
    final snap = _snapBaseFromPreviewTopLeft(topLeft);
    if (snap == null) return false;

    if (!_canPlace(piece, snap.row, snap.col)) return false;

    final colorId = _colorToId(piece.color);
    for (final cell in piece.cells) {
      board[snap.row + cell.r][snap.col + cell.c] = colorId;
    }
    return true;
  }

  int _colorToId(Color c) {
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

        final boardSide = min(w * 0.96, h * 0.60);
        final boardTop = h * 0.20;

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
                              hideIndex: draggingIndex,
                            ),
                          ),
                          LayoutBuilder(
                            builder: (context, trayCons) {
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

              // ===== ✅ 보드 위 "스냅 프리뷰" (놓을 수 있을 때만) =====
              if (draggingPiece != null && dragGlobalPos != null && _gridRect != null && _gridTile > 0 && _gridStep > 0)
                CustomPaint(
                  painter: SnapPreviewPainter(
                    piece: draggingPiece!,
                    dragGlobalPos: dragGlobalPos!,
                    fingerLift: fingerLift,
                    gridRect: _gridRect!,
                    tile: _gridTile,
                    step: _gridStep,
                    gap: GAP,
                    canPlace: (row, col) => _canPlace(draggingPiece!, row, col),
                    tileImg: tileImg,
                  ),
                  child: const SizedBox.expand(),
                ),

              // ===== 드래그 프리뷰(손가락 따라다니는 것) =====
              if (draggingPiece != null && dragGlobalPos != null)
                CustomPaint(
                  painter: DragOverlayPainter(
                    piece: draggingPiece!,
                    globalPos: dragGlobalPos!,
                    tileImg: tileImg,
                    lift: fingerLift,
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
// 스냅 프리뷰 Painter
// =========================
class SnapPreviewPainter extends CustomPainter {
  final Piece piece;
  final Offset dragGlobalPos;
  final double fingerLift;

  final Rect gridRect;
  final double tile;
  final double step;
  final double gap;

  final bool Function(int row, int col) canPlace;
  final ui.Image? tileImg;

  SnapPreviewPainter({
    required this.piece,
    required this.dragGlobalPos,
    required this.fingerLift,
    required this.gridRect,
    required this.tile,
    required this.step,
    required this.gap,
    required this.canPlace,
    required this.tileImg,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // globalPos는 이미 GestureDetector 기준 global 좌표로 들어옴
    // 여기서는 CustomPainter가 화면 전체라서 globalPos를 그대로 local처럼 써도 됨(오차가 있을 수 있음).
    // 안전하게 하려면 RenderBox 변환을 해야 하지만, 현재 구조 유지 요청이라 여기선 동일 스케일로 처리.
    final center = dragGlobalPos + Offset(0, -fingerLift);

    final totalW = piece.w * tile + (piece.w - 1) * gap;
    final totalH = piece.h * tile + (piece.h - 1) * gap;

    final startX = center.dx - totalW / 2;
    final startY = center.dy - totalH / 2;

    final gx = startX - gridRect.left;
    final gy = startY - gridRect.top;

    final baseCol = (gx / step).round();
    final baseRow = (gy / step).round();

    if (!canPlace(baseRow, baseCol)) return;

    // ✅ 스냅된 위치의 top-left를 다시 계산해서 유령 프리뷰 그림
    final snapX = gridRect.left + baseCol * step;
    final snapY = gridRect.top + baseRow * step;

    final ghostAlpha = 0.35;

    for (final cell in piece.cells) {
      final x = snapX + cell.c * step;
      final y = snapY + cell.r * step;
      final dst = Rect.fromLTWH(x, y, tile, tile);

      if (tileImg != null) {
        final src = Rect.fromLTWH(0, 0, tileImg!.width.toDouble(), tileImg!.height.toDouble());
        final paint = Paint()
          ..isAntiAlias = true
          ..filterQuality = FilterQuality.high
          ..colorFilter = ColorFilter.mode(piece.color.withValues(alpha: ghostAlpha), BlendMode.modulate);
        canvas.drawImageRect(tileImg!, src, dst, paint);
      } else {
        final p = Paint()..color = piece.color.withValues(alpha: ghostAlpha);
        canvas.drawRect(dst, p);
      }
    }
  }

  @override
  bool shouldRepaint(covariant SnapPreviewPainter oldDelegate) => true;
}

// =========================
// Board Painter
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
// Tray Painter
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
      if (hideIndex == i) continue;

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
// Drag Overlay Painter
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
    final center = globalPos + Offset(0, -lift);

    final totalW = piece.w * targetTile + (piece.w - 1) * gap;
    final totalH = piece.h * targetTile + (piece.h - 1) * gap;

    final startX = center.dx - totalW / 2;
    final startY = center.dy - totalH / 2;

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
