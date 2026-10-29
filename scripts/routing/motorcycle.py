"""Reference motorcycle route core. NOT production navigation.

This deliberately rejects unsupported conditional and via-way restrictions rather
than silently treating them as permitted. It is not yet connected to the app.
"""
from dataclasses import dataclass
from heapq import heappop, heappush
from math import asin, cos, radians, sin, sqrt


class UnsupportedData(ValueError):
    pass


@dataclass(frozen=True)
class Way:
    id: int
    nodes: tuple[int, ...]
    tags: dict


@dataclass(frozen=True)
class Restriction:
    from_way: int
    via_node: int
    to_way: int
    kind: str


@dataclass(frozen=True)
class Edge:
    end: int
    way_id: int
    meters: float


def _distance(a, b):
    lat1, lon1 = map(radians, a)
    lat2, lon2 = map(radians, b)
    h = sin((lat2-lat1)/2)**2 + cos(lat1)*cos(lat2)*sin((lon2-lon1)/2)**2
    return 12_742_000 * asin(min(1, sqrt(h)))


def _eligible(tags):
    highway = tags.get('highway', '')
    # Positive allowlist; service roads are permitted only absent restrictive tags.
    allowed = {'trunk', 'trunk_link', 'primary', 'primary_link', 'secondary',
               'secondary_link', 'tertiary', 'tertiary_link', 'unclassified',
               'residential', 'living_street', 'service', 'road'}
    if highway not in allowed: return False
    if any(k.endswith(':conditional') and k.split(':')[0] in
           {'access', 'vehicle', 'motor_vehicle', 'motorcycle', 'oneway'} for k in tags):
        return False
    # More specific tags override less specific ones, but unknown/private values
    # are rejected instead of guessing access.
    for key in ('motorcycle', 'motor_vehicle', 'vehicle', 'access'):
        if key in tags:
            return tags[key] in {'yes', 'permissive', 'designated'}
    return True


def _directions(tags):
    val = tags.get('oneway:motorcycle', tags.get('oneway', ''))
    if val in ('yes', '1', 'true'): return (True, False)
    if val in ('-1', 'reverse'): return (False, True)
    if val in ('no', '0', 'false'): return (True, True)
    if val: return (False, False)  # unknown values are not treated as two-way
    if tags.get('junction') in ('roundabout', 'circular'): return (True, False)
    return (True, True)


def build_graph(nodes, ways):
    graph = {}
    for way in ways:
        if not _eligible(way.tags): continue
        forward, backward = _directions(way.tags)
        for left, right in zip(way.nodes, way.nodes[1:]):
            if left not in nodes or right not in nodes: continue
            d = _distance(nodes[left], nodes[right])
            if forward: graph.setdefault(left, []).append(Edge(right, way.id, d))
            if backward: graph.setdefault(right, []).append(Edge(left, way.id, d))
    return graph


def parse_restriction(tags, members):
    if tags.get('type') != 'restriction': raise UnsupportedData('Unknown restriction type')
    # Conditional restrictions need local time and conditional grammar; reject for now.
    if any(k.startswith('restriction') and k.endswith(':conditional') for k in tags):
        raise UnsupportedData('Conditional restriction')
    exceptions = {x.strip() for x in tags.get('except', '').split(';')}
    if 'motorcycle' in exceptions: return None
    kind = tags.get('restriction:motorcycle', tags.get('restriction', ''))
    if kind in ('no_u_turn', 'only_u_turn'):
        raise UnsupportedData('U-turn restrictions need directed edge state')
    if not (kind.startswith('no_') or kind.startswith('only_')):
        raise UnsupportedData('Unknown restriction value')
    def find(role, typ):
        values = [m['ref'] for m in members if m['role'] == role and m['type'] == typ]
        if len(values) != 1: raise UnsupportedData('Unsupported relation members')
        return values[0]
    if len(members) != 3: raise UnsupportedData('Unsupported relation members')
    return Restriction(find('from', 'w'), find('via', 'n'), find('to', 'w'), kind)


def shortest_route(graph, start, end, restrictions=()):
    """Dijkstra over (node, incoming way); costs are distance, not travel time."""
    blocks, only = {}, {}
    for r in restrictions:
        if r is None: continue
        key = (r.via_node, r.from_way)
        if r.kind.startswith('no_'): blocks.setdefault(key, set()).add(r.to_way)
        elif r.kind.startswith('only_'): only.setdefault(key, set()).add(r.to_way)
        else: raise UnsupportedData('Unknown restriction value')
    start_state = (start, None)
    distances = {start_state: 0.0}
    previous = {}
    queue = [(0.0, 0, start_state)]
    serial = 0
    while queue:
        cost, _, state = heappop(queue)
        if cost != distances[state]: continue
        node, incoming = state
        if node == end:
            path = []
            while state != start_state:
                old, edge = previous[state]
                path.append((old[0], edge.end, edge.way_id))
                state = old
            return cost, list(reversed(path))
        key = (node, incoming)
        for edge in graph.get(node, ()):
            if edge.way_id in blocks.get(key, ()): continue
            if key in only and edge.way_id not in only[key]: continue
            next_state = (edge.end, edge.way_id)
            new_cost = cost + edge.meters
            if new_cost < distances.get(next_state, float('inf')):
                distances[next_state] = new_cost
                previous[next_state] = (state, edge)
                serial += 1
                heappush(queue, (new_cost, serial, next_state))
    return None
