# LPtown
 A simple LP model of a district heating system, written in Julia/JuMP.

# Installation
Install and run Julia. Then copy/paste/type this at the prompt:

```
julia> using Pkg; Pkg.add(url="https://github.com/niclasmattsson/LPtown")
```

# Usage

The first time you run the model there will be delay of 30 seconds or so while the code is compiling. Subsequent runs should be instantaneous.

```
julia> using LPtown

julia> runmodel()

Coin0506I Presolve 21 (-61) rows, 39 (-36) columns and 69 (-183) elements
Clp0006I 0  Obj 0 Primal inf 4478.0003 (9)
Clp0006I 21  Obj 527.47197
Clp0000I Optimal - objective value 527.47197
Coin0511I After Postsolve, objective 527.47197, infeasibilities - dual 0 (0), primal 0 (0)
Clp0032I Optimal objective 527.4719717 - 21 iterations time 0.012, Presolve 0.01
┌──────────┬─────────┐
│          │  Invest │
│          │    [MW] │
├──────────┼─────────┤
│   woodHP │     0.0 │
│  wasteHP │     0.0 │
│    oilHP │     0.0 │
│ heatpump │     0.0 │
│   gasCHP │     0.0 │
│  woodCHP │ 264.932 │
└──────────┴─────────┘
┌─────────────┬─────────────────────┐
│             │ Shadow price Demand │
│             │            [kr/MWh] │
├─────────────┼─────────────────────┤
│   winterday │             240.014 │
│ winternight │             240.014 │
│   summerday │                70.0 │
│ summernight │                50.0 │
│    otherday │             182.778 │
│  othernight │             212.778 │
└─────────────┴─────────────────────┘
┌───────────────────────┬───────────┬─────────────┬───────────┬─────────────┬──────────┬────────────┐
│ Shadow price Capacity │ winterday │ winternight │ summerday │ summernight │ otherday │ othernight │
│                       │  [kr/MWh] │    [kr/MWh] │  [kr/MWh] │    [kr/MWh] │ [kr/MWh] │   [kr/MWh] │
├───────────────────────┼───────────┼─────────────┼───────────┼─────────────┼──────────┼────────────┤
│                woodHP │       0.0 │         0.0 │       0.0 │         0.0 │      0.0 │        0.0 │
│               wasteHP │       0.0 │         0.0 │     -20.0 │         0.0 │      0.0 │      -30.0 │
│                 oilHP │       0.0 │         0.0 │       0.0 │         0.0 │      0.0 │        0.0 │
│              heatpump │  -90.0144 │    -127.514 │       0.0 │         0.0 │ -82.7778 │     -135.0 │
│                gasCHP │  -173.348 │    -23.3477 │       0.0 │         0.0 │      0.0 │        0.0 │
│               woodCHP │  -102.237 │    -57.2366 │       0.0 │         0.0 │      0.0 │        0.0 │
└───────────────────────┴───────────┴─────────────┴───────────┴─────────────┴──────────┴────────────┘
┌────────────────┬───────────┬─────────────┬───────────┬─────────────┬──────────┬────────────┐
│ HeatProduction │ winterday │ winternight │ summerday │ summernight │ otherday │ othernight │
│                │     [GWh] │       [GWh] │     [GWh] │       [GWh] │    [GWh] │      [GWh] │
├────────────────┼───────────┼─────────────┼───────────┼─────────────┼──────────┼────────────┤
│         woodHP │       0.0 │         0.0 │       0.0 │         0.0 │      0.0 │        0.0 │
│        wasteHP │   224.614 │     112.307 │    234.24 │     102.681 │  217.999 │     116.16 │
│          oilHP │       0.0 │         0.0 │       0.0 │         0.0 │      0.0 │        0.0 │
│       heatpump │    429.44 │      214.72 │     58.56 │     43.7195 │   425.92 │     212.96 │
│         gasCHP │     585.6 │       292.8 │       0.0 │         0.0 │      0.0 │        0.0 │
│        woodCHP │   517.146 │     258.573 │       0.0 │         0.0 │  227.281 │     203.28 │
└────────────────┴───────────┴─────────────┴───────────┴─────────────┴──────────┴────────────┘
┌─────────────────────────────┬───────────┬─────────────┬─────────────┬─────────────┬──────────┬────────────┐
│ Reduced cost HeatProduction │ winterday │ winternight │   summerday │ summernight │ otherday │ othernight │
│                             │  [kr/MWh] │    [kr/MWh] │    [kr/MWh] │    [kr/MWh] │ [kr/MWh] │   [kr/MWh] │
├─────────────────────────────┼───────────┼─────────────┼─────────────┼─────────────┼──────────┼────────────┤
│                      woodHP │   4.43004 │     4.43004 │     174.444 │     194.444 │  61.6667 │    31.6667 │
│                     wasteHP │       0.0 │         0.0 │ 6.93889e-15 │         0.0 │      0.0 │        0.0 │
│                       oilHP │   371.097 │     371.097 │     541.111 │     561.111 │  428.333 │    398.333 │
│                    heatpump │       0.0 │ 1.38778e-14 │         0.0 │         0.0 │      0.0 │        0.0 │
│                      gasCHP │       0.0 │ 5.55112e-14 │     246.667 │     366.667 │  33.8889 │    103.889 │
│                     woodCHP │       0.0 │         0.0 │     142.778 │     192.778 │      0.0 │        0.0 │
└─────────────────────────────┴───────────┴─────────────┴─────────────┴─────────────┴──────────┴────────────┘


Solve status: OPTIMAL

Objective [Mkr]: 527.4719716636439
CO2emissions [Mton CO2/year]: 0.2659002648401827
Reduced costs CO2emissions [kr/ton CO2]: 0.0

julia>

```
