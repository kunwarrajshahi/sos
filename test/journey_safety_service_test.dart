import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:safe_route/controllers/heatmap_controller.dart';
import 'package:safe_route/services/journey_safety_service.dart';
import 'package:safe_route/services/routing_service.dart';

void main() {
  group('JourneySafetyService', () {
    final zone = UnsafeZone(
      id: 'zone-1',
      point: const LatLng(28.61395, 77.20905),
      reason: 'Harassment',
      timeStart: '20:00',
      timeEnd: '23:00',
    );

    test(
      'doesRouteIntersectDangerZone returns true when route crosses zone',
      () {
        final route = [
          const LatLng(28.6137, 77.2088),
          const LatLng(28.6142, 77.2093),
        ];

        final intersects = JourneySafetyService.doesRouteIntersectDangerZone(
          route,
          [zone],
          bufferMeters: 120,
        );

        expect(intersects, isTrue);
      },
    );

    test('calculateRouteRisk increases for intersecting routes', () {
      final riskyRoute = [
        const LatLng(28.6137, 77.2088),
        const LatLng(28.6142, 77.2093),
      ];
      final safeRoute = [
        const LatLng(28.6120, 77.2050),
        const LatLng(28.6125, 77.2055),
      ];

      final risky = JourneySafetyService.calculateRouteRisk(riskyRoute, [
        zone,
      ], userLocation: const LatLng(28.6138, 77.2089));
      final safe = JourneySafetyService.calculateRouteRisk(safeRoute, [
        zone,
      ], userLocation: const LatLng(28.6121, 77.2051));

      expect(risky.score, greaterThan(safe.score));
      expect(risky.intersectsDangerZone, isTrue);
    });

    test('calculateDetourRatio compares candidate against shortest route', () {
      const shortest = RouteSummary(
        points: [LatLng(28.6120, 77.2050), LatLng(28.6125, 77.2055)],
        distanceMeters: 1000,
        durationSeconds: 180,
      );
      const longer = RouteSummary(
        points: [LatLng(28.6120, 77.2050), LatLng(28.6135, 77.2075)],
        distanceMeters: 1280,
        durationSeconds: 240,
      );

      final ratio = JourneySafetyService.calculateDetourRatio(longer, shortest);

      expect(ratio, closeTo(1.28, 0.01));
    });

    test('getAdaptiveDangerBuffer scales by zone severity', () {
      expect(JourneySafetyService.getAdaptiveDangerBuffer(1.0), 260);
      expect(JourneySafetyService.getAdaptiveDangerBuffer(0.82), 140);
      expect(JourneySafetyService.getAdaptiveDangerBuffer(0.6), 80);
    });

    test('selectBalancedSafeRoute prefers practical safe route', () {
      final candidates = [
        JourneySafetyCandidate(
          route: const RouteSummary(
            points: [LatLng(28.6137, 77.2088), LatLng(28.6142, 77.2093)],
            distanceMeters: 1000,
            durationSeconds: 180,
          ),
          risk: const JourneyRiskResult(
            score: 82,
            nearestDangerDistanceMeters: 20,
            nearbyDangerCount: 1,
            intersectsDangerZone: true,
          ),
          viaPoints: const [],
        ),
        JourneySafetyCandidate(
          route: const RouteSummary(
            points: [LatLng(28.6120, 77.2050), LatLng(28.6125, 77.2055)],
            distanceMeters: 1200,
            durationSeconds: 240,
          ),
          risk: const JourneyRiskResult(
            score: 24,
            nearestDangerDistanceMeters: 500,
            nearbyDangerCount: 0,
            intersectsDangerZone: false,
          ),
          viaPoints: const [],
        ),
        JourneySafetyCandidate(
          route: const RouteSummary(
            points: [LatLng(28.6110, 77.2040), LatLng(28.6165, 77.2140)],
            distanceMeters: 2600,
            durationSeconds: 480,
          ),
          risk: const JourneyRiskResult(
            score: 10,
            nearestDangerDistanceMeters: 800,
            nearbyDangerCount: 0,
            intersectsDangerZone: false,
          ),
          viaPoints: const [],
        ),
      ];

      final safest = JourneySafetyService.selectBalancedSafeRoute(candidates, [
        zone,
      ]);

      expect(safest, isNotNull);
      expect(safest!.candidate.route.distanceMeters, 1200);
      expect(safest.warningMessage, contains('Safer route'));
    });

    test(
      'calculateDangerZonePenalty heavily penalizes actual zone crossing',
      () {
        const crossingRoute = RouteSummary(
          points: [LatLng(28.6137, 77.2088), LatLng(28.6142, 77.2093)],
          distanceMeters: 1000,
          durationSeconds: 180,
        );
        const nearbyRoute = RouteSummary(
          points: [LatLng(28.6122, 77.2070), LatLng(28.6125, 77.2072)],
          distanceMeters: 980,
          durationSeconds: 170,
        );

        final crossingPenalty = JourneySafetyService.calculateDangerZonePenalty(
          crossingRoute,
          [zone],
        );
        final nearbyPenalty = JourneySafetyService.calculateDangerZonePenalty(
          nearbyRoute,
          [zone],
        );

        expect(crossingPenalty, greaterThan(nearbyPenalty));
      },
    );

    test('getFloatingButtonOffsets keeps vertical ordering stable', () {
      final offsets = JourneySafetyService.getFloatingButtonOffsets(
        isTripActive: true,
        hasResponderCard: false,
        screenHeight: 720,
        safeBottomPadding: 12,
      );

      expect(offsets.locationBottom, greaterThan(offsets.sosBottom));
      expect(offsets.riskBottom, greaterThan(offsets.locationBottom));
      expect(offsets.journeyPanelBottom, greaterThan(0));
    });
  });
}
