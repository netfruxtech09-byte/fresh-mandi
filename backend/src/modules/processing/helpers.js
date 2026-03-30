import { env } from '../../config/env.js';

export function normalizeFlatToken(raw) {
  const text = `${raw ?? ''}`.trim().toUpperCase();
  if (!text) return '';
  const number = text.match(/\d+/)?.[0] ?? '';
  if (number) {
    const n = Number(number);
    if (Number.isFinite(n)) return `${n}`.padStart(3, '0');
  }
  return text;
}

export function inferFloorAndFlat(line1) {
  const text = `${line1 ?? ''}`;
  const floorMatch = text.match(/(?:floor|flr|fl)\s*[-:]?\s*(\d+)/i);
  const flatMatch = text.match(/(?:flat|apt|apartment|unit)\s*[-:]?\s*([a-z0-9-]+)/i);
  const fallbackNumber = text.match(/\b(\d{1,4})\b/)?.[1] ?? '';
  const floor = floorMatch ? Number(floorMatch[1]) : Math.floor((Number(fallbackNumber) || 0) / 100);
  const flat = flatMatch?.[1] ?? fallbackNumber;
  return {
    floorNumber: Number.isFinite(floor) ? floor : 0,
    flatNumber: normalizeFlatToken(flat),
  };
}

export function expectedBarcodeForOrder(order) {
  const ref = `${order?.customer_ref ?? ''}`.trim();
  if (ref) return ref.toUpperCase();
  return `ORD-${order.id}`;
}

export function parseCoordinate(value) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

export function haversineKm(a, b) {
  const lat1 = parseCoordinate(a?.latitude);
  const lon1 = parseCoordinate(a?.longitude);
  const lat2 = parseCoordinate(b?.latitude);
  const lon2 = parseCoordinate(b?.longitude);
  if ([lat1, lon1, lat2, lon2].some((v) => v == null)) return 0;

  const toRad = (deg) => (deg * Math.PI) / 180;
  const dLat = toRad(lat2 - lat1);
  const dLon = toRad(lon2 - lon1);
  const q =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLon / 2) ** 2;
  return 6371 * 2 * Math.atan2(Math.sqrt(q), Math.sqrt(1 - q));
}

function nearestNeighbor(points) {
  if (points.length <= 2) return points;
  const remaining = [...points];
  const ordered = [remaining.shift()];

  while (remaining.length) {
    const current = ordered[ordered.length - 1];
    let bestIndex = 0;
    let bestDistance = Number.POSITIVE_INFINITY;

    for (let i = 0; i < remaining.length; i++) {
      const nextDistance = haversineKm(current, remaining[i]);
      if (nextDistance < bestDistance) {
        bestDistance = nextDistance;
        bestIndex = i;
      }
    }

    ordered.push(remaining.splice(bestIndex, 1)[0]);
  }

  return ordered;
}

export async function optimizeIndependentStops(points) {
  const cleanPoints = points.filter(
    (item) => parseCoordinate(item.latitude) != null && parseCoordinate(item.longitude) != null,
  );
  if (cleanPoints.length < 2) {
    return { ordered: points, optimized: false, totalDistanceKm: 0, estimatedTimeMinutes: 0 };
  }

  if (env.googleMapsApiKey) {
    try {
      const ordered = await optimizeViaGoogle(cleanPoints);
      const metrics = estimateRouteMetrics(ordered);
      return { ordered, optimized: true, ...metrics };
    } catch {
      // Fall back locally when Google API is not reachable or not configured correctly.
    }
  }

  const ordered = nearestNeighbor(cleanPoints);
  const metrics = estimateRouteMetrics(ordered);
  const byId = new Map(ordered.map((item, index) => [item.id, { ...item, optimized_index: index }]));
  return {
    ordered: points
      .map((item) => byId.get(item.id) ?? item)
      .sort((a, b) => (a.optimized_index ?? Number.MAX_SAFE_INTEGER) - (b.optimized_index ?? Number.MAX_SAFE_INTEGER)),
    optimized: false,
    ...metrics,
  };
}

async function optimizeViaGoogle(points) {
  const body = {
    origin: {
      location: {
        latLng: {
          latitude: parseCoordinate(points[0].latitude),
          longitude: parseCoordinate(points[0].longitude),
        },
      },
    },
    destination: {
      location: {
        latLng: {
          latitude: parseCoordinate(points[points.length - 1].latitude),
          longitude: parseCoordinate(points[points.length - 1].longitude),
        },
      },
    },
    intermediates: points.slice(1, -1).map((item) => ({
      location: {
        latLng: {
          latitude: parseCoordinate(item.latitude),
          longitude: parseCoordinate(item.longitude),
        },
      },
    })),
    optimizeWaypointOrder: true,
    travelMode: 'DRIVE',
  };

  const response = await fetch(env.googleRouteOptimizationUrl, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'X-Goog-Api-Key': env.googleMapsApiKey,
      'X-Goog-FieldMask': 'routes.optimizedIntermediateWaypointIndex',
    },
    body: JSON.stringify(body),
  });

  if (!response.ok) {
    throw new Error(`Google optimization failed with ${response.status}`);
  }

  const payload = await response.json();
  const route = payload?.routes?.[0];
  const waypointOrder = route?.optimizedIntermediateWaypointIndex ?? [];
  const middle = points.slice(1, -1);
  return [
    points[0],
    ...waypointOrder.map((index) => middle[index]).filter(Boolean),
    points[points.length - 1],
  ];
}

export function estimateRouteMetrics(points) {
  let totalDistanceKm = 0;
  for (let i = 1; i < points.length; i++) {
    totalDistanceKm += haversineKm(points[i - 1], points[i]);
  }

  const estimatedTimeMinutes = Math.max(5, Math.round(totalDistanceKm * 4.5));
  return {
    totalDistanceKm: Number(totalDistanceKm.toFixed(2)),
    estimatedTimeMinutes,
  };
}

export function buildCrateCode(index) {
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  let value = index;
  let code = '';

  do {
    code = alphabet[value % 26] + code;
    value = Math.floor(value / 26) - 1;
  } while (value >= 0);

  return `CRATE-${code}`;
}

export function deriveCratesForStops(totalStops, capacity = env.processingCrateCapacity) {
  const safeCapacity = Math.max(1, capacity || 15);
  const crates = [];
  for (let start = 1, idx = 0; start <= totalStops; start += safeCapacity, idx++) {
    const stopTo = Math.min(start + safeCapacity - 1, totalStops);
    crates.push({
      crate_code: buildCrateCode(idx),
      stop_from: start,
      stop_to: stopTo,
      max_capacity: safeCapacity,
      current_orders: stopTo - start + 1,
    });
  }
  return crates;
}

export function routeTypeForOrders(orders) {
  const withBuildings = orders.filter((item) => item.building_id != null);
  if (withBuildings.length === orders.length && withBuildings.length > 0) return 'APARTMENT';
  if (withBuildings.length === 0) return 'INDEPENDENT';
  return 'MIXED';
}
