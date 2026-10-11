"""Distance helper shared by the pipeline steps."""

import math


def distance_m(lat1, lon1, lat2, lon2):
    """Great-circle distance in meters (haversine)."""
    r = 6371000
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp = p2 - p1
    dl = math.radians(lon2 - lon1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * r * math.asin(math.sqrt(a))


# Outlines (parks, ballparks, plazas). A ring is a closed list of [lat, lon] points; a stop's
# "area" is a list of rings (a multipolygon can have several outer parts). Math is done on a
# flat local projection in meters, which is plenty accurate across one place.

def _to_xy(lat, lon, lat0):
    """Meters east/north of (lat0, 0) on a flat local projection."""
    k = 111_195.0  # meters per degree of latitude
    return lon * k * math.cos(math.radians(lat0)), lat * k


def _segment_distance(px, py, ax, ay, bx, by):
    dx, dy = bx - ax, by - ay
    length2 = dx * dx + dy * dy
    t = 0.0 if length2 == 0 else max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / length2))
    return math.hypot(px - (ax + t * dx), py - (ay + t * dy))


def _inside(px, py, ring_xy):
    """Ray casting: is the point inside the closed ring?"""
    inside = False
    for (ax, ay), (bx, by) in zip(ring_xy, ring_xy[1:]):
        if (ay > py) != (by > py) and px < ax + (py - ay) * (bx - ax) / (by - ay):
            inside = not inside
    return inside


def distance_to_area_m(lat, lon, area):
    """0 inside any ring, otherwise the distance to the nearest edge."""
    px, py = _to_xy(lat, lon, lat)
    best = math.inf
    for ring in area:
        xy = [_to_xy(a, b, lat) for a, b in ring]
        if _inside(px, py, xy):
            return 0.0
        best = min(best, min(_segment_distance(px, py, *a, *b) for a, b in zip(xy, xy[1:])))
    return best


def distance_to_stop_m(lat, lon, stop):
    """How far a walker is from a stop: from its outline when it has one, else from its point."""
    if stop.get("area"):
        return distance_to_area_m(lat, lon, stop["area"])
    return distance_m(lat, lon, stop["lat"], stop["lon"])


def simplify_ring(ring, tolerance_m):
    """Douglas-Peucker: drop points that bend the outline by less than tolerance_m."""
    lat0 = ring[0][0]
    xy = [_to_xy(a, b, lat0) for a, b in ring]
    keep = [False] * len(ring)
    keep[0] = keep[-1] = True
    pending = [(0, len(ring) - 1)]
    while pending:
        first, last = pending.pop()
        worst, worst_d = None, tolerance_m
        for i in range(first + 1, last):
            d = _segment_distance(*xy[i], *xy[first], *xy[last])
            if d > worst_d:
                worst, worst_d = i, d
        if worst is not None:
            keep[worst] = True
            pending += [(first, worst), (worst, last)]
    return [p for p, k in zip(ring, keep) if k]
