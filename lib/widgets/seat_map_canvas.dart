import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/seat.dart';

/// Padding around seat bounds in data coordinate units (matches web SVG viewBox padding).
const double _kPadding = 20;

/// Pinch zoom, relative to the fitted overview, where the section curtain is gone.
const double _kCurtainFadeEnd = 1.7;

const List<Color> _kCurtainColors = <Color>[
  Color(0xFF1d4ed8),
  Color(0xFF15803d),
  Color(0xFF2563eb),
  Color(0xFF166534),
  Color(0xFF1e40af),
  Color(0xFF047857),
  Color(0xFF0284c7),
  Color(0xFF059669),
];

/// 1 covers the section. 0 shows the seats. [relativeZoom] is 1 at the fitted overview.
double curtainOpacityForZoom({
  required double relativeZoom,
  required bool sectionOpen,
}) {
  if (sectionOpen || relativeZoom >= _kCurtainFadeEnd) return 0;
  if (relativeZoom <= 1) return 1;
  return 1 - (relativeZoom - 1) / (_kCurtainFadeEnd - 1);
}

/// X/Y scale of a map transform. [Matrix4.getMaxScaleOnAxis] also reads the Z
/// axis, which stays 1, so a fitted overview below 1 would look fully zoomed in.
double viewScaleOf(Matrix4 matrix) {
  final List<double> storage = matrix.storage;
  final double scaleX = math.sqrt((storage[0] * storage[0]) + (storage[1] * storage[1]));
  final double scaleY = math.sqrt((storage[4] * storage[4]) + (storage[5] * storage[5]));
  return math.max(scaleX, scaleY);
}

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
    this.focusedSectionId,
    this.onSectionTap,
  });

  final List<SeatModel> seats;
  final List<SectionModel> sections;
  final List<String> selectedPlaceIds;
  final ValueChanged<SeatModel> onSeatTap;
  final int maxSeatsToSelect;
  final double rowSpacingMultiplier;
  final double seatSpacingMultiplier;
  final double? seatRadiusOverride;
  final String? focusedSectionId;
  final ValueChanged<String>? onSectionTap;

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
  Map<String, List<Offset>> _transformedSectionPolygons = const {};
  bool _initialFitApplied = false;
  double? _overviewScale;
  final TransformationController _ctrl = TransformationController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(SeatMapCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.seats != widget.seats ||
        oldWidget.sections != widget.sections ||
        oldWidget.rowSpacingMultiplier != widget.rowSpacingMultiplier ||
        oldWidget.seatSpacingMultiplier != widget.seatSpacingMultiplier ||
        oldWidget.seatRadiusOverride != widget.seatRadiusOverride ||
        oldWidget.focusedSectionId != widget.focusedSectionId) {
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
    final transformedPolygons = <String, List<Offset>>{};

    // Include polygon points in bounds (standing/area has no seat x/y but has polygon).
    for (final section in widget.sections) {
      if (section.polygon.isEmpty) continue;

      final points = <Offset>[];
      for (final p in section.polygon) {
        final scaled = hasAnyPolygon ? _scaledPointForSection(section, p) : Offset(p.x, p.y);
        points.add(scaled);
        minX = math.min(minX, scaled.dx);
        minY = math.min(minY, scaled.dy);
        maxX = math.max(maxX, scaled.dx);
        maxY = math.max(maxY, scaled.dy);
      }
      transformedPolygons[section.id] = points;
    }

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

    final sx = widget.seatSpacingMultiplier.clamp(0.1, 1.0);
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
      _transformedSectionPolygons = transformedPolygons;
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
    if ((global - 1.0).abs() > 0.001) return global.clamp(0.1, 1.0);
    final sectionScale = section?.spacingConfig?.seatSpacingVisual ?? 1.0;
    return sectionScale.clamp(0.1, 1.0);
  }

  double _resolveRowScale(SectionModel? section) {
    final global = widget.rowSpacingMultiplier;
    if ((global - 1.0).abs() > 0.001) return global.clamp(0.1, 1.0);
    final sectionScale = section?.spacingConfig?.rowSpacingVisual ?? 1.0;
    return sectionScale.clamp(0.1, 1.0);
  }

  Offset _scaledPointForSection(SectionModel section, SectionPoint p) {
    final x = p.x;
    final y = p.y;

    final seatScale = _resolveSeatScale(section);
    final rowScale = _resolveRowScale(section);
    final topMargin = section.spacingConfig?.topMargin ?? 0;
    final rotation = section.spacingConfig?.rotationAngle ?? 0;

    final polygon = section.polygon;
    if (polygon.isEmpty) return Offset(x, y);

    final centerX =
        polygon.fold<double>(0, (sum, q) => sum + q.x) / polygon.length;
    final centerY =
        polygon.fold<double>(0, (sum, q) => sum + q.y) / polygon.length;

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

      // Keep consistent with web/seat transform: no topMargin in rotation branch.
      return Offset(centerX + rotatedBackX, centerY + rotatedBackY);
    }

    final scaledX = centerX + (x - centerX) * seatScale;
    final scaledY = topMargin + centerY + (y - centerY) * rowScale;
    return Offset(scaledX, scaledY);
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
        x * widget.seatSpacingMultiplier.clamp(0.1, 1.0),
        y * widget.rowSpacingMultiplier.clamp(0.1, 1.0),
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

  int _seatRenderPriority(SeatModel s) {
    if (widget.selectedPlaceIds.contains(s.placeId)) return 3;
    if (s.status == SeatStatus.sold) return 2;
    if (s.status == SeatStatus.reserved) return 1;
    return 0;
  }

  List<SeatModel> _visibleSeatsForRendering() {
    final clustered = <({SeatModel seat, Offset point})>[];
    final mergeDistance = math.max(1.5, _seatRadius * 0.75);
    final mergeDistance2 = mergeDistance * mergeDistance;
    for (final seat in widget.seats) {
      if (seat.x == null || seat.y == null) continue;
      final x = _tx(seat);
      final y = _ty(seat);
      var merged = false;
      for (var i = 0; i < clustered.length; i++) {
        final entry = clustered[i];
        final dx = entry.point.dx - x;
        final dy = entry.point.dy - y;
        final d2 = (dx * dx) + (dy * dy);
        if (d2 <= mergeDistance2) {
          // Merge effectively-overlapping dots so blocked state cannot be hidden
          // by a nearby duplicate "available" seat.
          final existingPriority = _seatRenderPriority(entry.seat);
          final nextPriority = _seatRenderPriority(seat);
          if (nextPriority >= existingPriority) {
            clustered[i] = (seat: seat, point: Offset(x, y));
          }
          merged = true;
          break;
        }
      }
      if (!merged) {
        clustered.add((seat: seat, point: Offset(x, y)));
      }
    }
    return clustered.map((e) => e.seat).toList();
  }

  SeatModel? _hitSeat(Offset local) {
    final r = _seatRadius * 2.5;
    final r2 = r * r;
    SeatModel? best;
    double bestD2 = r2;
    for (final s in _visibleSeatsForRendering()) {
      if (s.x == null || s.y == null) continue;
      final dx = local.dx - _tx(s);
      final dy = local.dy - _ty(s);
      final d2 = dx * dx + dy * dy;
      if (d2 < bestD2) {
        bestD2 = d2;
        best = s;
      } else if (d2 == bestD2 && best != null) {
        // If two dots overlap exactly, prefer non-available status so blocked seats are not tappable.
        final bestIsAvailable = best.status == SeatStatus.available;
        final nextIsAvailable = s.status == SeatStatus.available;
        if (bestIsAvailable && !nextIsAvailable) {
          best = s;
        }
      }
    }
    return best;
  }

  String? _hitSection(Offset local) {
    String? bestId;
    var bestArea = double.infinity;
    for (final section in widget.sections) {
      if (!_sectionCanOpen(section)) continue;
      final polygon = _transformedSectionPolygons[section.id];
      if (polygon == null || polygon.length < 3) continue;
      final canvasPoints = <Offset>[
        for (final point in polygon) Offset(_pointTx(point.dx), _pointTy(point.dy)),
      ];
      if (!_polygonContains(local, canvasPoints)) continue;
      final area = _polygonArea(canvasPoints);
      if (area < bestArea) {
        bestArea = area;
        bestId = section.id;
      }
    }
    return bestId;
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

  Rect? _focusedContentRect() {
    final id = widget.focusedSectionId;
    if (id == null || id.isEmpty) return null;
    SectionModel? section;
    for (final item in widget.sections) {
      if (item.id == id) {
        section = item;
        break;
      }
    }
    if (section == null) return null;
    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = double.negativeInfinity;
    var maxY = double.negativeInfinity;
    void includeDataPoint(double x, double y) {
      final childX = _kPadding + (x - _minX);
      final childY = _kPadding + (y - _minY);
      minX = math.min(minX, childX);
      minY = math.min(minY, childY);
      maxX = math.max(maxX, childX);
      maxY = math.max(maxY, childY);
    }
    final polygon = _transformedSectionPolygons[section.id] ?? const <Offset>[];
    for (final point in polygon) {
      includeDataPoint(point.dx, point.dy);
    }
    final name = section.name.trim().toLowerCase();
    final sectionId = section.id.trim().toLowerCase();
    for (final seat in widget.seats) {
      final key = (seat.section ?? '').trim().toLowerCase();
      if (key.isEmpty || (key != name && key != sectionId)) continue;
      final pos = _seatPositions[seat.placeId];
      if (pos == null) continue;
      includeDataPoint(pos.dx, pos.dy);
    }
    if (minX == double.infinity) return null;
    const pad = 36.0;
    return Rect.fromLTRB(minX - pad, minY - pad, maxX + pad, maxY + pad);
  }

  void _applyInitialFit(double viewportW, double viewportH) {
    if (_initialFitApplied || _contentWidth <= 0 || _contentHeight <= 0) return;
    if (viewportW <= 0 || viewportH <= 0) return;
    _initialFitApplied = true;
    final focus = _focusedContentRect();
    final rect = focus ?? Rect.fromLTWH(0, 0, _contentWidth, _contentHeight);
    final fitWidthScale = (viewportW / rect.width) * 0.98;
    final fitHeightScale = (viewportH / rect.height) * 0.95;
    final isTallMap = (rect.height / rect.width) > 1.25;
    final scale = focus != null
        ? math.min(fitWidthScale, fitHeightScale)
        : (isTallMap ? fitWidthScale : math.min(fitWidthScale, fitHeightScale));
    final displayW = scale * rect.width;
    final displayH = scale * rect.height;
    final tx = (viewportW - displayW) / 2 - rect.left * scale;
    final ty = focus == null
        ? (displayH > viewportH ? 8.0 : (viewportH - displayH) / 2)
        : (viewportH - displayH) / 2 - rect.top * scale;
    final matrix = Matrix4.diagonal3Values(scale, scale, 1.0);
    matrix.setTranslationRaw(tx, ty, 0.0);
    _ctrl.value = matrix;
    if (focus == null && (_overviewScale == null || (_overviewScale! - scale).abs() > 0.0001)) {
      setState(() => _overviewScale = scale);
    }
  }

  bool get _sectionOpen =>
      widget.focusedSectionId != null && widget.focusedSectionId!.isNotEmpty;

  double _curtainOpacity() {
    final overview = _overviewScale;
    if (overview == null || overview <= 0) return _sectionOpen ? 0 : 1;
    final relativeZoom = viewScaleOf(_ctrl.value) / overview;
    return curtainOpacityForZoom(relativeZoom: relativeZoom, sectionOpen: _sectionOpen);
  }

  double _pointTx(double x) => _kPadding + (x - _minX);
  double _pointTy(double y) => _kPadding + (y - _minY);

  bool _sectionHasSeatDots(SectionModel section) {
    final String name = section.name.trim().toLowerCase();
    final String id = section.id.trim().toLowerCase();
    for (final SeatModel seat in widget.seats) {
      final String key = (seat.section ?? '').trim().toLowerCase();
      if (_sectionKeyMatches(name, key) || _sectionKeyMatches(id, key)) return true;
    }
    return false;
  }

  bool _sectionKeyMatches(String sectionKey, String seatKey) {
    if (sectionKey.isEmpty || seatKey.isEmpty) return false;
    return sectionKey == seatKey ||
        sectionKey.contains(seatKey) ||
        seatKey.contains(sectionKey);
  }

  bool _sectionCanOpen(SectionModel section) {
    if (section.isInactiveAreaHighlight) return false;
    return _sectionHasSeatDots(section);
  }

  @override
  Widget build(BuildContext context) {
    final seatsWithPosition = widget.seats.where((s) => s.x != null && s.y != null).toList();
    final hasAnyAreaPolygon = widget.sections.any((s) => s.polygon.isNotEmpty);
    if (seatsWithPosition.isEmpty && !hasAnyAreaPolygon) {
      return const Center(child: Text('No seat positions available'));
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final vw = constraints.maxWidth;
        final vh = constraints.maxHeight;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _applyInitialFit(vw, vh);
        });
        final double overview = _overviewScale ?? viewScaleOf(_ctrl.value);
        final double minScale = math.max(0.001, overview * 0.92);
        final double maxScale = math.max(minScale * 4, math.max(12, overview * 24));
        return InteractiveViewer(
          transformationController: _ctrl,
          minScale: minScale,
          maxScale: maxScale,
          panEnabled: true,
          scaleEnabled: true,
          constrained: false,
          // Keep seat-map rendering inside its box so it cannot visually cover
          // the bottom CTA on devices with system navigation bars.
          clipBehavior: Clip.hardEdge,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTapUp: (details) {
              if (_curtainOpacity() > 0.45) {
                final sectionId = _hitSection(details.localPosition);
                if (sectionId != null) widget.onSectionTap?.call(sectionId);
                return;
              }
              final seat = _hitSeat(details.localPosition);
              if (seat != null) widget.onSeatTap(seat);
            },
            child: SizedBox(
              width: _contentWidth,
              height: _contentHeight,
              child: CustomPaint(
                painter: _SeatMapPainter(
                  seats: _visibleSeatsForRendering(),
                  selectedPlaceIds: widget.selectedPlaceIds.toSet(),
                  tx: _tx,
                  ty: _ty,
                  pointTx: _pointTx,
                  pointTy: _pointTy,
                  sections: widget.sections,
                  transformedSectionPolygons: _transformedSectionPolygons,
                  focusedSectionId: widget.focusedSectionId,
                  sectionHasSeatDots: _sectionHasSeatDots,
                  seatRadius: _seatRadius,
                  seatColor: _seatColor,
                  transform: _ctrl,
                  overviewScale: _overviewScale,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

bool _polygonContains(Offset point, List<Offset> polygon) {
  var inside = false;
  for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
    final pi = polygon[i];
    final pj = polygon[j];
    final crosses = (pi.dy > point.dy) != (pj.dy > point.dy);
    if (!crosses) continue;
    final xAtY = (pj.dx - pi.dx) * (point.dy - pi.dy) / (pj.dy - pi.dy) + pi.dx;
    if (point.dx < xAtY) inside = !inside;
  }
  return inside;
}

double _polygonArea(List<Offset> polygon) {
  var sum = 0.0;
  for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
    sum += (polygon[j].dx + polygon[i].dx) * (polygon[j].dy - polygon[i].dy);
  }
  return sum.abs() / 2;
}

class _SeatMapPainter extends CustomPainter {
  _SeatMapPainter({
    required this.seats,
    required this.selectedPlaceIds,
    required this.tx,
    required this.ty,
    required this.pointTx,
    required this.pointTy,
    required this.sections,
    required this.transformedSectionPolygons,
    required this.focusedSectionId,
    required this.sectionHasSeatDots,
    required this.seatRadius,
    required this.seatColor,
    required TransformationController transform,
    required this.overviewScale,
  })  : _transform = transform,
        super(repaint: transform);

  final List<SeatModel> seats;
  final Set<String> selectedPlaceIds;
  final double Function(SeatModel) tx;
  final double Function(SeatModel) ty;
  final double Function(double) pointTx;
  final double Function(double) pointTy;
  final double seatRadius;
  final Color Function(SeatModel, bool isSelected) seatColor;
  final List<SectionModel> sections;
  final Map<String, List<Offset>> transformedSectionPolygons;
  final String? focusedSectionId;
  final bool Function(SectionModel section) sectionHasSeatDots;
  final TransformationController _transform;
  final double? overviewScale;

  double get _curtainOpacity {
    final sectionOpen = focusedSectionId != null && focusedSectionId!.isNotEmpty;
    final overview = overviewScale;
    if (overview == null || overview <= 0) return sectionOpen ? 0 : 1;
    final relativeZoom = viewScaleOf(_transform.value) / overview;
    return curtainOpacityForZoom(relativeZoom: relativeZoom, sectionOpen: sectionOpen);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final curtainOpacity = _curtainOpacity;
    final sortedSections = [...sections]..sort((a, b) {
        final ai = a.isInactiveAreaHighlight ? 0 : 1;
        final bi = b.isInactiveAreaHighlight ? 0 : 1;
        if (ai != bi) return ai.compareTo(bi);
        return a.id.compareTo(b.id);
      });

    for (final section in sortedSections) {
      if (_isCurtainSection(section)) continue;
      _paintSectionBody(canvas, section);
    }

    if (curtainOpacity < 0.98) {
      _paintSeats(canvas, 1 - curtainOpacity);
    }
    if (curtainOpacity > 0.02) {
      for (var index = 0; index < sections.length; index++) {
        final section = sections[index];
        if (!_isCurtainSection(section)) continue;
        _paintCurtain(canvas, section, index, curtainOpacity);
      }
    }
    if (curtainOpacity < 0.45) _paintRowLabels(canvas);
  }

  bool _isCurtainSection(SectionModel section) {
    if (!sectionHasSeatDots(section)) return false;
    if (section.isInactiveAreaHighlight) return false;
    return true;
  }

  Path? _sectionPath(SectionModel section) {
    final pts = transformedSectionPolygons[section.id];
    if (pts == null || pts.length < 3) return null;
    final path = Path()..moveTo(pointTx(pts.first.dx), pointTy(pts.first.dy));
    for (var i = 1; i < pts.length; i++) {
      path.lineTo(pointTx(pts[i].dx), pointTy(pts[i].dy));
    }
    path.close();
    return path;
  }

  void _paintSectionBody(Canvas canvas, SectionModel section) {
    final path = _sectionPath(section);
    if (path == null) return;
    final hasSeats = sectionHasSeatDots(section);
    final isArea = section.selectionMode == 'area' && !hasSeats;
    final isField = !hasSeats && !isArea;
    final inactive = isArea && section.isInactiveAreaHighlight;
    final fillOpacity = isField
        ? 0.16
        : inactive
            ? 0.07
            : hasSeats
                ? 0.04
                : 0.11;
    final fillPaint = Paint()
      ..color = isField
          ? const Color(0xFF1e3a5f).withValues(alpha: fillOpacity)
          : sectionColorWithOpacity(section.color, fillOpacity)
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, fillPaint);
    final strokePaint = Paint()
      ..color = inactive
          ? const Color(0xFF6b7280)
          : sectionColorWithOpacity(section.color, 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = inactive ? 1.2 : 1.6;
    canvas.drawPath(path, strokePaint);
  }

  void _paintCurtain(Canvas canvas, SectionModel section, int index, double opacity) {
    final path = _sectionPath(section);
    final pts = transformedSectionPolygons[section.id];
    if (path == null || pts == null) return;
    final fill = _kCurtainColors[index % _kCurtainColors.length].withValues(alpha: 0.94 * opacity);
    canvas.drawPath(path, Paint()..color = fill..style = PaintingStyle.fill);
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white.withValues(alpha: opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4,
    );
    _paintCurtainLabel(canvas, pts, section.name, opacity);
  }

  void _paintCurtainLabel(Canvas canvas, List<Offset> pts, String name, double opacity) {
    final label = name.trim();
    if (label.isEmpty || opacity < 0.08) return;
    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = double.negativeInfinity;
    var maxY = double.negativeInfinity;
    for (final point in pts) {
      final x = pointTx(point.dx);
      final y = pointTy(point.dy);
      minX = math.min(minX, x);
      minY = math.min(minY, y);
      maxX = math.max(maxX, x);
      maxY = math.max(maxY, y);
    }
    final width = math.max(maxX - minX, 1);
    final height = math.max(maxY - minY, 1);
    final fitted = (width * 0.72) / math.max(label.length * 0.62, 1);
    final double fontSize = math.max(14.0, math.min(fitted, math.min(height * 0.28, 72.0)));
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: Colors.white.withValues(alpha: opacity),
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout(maxWidth: width * 0.9);
    painter.paint(
      canvas,
      Offset((minX + maxX) / 2 - painter.width / 2, (minY + maxY) / 2 - painter.height / 2),
    );
  }

  void _paintSeats(Canvas canvas, double visibility) {
    final orderedSeats = [...seats]
      ..sort((a, b) {
        int priority(SeatModel seat) {
          if (seat.status == SeatStatus.available) return 0;
          if (seat.status == SeatStatus.reserved) return 1;
          return 2;
        }
        return priority(a).compareTo(priority(b));
      });
    for (final s in orderedSeats) {
      final x = tx(s);
      final y = ty(s);
      final isSelected = selectedPlaceIds.contains(s.placeId);
      var color = seatColor(s, isSelected);
      final isWheelchair = s.tags.contains('wheelchair');
      if (s.status == SeatStatus.sold || s.status == SeatStatus.reserved) {
        color = color.withValues(alpha: 0.5);
      }
      color = color.withValues(alpha: color.a * visibility);
      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(x, y), seatRadius, paint);
      if (isSelected || isWheelchair) {
        final stroke = Paint()
          ..color = (isWheelchair ? const Color(0xFF9333ea) : Colors.white).withValues(alpha: visibility)
          ..style = PaintingStyle.stroke
          ..strokeWidth = seatRadius * 0.4;
        canvas.drawCircle(Offset(x, y), seatRadius, stroke);
      }
    }
  }

  void _paintRowLabels(Canvas canvas) {
    final focusId = focusedSectionId;
    if (focusId == null || focusId.isEmpty) return;
    SectionModel? section;
    for (final item in sections) {
      if (item.id == focusId) {
        section = item;
        break;
      }
    }
    if (section == null) return;
    final name = section.name.trim().toLowerCase();
    final id = section.id.trim().toLowerCase();
    final firstByRow = <String, Offset>{};
    for (final seat in seats) {
      final key = (seat.section ?? '').trim().toLowerCase();
      final row = seat.row;
      if (row == null || row.isEmpty) continue;
      if (key.isEmpty || (key != name && key != id)) continue;
      final point = Offset(tx(seat), ty(seat));
      final existing = firstByRow[row];
      if (existing == null || point.dx < existing.dx) {
        firstByRow[row] = point;
      }
    }
    final style = TextStyle(
      color: const Color(0xFF111827),
      fontSize: math.max(12, seatRadius * 1.6),
      fontWeight: FontWeight.w700,
    );
    for (final entry in firstByRow.entries) {
      final painter = TextPainter(
        text: TextSpan(text: entry.key, style: style),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(
        canvas,
        Offset(entry.value.dx - seatRadius - 8 - painter.width, entry.value.dy - painter.height / 2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SeatMapPainter oldDelegate) {
    return oldDelegate.seats != seats ||
        oldDelegate.selectedPlaceIds != selectedPlaceIds ||
        oldDelegate.seatRadius != seatRadius ||
        oldDelegate.sections != sections ||
        oldDelegate.focusedSectionId != focusedSectionId ||
        oldDelegate.overviewScale != overviewScale ||
        oldDelegate.transformedSectionPolygons != transformedSectionPolygons;
  }
}

Color sectionColorWithOpacity(String hexColor, double opacity) {
  final hex = hexColor.replaceAll('#', '').trim();
  if (hex.length != 6) return Colors.blue.withValues(alpha: opacity);
  final val = int.parse(hex, radix: 16);
  final r = (val >> 16) & 0xFF;
  final g = (val >> 8) & 0xFF;
  final b = val & 0xFF;
  return Color.fromARGB((opacity * 255).round().clamp(0, 255), r, g, b);
}
