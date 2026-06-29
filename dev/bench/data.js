window.BENCHMARK_DATA = {
  "lastUpdate": 1782722924588,
  "repoUrl": "https://github.com/jane-street-immersion-program/jsip-exchange-part-3-group-b",
  "entries": {
    "Order book benchmark": [
      {
        "commit": {
          "author": {
            "email": "abauer@janestreet.com",
            "name": "Aaron Bauer",
            "username": "awilliambauer"
          },
          "committer": {
            "email": "abauer@janestreet.com",
            "name": "Aaron Bauer",
            "username": "awilliambauer"
          },
          "distinct": true,
          "id": "a06b27e5d291368ffa6dd440247cd94d4358eb7b",
          "message": "github actions",
          "timestamp": "2026-06-29T08:44:08Z",
          "tree_id": "f7004ba9d4d7d0c64be978e8a80aa4249bc612c4",
          "url": "https://github.com/jane-street-immersion-program/jsip-exchange-part-3-group-b/commit/a06b27e5d291368ffa6dd440247cd94d4358eb7b"
        },
        "date": 1782722923906,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "find_match (n=10)",
            "value": 24.562698298714064,
            "unit": "ns"
          },
          {
            "name": "find_match (n=50)",
            "value": 26.153480824742136,
            "unit": "ns"
          },
          {
            "name": "find_match (n=100)",
            "value": 26.817066824973868,
            "unit": "ns"
          },
          {
            "name": "find_match (n=500)",
            "value": 29.871430193595046,
            "unit": "ns"
          },
          {
            "name": "find_match_miss (n=10)",
            "value": 25.9150716476742,
            "unit": "ns"
          },
          {
            "name": "find_match_miss (n=50)",
            "value": 27.352705064364972,
            "unit": "ns"
          },
          {
            "name": "find_match_miss (n=100)",
            "value": 28.064553724160092,
            "unit": "ns"
          },
          {
            "name": "find_match_miss (n=500)",
            "value": 30.891268467309644,
            "unit": "ns"
          },
          {
            "name": "best_bid_offer (n=10)",
            "value": 175.5690619247494,
            "unit": "ns"
          },
          {
            "name": "best_bid_offer (n=50)",
            "value": 745.5362870042463,
            "unit": "ns"
          },
          {
            "name": "best_bid_offer (n=100)",
            "value": 1461.11280888108,
            "unit": "ns"
          },
          {
            "name": "best_bid_offer (n=500)",
            "value": 7174.42603446613,
            "unit": "ns"
          },
          {
            "name": "add+remove (n=100)",
            "value": 409.75785561869174,
            "unit": "ns"
          },
          {
            "name": "submit_ioc_cross (n=10)",
            "value": 119.77338561976673,
            "unit": "ns"
          },
          {
            "name": "submit_ioc_cross (n=50)",
            "value": 123.21758084329196,
            "unit": "ns"
          },
          {
            "name": "submit_ioc_cross (n=100)",
            "value": 121.19610858283367,
            "unit": "ns"
          },
          {
            "name": "submit_ioc_cross (n=500)",
            "value": 123.68427991305552,
            "unit": "ns"
          },
          {
            "name": "submit_ioc_miss (n=10)",
            "value": 60.080095513545984,
            "unit": "ns"
          },
          {
            "name": "submit_ioc_miss (n=50)",
            "value": 60.18609679066782,
            "unit": "ns"
          },
          {
            "name": "submit_ioc_miss (n=100)",
            "value": 60.13060632445083,
            "unit": "ns"
          },
          {
            "name": "submit_ioc_miss (n=500)",
            "value": 60.141127940610914,
            "unit": "ns"
          },
          {
            "name": "submit_sweep_10_levels",
            "value": 7115.420626814541,
            "unit": "ns"
          },
          {
            "name": "submit_sweep_50_levels",
            "value": 66884.0930180184,
            "unit": "ns"
          },
          {
            "name": "submit_sweep_100_levels",
            "value": 212948.20518738645,
            "unit": "ns"
          },
          {
            "name": "find_match_alloc (n=100)",
            "value": 29.52985003561388,
            "unit": "ns"
          }
        ]
      }
    ]
  }
}