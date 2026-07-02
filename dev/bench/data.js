window.BENCHMARK_DATA = {
  "lastUpdate": 1783016104786,
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
      },
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
          "id": "149cd0b88050f0bfe96b953f8dc39d6b8c4cdb25",
          "message": "ai intro, part 3 exercises, claude code files",
          "timestamp": "2026-07-01T04:31:21Z",
          "tree_id": "78d26c220c6fa48f14ba23bc009b50efe07aee98",
          "url": "https://github.com/jane-street-immersion-program/jsip-exchange-part-3-group-b/commit/149cd0b88050f0bfe96b953f8dc39d6b8c4cdb25"
        },
        "date": 1782880568442,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "find_match (n=10)",
            "value": 21.549726420067564,
            "unit": "ns"
          },
          {
            "name": "find_match (n=50)",
            "value": 22.841222101651397,
            "unit": "ns"
          },
          {
            "name": "find_match (n=100)",
            "value": 23.889400534412907,
            "unit": "ns"
          },
          {
            "name": "find_match (n=500)",
            "value": 26.37282371331645,
            "unit": "ns"
          },
          {
            "name": "find_match_miss (n=10)",
            "value": 22.050400935065475,
            "unit": "ns"
          },
          {
            "name": "find_match_miss (n=50)",
            "value": 23.290847919716008,
            "unit": "ns"
          },
          {
            "name": "find_match_miss (n=100)",
            "value": 24.248938423200524,
            "unit": "ns"
          },
          {
            "name": "find_match_miss (n=500)",
            "value": 26.689947034951206,
            "unit": "ns"
          },
          {
            "name": "best_bid_offer (n=10)",
            "value": 151.3048947165609,
            "unit": "ns"
          },
          {
            "name": "best_bid_offer (n=50)",
            "value": 605.1291781768156,
            "unit": "ns"
          },
          {
            "name": "best_bid_offer (n=100)",
            "value": 1192.2258134272533,
            "unit": "ns"
          },
          {
            "name": "best_bid_offer (n=500)",
            "value": 5847.540614438333,
            "unit": "ns"
          },
          {
            "name": "add+remove (n=100)",
            "value": 398.2120185452772,
            "unit": "ns"
          },
          {
            "name": "submit_ioc_cross (n=10)",
            "value": 114.92514254450923,
            "unit": "ns"
          },
          {
            "name": "submit_ioc_cross (n=50)",
            "value": 121.19493897115977,
            "unit": "ns"
          },
          {
            "name": "submit_ioc_cross (n=100)",
            "value": 121.50315778904739,
            "unit": "ns"
          },
          {
            "name": "submit_ioc_cross (n=500)",
            "value": 119.72966454083046,
            "unit": "ns"
          },
          {
            "name": "submit_ioc_miss (n=10)",
            "value": 59.25688811406331,
            "unit": "ns"
          },
          {
            "name": "submit_ioc_miss (n=50)",
            "value": 59.595631288308304,
            "unit": "ns"
          },
          {
            "name": "submit_ioc_miss (n=100)",
            "value": 58.22508542890109,
            "unit": "ns"
          },
          {
            "name": "submit_ioc_miss (n=500)",
            "value": 58.41858627378047,
            "unit": "ns"
          },
          {
            "name": "submit_sweep_10_levels",
            "value": 7043.508556291653,
            "unit": "ns"
          },
          {
            "name": "submit_sweep_50_levels",
            "value": 67940.97816534282,
            "unit": "ns"
          },
          {
            "name": "submit_sweep_100_levels",
            "value": 200191.0972086182,
            "unit": "ns"
          },
          {
            "name": "find_match_alloc (n=100)",
            "value": 24.019215271724956,
            "unit": "ns"
          }
        ]
      },
      {
        "commit": {
          "author": {
            "email": "nigeltatem2@gmail.com",
            "name": "Nigel Tatem",
            "username": "NigelTatem"
          },
          "committer": {
            "email": "noreply@github.com",
            "name": "GitHub",
            "username": "web-flow"
          },
          "distinct": true,
          "id": "6b5165c8bb55aebe1924e5553e3fe6e5c29d7af7",
          "message": "reconcile digests (#1)",
          "timestamp": "2026-07-02T14:11:14-04:00",
          "tree_id": "8e71255e48fc53be07b6e27210f86734d7fb4535",
          "url": "https://github.com/jane-street-immersion-program/jsip-exchange-part-3-group-b/commit/6b5165c8bb55aebe1924e5553e3fe6e5c29d7af7"
        },
        "date": 1783016104350,
        "tool": "customSmallerIsBetter",
        "benches": [
          {
            "name": "find_match (n=10)",
            "value": 24.600555901402192,
            "unit": "ns"
          },
          {
            "name": "find_match (n=50)",
            "value": 24.519203180669848,
            "unit": "ns"
          },
          {
            "name": "find_match (n=100)",
            "value": 26.358940963986303,
            "unit": "ns"
          },
          {
            "name": "find_match (n=500)",
            "value": 29.97223605417954,
            "unit": "ns"
          },
          {
            "name": "find_match_miss (n=10)",
            "value": 25.258602644950503,
            "unit": "ns"
          },
          {
            "name": "find_match_miss (n=50)",
            "value": 26.6299475355405,
            "unit": "ns"
          },
          {
            "name": "find_match_miss (n=100)",
            "value": 26.152905442095705,
            "unit": "ns"
          },
          {
            "name": "find_match_miss (n=500)",
            "value": 30.030839609757624,
            "unit": "ns"
          },
          {
            "name": "best_bid_offer (n=10)",
            "value": 168.5774298123371,
            "unit": "ns"
          },
          {
            "name": "best_bid_offer (n=50)",
            "value": 697.0394449394997,
            "unit": "ns"
          },
          {
            "name": "best_bid_offer (n=100)",
            "value": 1358.6430387529215,
            "unit": "ns"
          },
          {
            "name": "best_bid_offer (n=500)",
            "value": 6730.968898809111,
            "unit": "ns"
          },
          {
            "name": "add+remove (n=100)",
            "value": 410.1519769406464,
            "unit": "ns"
          },
          {
            "name": "submit_ioc_cross (n=10)",
            "value": 116.71942158465193,
            "unit": "ns"
          },
          {
            "name": "submit_ioc_cross (n=50)",
            "value": 118.28949797330293,
            "unit": "ns"
          },
          {
            "name": "submit_ioc_cross (n=100)",
            "value": 120.25350099968647,
            "unit": "ns"
          },
          {
            "name": "submit_ioc_cross (n=500)",
            "value": 121.2640880730958,
            "unit": "ns"
          },
          {
            "name": "submit_ioc_miss (n=10)",
            "value": 57.419011937259754,
            "unit": "ns"
          },
          {
            "name": "submit_ioc_miss (n=50)",
            "value": 58.78781348544511,
            "unit": "ns"
          },
          {
            "name": "submit_ioc_miss (n=100)",
            "value": 59.15166039064914,
            "unit": "ns"
          },
          {
            "name": "submit_ioc_miss (n=500)",
            "value": 59.11655221343876,
            "unit": "ns"
          },
          {
            "name": "submit_sweep_10_levels",
            "value": 7149.057469544347,
            "unit": "ns"
          },
          {
            "name": "submit_sweep_50_levels",
            "value": 66496.15131716827,
            "unit": "ns"
          },
          {
            "name": "submit_sweep_100_levels",
            "value": 218949.29500036174,
            "unit": "ns"
          },
          {
            "name": "find_match_alloc (n=100)",
            "value": 28.84156077309532,
            "unit": "ns"
          }
        ]
      }
    ]
  }
}