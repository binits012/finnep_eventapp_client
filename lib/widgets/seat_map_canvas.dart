import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/seat.dart';

/// Padding around seat bounds in data coordinate units (matches web SVG viewBox padding).
const double _kPadding = 20;

/// Canvas-based seat map matching web SVG approach: content size = data bounding
/// box + padding (in data units); InteractiveViewer scales to viewport.
/// seatRadius is computed from actual seat spacing so proportions match the web.
class SeatMapCanvas extends StatefulWidget {
  const SeatMapCanvas({
    super.key,
    required this.seats,
    this.sections = const [],
    required this.selectedPlaceIds,
    required this.onSeatTap,
    this.maxSeatsToSelect = 10,
    this.rowSpacingMultiplier = 1.0,
    this.seatSpacingMultiplier = 1.0,
    this.seatRadiusOverride,
  });

  final List<SeatModel> seats;
  final List<SectionModel> sections;
  final List<String> selectedPlaceIds;
  final ValueChanged<SeatModel> onSeatTap;
  final int maxSeatsToSelect;
  final double rowSpacingMultiplier;
  final double seatSpacingMultiplier;
  final double? seatRadiusOverride;

  @override
  State<SeatMapCanvas> createState() => _SeatMapCanvasState();
}

class _SeatMapCanvasState extends State<SeatMapCanvas> {
  double _minX = 0;
  double _minY = 0;
  double _contentWidth = 400;
  double _contentHeight = 400;
  double _seatRadius = 4;
  Map<String, Offset> _seatPositions = const {};
  bool _initialFitApplied = false;
  final TransformationController _ctrl = TransformationController();

