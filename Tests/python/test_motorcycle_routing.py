import sys
import unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'scripts' / 'routing'))
from motorcycle import Way, Restriction, UnsupportedData, build_graph, shortest_route, parse_restriction

class RoutingTests(unittest.TestCase):
    def setUp(self):
        self.nodes = {1:(21, 105), 2:(21, 105.001), 3:(21, 105.002), 4:(21.001, 105.001)}
    def graph(self, ways):
        return build_graph(self.nodes, ways)
    def test_oneway_and_reverse(self):
        for tag in ('yes', '-1'):
            g = self.graph([Way(1, (1, 2), {'highway':'residential', 'oneway':tag})])
            self.assertEqual(shortest_route(g, 1, 2) is not None, tag == 'yes')
            self.assertEqual(shortest_route(g, 2, 1) is not None, tag == '-1')
    def test_motorway_and_motorcycle_no_are_excluded(self):
        g = self.graph([Way(1,(1,2),{'highway':'motorway'}), Way(2,(2,3),{'highway':'primary','motorcycle':'no'})])
        self.assertIsNone(shortest_route(g, 1, 2)); self.assertIsNone(shortest_route(g, 2, 3))
    def test_access_override(self):
        g = self.graph([Way(1,(1,2),{'highway':'residential','access':'no','motorcycle':'yes'})])
        self.assertIsNotNone(shortest_route(g,1,2))
    def test_conditional_access_excluded(self):
        g = self.graph([Way(1,(1,2),{'highway':'residential','motorcycle:conditional':'no @ (Mo-Fr)'})])
        self.assertIsNone(shortest_route(g,1,2))
    def test_no_turn_requires_alternative(self):
        ways = [Way(10,(1,2),{'highway':'residential'}), Way(20,(2,3),{'highway':'residential'}), Way(30,(2,4,3),{'highway':'residential'})]
        route = shortest_route(self.graph(ways),1,3,[Restriction(10,2,20,'no_right_turn')])
        self.assertIsNotNone(route)
        self.assertEqual([edge[2] for edge in route[1]], [10,30,30])
    def test_only_turn_and_no_path(self):
        g = self.graph([Way(10,(1,2),{'highway':'residential'}),Way(20,(2,3),{'highway':'residential'})])
        self.assertIsNone(shortest_route(g,1,3,[Restriction(10,2,30,'only_right_turn')]))
    def test_unknown_or_via_way_restrictions_fail_closed(self):
        members = [{'role':'from','type':'w','ref':10},{'role':'via','type':'w','ref':30},{'role':'to','type':'w','ref':20}]
        with self.assertRaises(UnsupportedData): parse_restriction({'type':'restriction','restriction':'no_right_turn'},members)
        with self.assertRaises(UnsupportedData): parse_restriction({'type':'restriction','restriction:conditional':'no_right_turn @ (Mo-Fr)'},members)
        with self.assertRaises(UnsupportedData): parse_restriction({'type':'restriction','restriction':'no_u_turn'},members)
    def test_exemption(self):
        self.assertIsNone(parse_restriction({'type':'restriction','restriction':'no_right_turn','except':'bus;motorcycle'},[]))
    def test_disconnected_graph(self):
        self.assertIsNone(shortest_route(self.graph([]),1,3))

if __name__ == '__main__': unittest.main()