  @override
  void didUpdateWidget(SeatMapCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.seats != widget.seats ||
        oldWidget.sections != widget.sections ||
        oldWidget.rowSpacingMultiplier != widget.rowSpacingMultiplier ||
        oldWidget.seatSpacingMultiplier != widget.seatSpacingMultiplier ||
        oldWidget.seatRadiusOverride != widget.seatRadiusOverride) {
      _initialFitApplied = false;
      _computeBounds();
    }
  }

  @override
  void initState() {
    super.initState();
    _computeBounds();
  }

  void _computeBounds() {
    final hasAnyPolygon = widget.sections.any((s) => s.polygon.isNotEmpty);
    final sectionByName = <String, SectionModel>{};
    for (final section in widget.sections) {
      final nameKey = section.name.trim().toLowerCase();
      final idKey = section.id.trim().toLowerCase();
      if (nameKey.isNotEmpty) sectionByName[nameKey] = section;
      if (idKey.isNotEmpty) sectionByName[idKey] = section;
    }

    double minX = double.infinity;
    double minY = double.infinity;
    double maxX = double.negativeInfinity;
    double maxY = double.negativeInfinity;
    final transformed = <String, Offset>{};
    for (final s in widget.seats) {
      if (s.x != null && s.y != null) {
        final raw = _scaledSeatPosition(
          s,
          sectionByName: sectionByName,
          useSectionTransforms: hasAnyPolygon,
        );
        transformed[s.placeId] = raw;
        minX = math.min(minX, raw.dx);
        minY = math.min(minY, raw.dy);
        maxX = math.max(maxX, raw.dx);
        maxY = math.max(maxY, raw.dy);
      }
    }
    if (minX == double.infinity) {
      minX = 0; maxX = 100; minY = 0; maxY = 100;
    }
    final rangeX = (maxX - minX).clamp(1.0, double.infinity);
    final rangeY = (maxY - minY).clamp(1.0, double.infinity);

    final sx = widget.seatSpacingMultiplier.clamp(0.1, 3.0);
    final radius = widget.seatRadiusOverride != null
        ? widget.seatRadiusOverride!.clamp(1.0, 24.0)
        : _computeSeatRadius(rangeX, rangeY) * sx;

    setState(() {
      _minX = minX;
      _minY = minY;
      _contentWidth = rangeX + 2 * _kPadding;
      _contentHeight = rangeY + 2 * _kPadding;
      _seatRadius = radius;
      _seatPositions = transformed;
    });
  }

  /// Compute radius from actual seat spacing, matching web's r=4 with spacing=10
  /// (radius ≈ 40% of center-to-center distance).
  double _computeSeatRadius(double rangeX, double rangeY) {
    final seatsWithPos = widget.seats.where((s) => s.x != null && s.y != null).toList();
    if (seatsWithPos.length < 2) return 4;

    // Group seats by approximate row (same y within tolerance)
    final rowTolerance = rangeY * 0.005;
    seatsWithPos.sort((a, b) => a.y!.compareTo(b.y!));

    final gaps = <double>[];
    double rowStartY = seatsWithPos.first.y!;
    var rowSeats = <SeatModel>[seatsWithPos.first];

    for (var i = 1; i < seatsWithPos.length; i++) {
      final s = seatsWithPos[i];
      if ((s.y! - rowStartY).abs() <= rowTolerance) {
        rowSeats.add(s);
      } else {
        _collectGaps(rowSeats, gaps);
        rowStartY = s.y!;
        rowSeats = [s];
      }
    }
    _collectGaps(rowSeats, gaps);

    if (gaps.isEmpty) return math.max(rangeX, rangeY) * 0.008;

    gaps.sort();
    final medianGap = gaps[gaps.length ~/ 2];
    final radius = (medianGap * 0.4).clamp(1.0, math.max(rangeX, rangeY) * 0.02);
    return radius;
  }

  void _collectGaps(List<SeatModel> rowSeats, List<double> gaps) {
    if (rowSeats.length < 2) return;
    rowSeats.sort((a, b) => a.x!.compareTo(b.x!));
    for (var i = 1; i < rowSeats.length; i++) {
      final gap = (rowSeats[i].x! - rowSeats[i - 1].x!).abs();
      if (gap > 0.01) gaps.add(gap);
    }
  }

  double _resolveSeatScale(SectionModel? section) {
    final global = widget.seatSpacingMultiplier;
    if ((global - 1.0).abs() > 0.001) return global.clamp(0.1, 3.0);
    final sectionScale = section?.spacingConfig?.seatSpacingVisual ?? 1.0;
    return sectionScale.clamp(0.1, 3.0);
  }

  double _resolveRowScale(SectionModel? section) {
    final global = widget.rowSpacingMultiplier;
    if ((global - 1.0).abs() > 0.001) return global.clamp(0.1, 3.0);
    final sectionScale = section?.spacingConfig?.rowSpacingVisual ?? 1.0;
    return sectionScale.clamp(0.1, 3.0);
  }

  Offset _scaledSeatPosition(
    SeatModel seat, {
    required Map<String, SectionModel> sectionByName,
    required bool useSectionTransforms,
  }) {
    final x = seat.x ?? 0;
    final y = seat.y ?? 0;
    if (!useSectionTransforms) {
      return Offset(
        x * widget.seatSpacingMultiplier.clamp(0.1, 3.0),
        y * widget.rowSpacingMultiplier.clamp(0.1, 3.0),
      );
    }

    final sectionKey = (seat.section ?? '').trim().toLowerCase();
    final section = sectionByName[sectionKey];
    final polygon = section?.polygon ?? const <SectionPoint>[];
    if (polygon.isEmpty) return Offset(x, y);

    final seatScale = _resolveSeatScale(section);
    final rowScale = _resolveRowScale(section);
    final topMargin = section?.spacingConfig?.topMargin ?? 0;
    final rotation = section?.spacingConfig?.rotationAngle ?? 0;

    final centerX =
        polygon.fold<double>(0, (sum, p) => sum + p.x) / polygon.length;
    final centerY =
        polygon.fold<double>(0, (sum, p) => sum + p.y) / polygon.length;

    if ((seatScale - 1.0).abs() < 0.001 &&
        (rowScale - 1.0).abs() < 0.001 &&
        rotation.abs() < 0.001 &&
        topMargin.abs() < 0.001) {
      return Offset(x, y);
    }

    if (rotation.abs() > 0.001) {
      final reducedSeatScale = 0.6 + (seatScale - 1.0);
      final reducedRowScale = 0.8 + (rowScale - 1.0);
      final radians = rotation * math.pi / 180.0;
      final cosA = math.cos(radians);
      final sinA = math.sin(radians);

      final offsetX = x - centerX;
      final offsetY = y - centerY;
      final localX = offsetX * cosA + offsetY * sinA;
      final localY = -offsetX * sinA + offsetY * cosA;
      final scaledLocalX = localX * reducedSeatScale;
      final scaledLocalY = localY * reducedRowScale;
      final rotatedBackX = scaledLocalX * cosA - scaledLocalY * sinA;
      final rotatedBackY = scaledLocalX * sinA + scaledLocalY * cosA;
      return Offset(centerX + rotatedBackX, centerY + rotatedBackY);
    }

    final scaledX = centerX + (x - centerX) * seatScale;
    final scaledY = topMargin + centerY + (y - centerY) * rowScale;
    return Offset(scaledX, scaledY);
  }

  double _tx(SeatModel s) =>
      _kPadding + ((_seatPositions[s.placeId]?.dx ?? s.x ?? 0) - _minX);
  double _ty(SeatModel s) =>
      _kPadding + ((_seatPositions[s.placeId]?.dy ?? s.y ?? 0) - _minY);

  SeatModel? _hitSeat(Offset local) {
    final r = _seatRadius * 2.5;
    final r2 = r * r;
    SeatModel? best;
    double bestD2 = r2;
    for (final s in widget.seats) {
      if (s.x == null || s.y == null) continue;
      final dx = local.dx - _tx(s);
      final dy = local.dy - _ty(s);
      final d2 = dx * dx + dy * dy;
      if (d2 <= bestD2) {
        bestD2 = d2;
        best = s;
      }
    }
    return best;
  }

  static Color _seatColor(SeatModel s, bool isSelected) {
    if (isSelected) return const Color(0xFF3b82f6);
    switch (s.status) {
      case SeatStatus.sold:
        return const Color(0xFFef4444);
      case SeatStatus.reserved:
        return const Color(0xFFf59e0b);
      case SeatStatus.available:
        return const Color(0xFF10b981);
    }
  }

  void _applyInitialFit(double viewportW, double viewportH) {
    if (_initialFitApplied || _contentWidth <= 0 || _contentHeight <= 0) return;
    _initialFitApplied = true;
    final fitWidthScale = (viewportW / _contentWidth) * 0.98;
    final fitHeightScale = (viewportH / _contentHeight) * 0.95;

    // For tall maps, fit by width (larger seats, preserved row spacing) and allow vertical pan.
    final isTallMap = (_contentHeight / _contentWidth) > 1.25;
    final scale = isTallMap ? fitWidthScale : math.min(fitWidthScale, fitHeightScale);

    final displayW = scale * _contentWidth;
    final displayH = scale * _contentHeight;
    final tx = (viewportW - displayW) / 2;
    final ty = displayH > viewportH ? 8.0 : (viewportH - displayH) / 2;
    _ctrl.value = Matrix4.identity()
      ..scale(scale)
      ..translate(tx / scale, ty / scale);
  }

  @override
  Widget build(BuildContext context) {
    final seatsWithPosition = widget.seats.where((s) => s.x != null && s.y != null).toList();
    if (seatsWithPosition.isEmpty) {
      return const Center(child: Text('No seat positions available'));
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final vw = constraints.maxWidth;
        final vh = constraints.maxHeight;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _applyInitialFit(vw, vh);
        });
        return InteractiveViewer(
          transformationController: _ctrl,
          minScale: 0.1,
          maxScale: 10,
          panEnabled: true,
          scaleEnabled: true,
          constrained: false,
          clipBehavior: Clip.none,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTapUp: (details) {
              final seat = _hitSeat(details.localPosition);
              if (seat != null) widget.onSeatTap(seat);
            },
            child: SizedBox(
              width: _contentWidth,
              height: _contentHeight,
              child: CustomPaint(
                painter: _SeatMapPainter(
                  seats: seatsWithPosition,
                  selectedPlaceIds: widget.selectedPlaceIds.toSet(),
                  tx: _tx,
                  ty: _ty,
                  seatRadius: _seatRadius,
                  seatColor: _seatColor,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SeatMapPainter extends CustomPainter {
  _SeatMapPainter({
    required this.seats,
    required this.selectedPlaceIds,
    required this.tx,
    required this.ty,
    required this.seatRadius,
    required this.seatColor,
  });

  final List<SeatModel> seats;
  final Set<String> selectedPlaceIds;
  final double Function(SeatModel) tx;
  final double Function(SeatModel) ty;
  final double seatRadius;
  final Color Function(SeatModel, bool isSelected) seatColor;

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in seats) {
      final x = tx(s);
      final y = ty(s);
      final isSelected = selectedPlaceIds.contains(s.placeId);
      var color = seatColor(s, isSelected);
      final isWheelchair = s.tags.contains('wheelchair');
      if (s.status == SeatStatus.sold || s.status == SeatStatus.reserved) {
        color = color.withOpacity(0.5);
      }
      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(x, y), seatRadius, paint);
      if (isSelected || isWheelchair) {
        final stroke = Paint()
          ..color = isWheelchair ? const Color(0xFF9333ea) : Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = seatRadius * 0.4;
        canvas.drawCircle(Offset(x, y), seatRadius, stroke);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SeatMapPainter oldDelegate) {
    return oldDelegate.seats != seats ||
        oldDelegate.selectedPlaceIds != selectedPlaceIds ||
        oldDelegate.seatRadius != seatRadius;
  }
}
