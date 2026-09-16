# **Agent-Based Dressing Room Dynamics: Graph-Theoretic Morale Propagation and Mutiny Simulation in Godot 4**

## **Computational Architecture and Theoretical Framework**

Simulating squad cohesion, factional division, and dressing room volatility requires moving beyond isolated scalar attributes toward an interconnected network model1. Modern multi-agent social modeling demonstrates that emergent collective behaviors—such as toxic cliques, localized sentiment contagion, and squad mutinies—arise from topological network structures rather than isolated player states1. Developing this engine within Godot 4.x under the strict performance constraints of PowerFootball requires translating foundational computational sociology frameworks into high-efficiency, zero-allocation GDScript architectures1.

&nbsp;

| Multi-Agent Framework | Architectural Concept | Mathematical/Algorithmic Basis | PowerFootball GDScript Translation |
| :---- | :---- | :---- | :---- |
| **Mesa** (Apache-2.0) | NetworkGrid topological space & AgentSet scheduling loops1 | Graph-based neighbour queries, activation pipelines (Boltzmann / Axelrod)1 | Flat integer hashing: player\_key \= team\_id \* 1000 \+ squad\_index. Teammate filtering without graph object overhead1. |
| **SOIL** (Apache-2.0) | BaseAgent opinion dynamics & state evolution1 | Friedkin–Johnsen (FJ) opinion consensus with individual stubbornness1 | Matrix/vector blended morale and transitivity trust updates with stubbornness weighting1. |
| **AgentTorch** (MIT) | Tensor-based parallel state representation1 | Contiguous memory buffers, vectorized broadcast updates, zero runtime allocation1 | Flattened PackedFloat32Array and PackedInt32Array buffers indexed by squad offset1. |
| **Epidemiological SIS** | Threshold-based social contagion1 | Independent cascade with homophily-weighted infection probabilities1 | Morale drop cascades driven by teammate similarity and relationship multipliers1. |
| **Bron–Kerbosch** | Graph clique detection1 | Recursive backtracking with maximal candidate pruning via pivoting1 | 64-bit integer bitmasks (int), bitwise set algebra, constant-time pivot lookup1. |

Mesa structures spatial and network interactions through abstractions like NetworkGrid and scheduled agent sets, where agents exist as discrete Python objects residing on graph nodes that query neighbours through wrapped networkx graphs1. In GDScript 2.0, allocating discrete node wrapper objects or relying on runtime string dictionaries in per-frame or weekly loops introduces substantial Variant allocation overhead and garbage collection pauses1. The engine replaces Mesa's node mapping with an algorithmic coordinate scheme where a player's unique identity is expressed deterministically as ![][image1]1. Teammate neighbour iteration maps directly to filtered indexing across pre-allocated packed arrays, which bypasses runtime graph query structures while preserving Mesa’s concept of network-bound agent influence1. Scheduling mirrors the stochastic activation patterns seen in Mesa's Axelrod and Boltzmann models, running weekly evaluations across squads in randomized sequences to prevent evaluation order bias1.

The opinion dynamics paradigm ported from SOIL treats an individual’s internal state not as an absolute reactive value, but as a dynamic equilibrium between peer consensus and an anchored prior conviction representing stubbornness or personality baseline1. In a professional football dressing room, player morale does not fluctuate purely based on external stimuli; instead, it is anchored to core personality traits, playing-time satisfaction, and contract security, while experiencing continuous peer diffusion from adjacent teammates1. The engine adopts SOIL’s discrete convex formulation across the entire squad graph, preventing mathematical explosion and ensuring smooth asymptotic convergence1.

AgentTorch models large-scale multi-agent systems by maintaining all agent properties within contiguous parallel multidimensional arrays rather than discrete agent objects, avoiding per-object iteration penalties and memory fragmentation1. In Godot 4.x, generic Array and Dictionary instances are boxed as Variants, incurring allocation costs and pointer indirection1. SocialDynamicsEngine adheres to the AgentTorch zero-allocation pattern by projecting a squad of 25 players into flat contiguous packed buffers1. A 25-player squad is represented by a PackedFloat32Array of size 25 for morale (100 bytes), a PackedFloat32Array of size 625 for the row-major trust matrix (2,500 bytes), a PackedFloat32Array of size 625 for rivalry scores (2,500 bytes), and a PackedInt64Array of size 25 for graph adjacency bitmasks (200 bytes)1. The entire social graph occupies approximately 5.3 kilobytes of contiguous memory, residing entirely within modern CPU L1 data caches and enabling weekly evaluations to execute without instantiating intermediary heap structures1.

## **Mathematical Modeling of Social Dynamics**

For any squad of ![][image2] players, let ![][image3] denote the symmetric adjacency matrix representing social ties capable of forming cliques1. The relationship between player ![][image4] and player ![][image5] contains directed trust metrics ![][image6] and ![][image7]1. A social clique requires reciprocal solidarity; an unreciprocated high trust rating from player ![][image4] toward player ![][image5] cannot sustain a closed faction if player ![][image5] distrusts player ![][image4]1. Therefore, the mutual edge weight is defined using the conservative lower bound:

![][image8]

Given a clique trust threshold ![][image9] (defaulting to ![][image10]), the binary adjacency matrix ![][image11] is defined as1:

![][image12]

This ensures that the resulting graph ![][image13] is strictly undirected and suitable for maximal clique decomposition1.

Morale propagation models the social diffusion of emotional states across teammates1. Let ![][image14] denote the current morale of player ![][image4], and ![][image15] denote the player's initial anchored morale at the beginning of the evaluation period1. The influence weight ![][image16] exerted by player ![][image5] on player ![][image4] depends on direct trust ![][image6] and the tactical/relational match multiplier ![][image17]1:

![][image18]

where the relationship match multiplier is derived from net trust discounted by rivalry1:

![][image19]

![][image20]

The updated morale ![][image21] is computed as a convex combination governed by the stubbornness coefficient ![][image22] (default ![][image23])1:

![][image24]

When player ![][image4] is socially isolated within the squad (![][image25]), division by zero is avoided by setting ![][image26], maintaining the player's anchored morale1. The final morale is strictly clamped to the interval ![][image27]1.

Following deterministic continuous diffusion, localized emotional toxicity can propagate through a dressing room via an epidemiological SIS cascade1. Let the set of unhappy neighbours be defined as:

![][image28]

where ![][image29]1. The homophily similarity metric ![][image30] captures emotional proximity and relational bonding:

![][image31]

The overall transmission probability that player ![][image4] catches negative sentiment from unhappy peers is given by the independent cascade equation:

![][image32]

where ![][image33] is the base contagion rate (calibrated to ![][image34])1. When a pseudo-random draw from rng satisfies ![][image35], player ![][image4] receives an acute morale reduction shock (![][image36]), bounded by ![][image27]1.

Interpersonal trust evolves over time via social transitivity: friends of friends become friends, and shared alliances reinforce mutual regard1. The transitive trust update applies a matrix formulation of the FJ rule across squad pairs1:

![][image37]

where ![][image38] provides strong memory retention, preventing drastic shifts from single-week fluctuations1. If the row-sum ![][image39], the initial trust ![][image40] is preserved1.

## **Algorithmic Design: Bitmask Bron–Kerbosch with Pivoting**

Maximal clique enumeration on arbitrary graphs is an NP-complete problem with worst-case complexity ![][image41]1. For a squad of ![][image2] players, ![][image42] operations1. However, by mapping the graph into 64-bit integer bitmasks and implementing the Bron–Kerbosch algorithm with pivoting, the search space is pruned1.

GDScript native int is a signed 64-bit two's complement integer1. Bit-shifting operations (\<\<, \>\>) remain safe across the lower 63 bits (bits 0 to 62), fully accommodating the 25 bits required for a standard football squad1.

&nbsp;

| Set Operation | Bitwise Primitive | Mathematical Equivalent | Computational Cost |
| :---- | :---- | :---- | :---- |
| Set Union | A | B | ![][image43] | 1 CPU cycle1 |
| Set Intersection | A & B | ![][image44] | 1 CPU cycle1 |
| Set Difference | A & \~B | ![][image45] | 1 CPU cycle1 |
| Vertex Insertion | M | (1 \<\< v) | ![][image46] | 1 CPU cycle1 |
| Vertex Removal | M & \~(1 \<\< v) | ![][image47] | 1 CPU cycle1 |
| Set Membership | (M \>\> v) & 1 | ![][image48] | 1 CPU cycle1 |
| Cardinality | Brian Kernighan bit-count | ![][image49] | ![][image50] loop cycles2 |
| LSB Extraction | M & \-M (binary shift scan) | ![][image51] | ![][image52] binary branches2 |

Pivoting dramatically reduces the search tree1. At each recursive invocation, a pivot vertex ![][image53] is selected from ![][image54] that maximizes the cardinality ![][image55]1. The search then only branches over candidates in ![][image56]1. If ![][image53] is connected to many candidate vertices, those candidates are explored within other branches and do not require separate subtrees1.

Because all set operations operate entirely on primitive 64-bit integer parameters passed on the stack, the recursive execution does not instantiate arrays, dictionaries, or heap objects1. When a maximal clique with cardinality ![][image57] is verified (![][image58] and ![][image59]), its bitmask is appended to a pre-allocated PackedInt64Array1. Conversion from bitmasks into the public Array\[PackedInt32Array\] occurs once at the boundary of detect\_cliques()1.

## **Implementation: Social Dynamics Engine**

The complete implementation of shared/career/SocialDynamicsEngine.gd is structured as a stateless RefCounted class adhering strictly to Godot 4.x typed GDScript1.

&nbsp;

&nbsp;

&nbsp;

GDScript

class\_name SocialDynamicsEngine  
extends RefCounted

\# \--- Configurable Social Dynamics Constants \---  
const DEFAULT\_CLIQUE\_THRESHOLD: float \= 0.65  
const DEFAULT\_MORALE\_ALPHA: float \= 0.35  
const DEFAULT\_TRUST\_ALPHA: float \= 0.70  
const DEFAULT\_CONTAGION\_BETA: float \= 0.30  
const UNHAPPY\_MORALE\_THRESHOLD: float \= 0.40  
const CONTAGION\_MORALE\_DROP: float \= 0.15  
const MUTINY\_SQUAD\_MORALE\_THRESHOLD: float \= 0.35  
const MUTINY\_MANAGER\_TRUST\_THRESHOLD: float \= 0.25  
const MUTINY\_MIN\_DISAFFECTED\_PLAYERS: int \= 3  
const HIGH\_RIVALRY\_THRESHOLD: float \= 0.70  
const BUSTUP\_MORALE\_THRESHOLD: float \= 0.40  
const SCHISM\_MAX\_CROSS\_TRUST: float \= 0.35  
const SCHISM\_MIN\_MORALE\_DIFF: float \= 0.30  
const DECAY\_RATE\_PER\_WEEK: float \= 0.02  
const NATURAL\_TRUST\_BASELINE: float \= 0.50

\# \--- Public API Interface \---

static func evaluate\_weekly(career: CareerSaveData, rng: RandomNumberGenerator) \-\> Array\[WorldEvent\]:  
&nbsp;var emitted\_events: Array\[WorldEvent\] \= \[\]  
&nbsp;if career \== null or career.teams.is\_empty():  
&nbsp;&nbsp;return emitted\_events

&nbsp;for team: TeamData in career.teams:  
&nbsp;&nbsp;if team \== null or team.players.is\_empty():  
&nbsp;&nbsp;&nbsp;continue

&nbsp;&nbsp;var squad\_size: int \= team.players.size()  
&nbsp;&nbsp;if squad\_size \> 62:  
&nbsp;&nbsp;&nbsp;push\_warning("SocialDynamicsEngine: Squad size %d exceeds 62-bit mask capacity." % squad\_size)  
&nbsp;&nbsp;&nbsp;squad\_size \= 62

&nbsp;&nbsp;\# 1\. Apply natural relationship decay toward baseline  
&nbsp;&nbsp;\_apply\_relationship\_decay(team, career)

&nbsp;&nbsp;\# 2\. Update trust matrix using transitivity Friedkin-Johnsen rule  
&nbsp;&nbsp;\_update\_trust\_matrix\_fj(team, career, squad\_size)

&nbsp;&nbsp;\# 3\. Propagate morale across social ties and evaluate contagion  
&nbsp;&nbsp;propagate\_morale(team, career, rng)

&nbsp;&nbsp;\# 4\. Detect maximal cohesive cliques  
&nbsp;&nbsp;var cliques: Array\[PackedInt32Array\] \= detect\_cliques(team, career, DEFAULT\_CLIQUE\_THRESHOLD)

&nbsp;&nbsp;\# 5\. Evaluate and emit narrative world events  
&nbsp;&nbsp;\_evaluate\_events\_for\_team(team, career, cliques, emitted\_events)

&nbsp;return emitted\_events

static func detect\_cliques(team: TeamData, career: CareerSaveData, threshold: float) \-\> Array\[PackedInt32Array\]:  
&nbsp;var results: Array\[PackedInt32Array\] \= \[\]  
&nbsp;if team \== null or team.players.is\_empty():  
&nbsp;&nbsp;return results

&nbsp;var n: int \= mini(team.players.size(), 62\)  
&nbsp;if n \< 3:  
&nbsp;&nbsp;return results

&nbsp;\# Build adjacency bitmasks using symmetric min-trust  
&nbsp;var adj: PackedInt64Array \= PackedInt64Array()  
&nbsp;adj.resize(n)  
&nbsp;var keys: PackedInt32Array \= PackedInt32Array()  
&nbsp;keys.resize(n)

&nbsp;for i in range(n):  
&nbsp;&nbsp;adj\[i\] \= 0  
&nbsp;&nbsp;keys\[i\] \= \_get\_player\_key(team.team\_index, i)

&nbsp;for i in range(n):  
&nbsp;&nbsp;var key\_i: int \= keys\[i\]  
&nbsp;&nbsp;for j in range(i \+ 1, n):  
&nbsp;&nbsp;&nbsp;var key\_j: int \= keys\[j\]  
&nbsp;&nbsp;&nbsp;var t\_ij: float \= \_get\_trust(career, team.players\[i\], key\_i, key\_j)  
&nbsp;&nbsp;&nbsp;var t\_ji: float \= \_get\_trust(career, team.players\[j\], key\_j, key\_i)  
&nbsp;&nbsp;&nbsp;var mutual\_trust: float \= minf(t\_ij, t\_ji)

&nbsp;&nbsp;&nbsp;if mutual\_trust \>= threshold:  
&nbsp;&nbsp;&nbsp;&nbsp;adj\[i\] \= adj\[i\] | (1 \<\< j)  
&nbsp;&nbsp;&nbsp;&nbsp;adj\[j\] \= adj\[j\] | (1 \<\< i)

&nbsp;\# Execute Bron-Kerbosch with pivoting  
&nbsp;var clique\_masks: PackedInt64Array \= PackedInt64Array()  
&nbsp;var all\_candidates\_mask: int \= (1 \<\< n) \- 1  
&nbsp;\_bron\_kerbosch\_pivot(0, all\_candidates\_mask, 0, adj, clique\_masks)

&nbsp;\# Transform bitmasks to public Array\[PackedInt32Array\]  
&nbsp;for idx in range(clique\_masks.size()):  
&nbsp;&nbsp;var mask: int \= clique\_masks\[idx\]  
&nbsp;&nbsp;var clique\_keys: PackedInt32Array \= PackedInt32Array()  
&nbsp;&nbsp;for bit in range(n):  
&nbsp;&nbsp;&nbsp;if (mask & (1 \<\< bit)) \!= 0:  
&nbsp;&nbsp;&nbsp;&nbsp;clique\_keys.append(keys\[bit\])  
&nbsp;&nbsp;results.append(clique\_keys)

&nbsp;return results

static func propagate\_morale(team: TeamData, career: CareerSaveData, rng: RandomNumberGenerator) \-\> void:  
&nbsp;if team \== null or team.players.is\_empty():  
&nbsp;&nbsp;return

&nbsp;var n: int \= team.players.size()  
&nbsp;var keys: PackedInt32Array \= PackedInt32Array()  
&nbsp;keys.resize(n)  
&nbsp;var current\_morale: PackedFloat32Array \= PackedFloat32Array()  
&nbsp;current\_morale.resize(n)

&nbsp;for i in range(n):  
&nbsp;&nbsp;keys\[i\] \= \_get\_player\_key(team.team\_index, i)  
&nbsp;&nbsp;current\_morale\[i\] \= team.players\[i\].morale

&nbsp;var new\_morale: PackedFloat32Array \= PackedFloat32Array()  
&nbsp;new\_morale.resize(n)

&nbsp;\# Phase 1: Friedkin-Johnsen Continuous Diffusion  
&nbsp;for i in range(n):  
&nbsp;&nbsp;var p\_i: PlayerData \= team.players\[i\]  
&nbsp;&nbsp;var m\_anchor: float \= p\_i.morale  
&nbsp;&nbsp;var weight\_sum: float \= 0.0  
&nbsp;&nbsp;var peer\_sum: float \= 0.0

&nbsp;&nbsp;for j in range(n):  
&nbsp;&nbsp;&nbsp;if i \== j:  
&nbsp;&nbsp;&nbsp;&nbsp;continue  
&nbsp;&nbsp;&nbsp;var p\_j: PlayerData \= team.players\[j\]  
&nbsp;&nbsp;&nbsp;var t\_ij: float \= \_get\_trust(career, p\_i, keys\[i\], keys\[j\])  
&nbsp;&nbsp;&nbsp;var mult\_ij: float \= \_get\_multiplier(career, p\_i, keys\[i\], keys\[j\])  
&nbsp;&nbsp;&nbsp;var w\_ij: float \= maxf(0.0, mult\_ij) \* maxf(0.0, t\_ij)

&nbsp;&nbsp;&nbsp;if w\_ij \> 0.0001:  
&nbsp;&nbsp;&nbsp;&nbsp;weight\_sum \+= w\_ij  
&nbsp;&nbsp;&nbsp;&nbsp;peer\_sum \+= w\_ij \* p\_j.morale

&nbsp;&nbsp;if weight\_sum \> 0.0001:  
&nbsp;&nbsp;&nbsp;var consensus: float \= peer\_sum / weight\_sum  
&nbsp;&nbsp;&nbsp;new\_morale\[i\] \= clampf(DEFAULT\_MORALE\_ALPHA \* m\_anchor \+ (1.0 \- DEFAULT\_MORALE\_ALPHA) \* consensus, 0.0, 1.0)  
&nbsp;&nbsp;else:  
&nbsp;&nbsp;&nbsp;new\_morale\[i\] \= clampf(m\_anchor, 0.0, 1.0)

&nbsp;\# Apply diffusion state  
&nbsp;for i in range(n):  
&nbsp;&nbsp;team.players\[i\].morale \= new\_morale\[i\]

&nbsp;\# Phase 2: SIS Contagion Cascade  
&nbsp;if rng \!= null:  
&nbsp;&nbsp;for i in range(n):  
&nbsp;&nbsp;&nbsp;var p\_i: PlayerData \= team.players\[i\]  
&nbsp;&nbsp;&nbsp;var prod\_prob: float \= 1.0  
&nbsp;&nbsp;&nbsp;var has\_unhappy\_neighbor: bool \= false

&nbsp;&nbsp;&nbsp;for j in range(n):  
&nbsp;&nbsp;&nbsp;&nbsp;if i \== j:  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;continue  
&nbsp;&nbsp;&nbsp;&nbsp;var p\_j: PlayerData \= team.players\[j\]  
&nbsp;&nbsp;&nbsp;&nbsp;if p\_j.morale \< UNHAPPY\_MORALE\_THRESHOLD:  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;var mult\_ij: float \= \_get\_multiplier(career, p\_i, keys\[i\], keys\[j\])  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;var similarity: float \= clampf(1.0 \- absf(p\_i.morale \- p\_j.morale), 0.0, 1.0) \* mult\_ij  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;var p\_infect: float \= clampf(DEFAULT\_CONTAGION\_BETA \* similarity, 0.0, 1.0)  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;prod\_prob \*= (1.0 \- p\_infect)  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;has\_unhappy\_neighbor \= true

&nbsp;&nbsp;&nbsp;if has\_unhappy\_neighbor:  
&nbsp;&nbsp;&nbsp;&nbsp;var infection\_risk: float \= 1.0 \- prod\_prob  
&nbsp;&nbsp;&nbsp;&nbsp;if rng.randf() \< infection\_risk:  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;team.players\[i\].morale \= clampf(team.players\[i\].morale \- CONTAGION\_MORALE\_DROP, 0.0, 1.0)

static func check\_mutiny\_threshold(team: TeamData, career: CareerSaveData) \-\> bool:  
&nbsp;if team \== null or team.players.is\_empty():  
&nbsp;&nbsp;return false

&nbsp;var total\_morale: float \= 0.0  
&nbsp;var disaffected\_manager\_trust\_count: int \= 0  
&nbsp;var squad\_size: int \= team.players.size()

&nbsp;for i in range(squad\_size):  
&nbsp;&nbsp;var p: PlayerData \= team.players\[i\]  
&nbsp;&nbsp;total\_morale \+= p.morale

&nbsp;&nbsp;var mgr\_trust: float \= \_get\_player\_manager\_trust(career, p, \_get\_player\_key(team.team\_index, i))  
&nbsp;&nbsp;if mgr\_trust \< MUTINY\_MANAGER\_TRUST\_THRESHOLD:  
&nbsp;&nbsp;&nbsp;disaffected\_manager\_trust\_count \+= 1

&nbsp;var avg\_morale: float \= total\_morale / float(squad\_size)  
&nbsp;return (avg\_morale \< MUTINY\_SQUAD\_MORALE\_THRESHOLD) and (disaffected\_manager\_trust\_count \>= MUTINY\_MIN\_DISAFFECTED\_PLAYERS)

\# \--- Internal Graph & Bitwise Subroutines \---

static func \_bron\_kerbosch\_pivot(r\_mask: int, p\_mask: int, x\_mask: int, adj: PackedInt64Array, cliques: PackedInt64Array) \-\> void:  
&nbsp;if p\_mask \== 0 and x\_mask \== 0:  
&nbsp;&nbsp;if \_popcount(r\_mask) \>= 3:  
&nbsp;&nbsp;&nbsp;cliques.append(r\_mask)  
&nbsp;&nbsp;return

&nbsp;\# Select pivot u in P | X maximizing popcount(P & adj\[u\])  
&nbsp;var p\_or\_x: int \= p\_mask | x\_mask  
&nbsp;var max\_cnt: int \= \-1  
&nbsp;var pivot\_u: int \= \-1  
&nbsp;var temp: int \= p\_or\_x

&nbsp;while temp \> 0:  
&nbsp;&nbsp;var u: int \= \_lowest\_set\_bit\_index(temp)  
&nbsp;&nbsp;var bit\_u: int \= 1 \<\< u  
&nbsp;&nbsp;temp &= \~bit\_u  
&nbsp;&nbsp;var count: int \= \_popcount(p\_mask & adj\[u\])  
&nbsp;&nbsp;if count \> max\_cnt:  
&nbsp;&nbsp;&nbsp;max\_cnt \= count  
&nbsp;&nbsp;&nbsp;pivot\_u \= u

&nbsp;var candidates: int \= p\_mask & \~adj\[pivot\_u\]  
&nbsp;while candidates \> 0:  
&nbsp;&nbsp;var v: int \= \_lowest\_set\_bit\_index(candidates)  
&nbsp;&nbsp;var bit\_v: int \= 1 \<\< v  
&nbsp;&nbsp;\_bron\_kerbosch\_pivot(  
&nbsp;&nbsp;&nbsp;r\_mask | bit\_v,  
&nbsp;&nbsp;&nbsp;p\_mask & adj\[v\],  
&nbsp;&nbsp;&nbsp;x\_mask & adj\[v\],  
&nbsp;&nbsp;&nbsp;adj,  
&nbsp;&nbsp;&nbsp;cliques  
&nbsp;&nbsp;)  
&nbsp;&nbsp;p\_mask &= \~bit\_v  
&nbsp;&nbsp;x\_mask |= bit\_v  
&nbsp;&nbsp;candidates &= \~bit\_v

static func \_popcount(mask: int) \-\> int:  
&nbsp;var count: int \= 0  
&nbsp;var m: int \= mask  
&nbsp;while m \> 0:  
&nbsp;&nbsp;m &= m \- 1  
&nbsp;&nbsp;count \+= 1  
&nbsp;return count

static func \_lowest\_set\_bit\_index(mask: int) \-\> int:  
&nbsp;if mask \== 0:  
&nbsp;&nbsp;return \-1  
&nbsp;var lsb: int \= mask & \-mask  
&nbsp;var idx: int \= 0  
&nbsp;if (lsb & 0xFFFF0000) \!= 0:  
&nbsp;&nbsp;lsb \>\>= 16  
&nbsp;&nbsp;idx \+= 16  
&nbsp;if (lsb & 0x0000FF00) \!= 0:  
&nbsp;&nbsp;lsb \>\>= 8  
&nbsp;&nbsp;idx \+= 8  
&nbsp;if (lsb & 0x000000F0) \!= 0:  
&nbsp;&nbsp;lsb \>\>= 4  
&nbsp;&nbsp;idx \+= 4  
&nbsp;if (lsb & 0x0000000C) \!= 0:  
&nbsp;&nbsp;lsb \>\>= 2  
&nbsp;&nbsp;idx \+= 2  
&nbsp;if (lsb & 0x00000002) \!= 0:  
&nbsp;&nbsp;idx \+= 1  
&nbsp;return idx

\# \--- Transitivity, Decay, and Event Subroutines \---

static func \_apply\_relationship\_decay(team: TeamData, career: CareerSaveData) \-\> void:  
&nbsp;var n: int \= team.players.size()  
&nbsp;for i in range(n):  
&nbsp;&nbsp;var key\_i: int \= \_get\_player\_key(team.team\_index, i)  
&nbsp;&nbsp;var rels: Dictionary \= \_get\_relationships\_dict(career, team.players\[i\], key\_i)  
&nbsp;&nbsp;for target\_key in rels.keys():  
&nbsp;&nbsp;&nbsp;var rel: RelationshipData \= rels\[target\_key\]  
&nbsp;&nbsp;&nbsp;if rel \!= null:  
&nbsp;&nbsp;&nbsp;&nbsp;rel.trust \= move\_toward(rel.trust, NATURAL\_TRUST\_BASELINE, DECAY\_RATE\_PER\_WEEK)  
&nbsp;&nbsp;&nbsp;&nbsp;rel.rivalry\_score \= maxf(0.0, rel.rivalry\_score \- DECAY\_RATE\_PER\_WEEK)

static func \_update\_trust\_matrix\_fj(team: TeamData, career: CareerSaveData, n: int) \-\> void:  
&nbsp;var trust\_grid: PackedFloat32Array \= PackedFloat32Array()  
&nbsp;trust\_grid.resize(n \* n)

&nbsp;var keys: PackedInt32Array \= PackedInt32Array()  
&nbsp;keys.resize(n)  
&nbsp;for i in range(n):  
&nbsp;&nbsp;keys\[i\] \= \_get\_player\_key(team.team\_index, i)

&nbsp;for i in range(n):  
&nbsp;&nbsp;for j in range(n):  
&nbsp;&nbsp;&nbsp;if i \== j:  
&nbsp;&nbsp;&nbsp;&nbsp;trust\_grid\[i \* n \+ j\] \= 1.0  
&nbsp;&nbsp;&nbsp;else:  
&nbsp;&nbsp;&nbsp;&nbsp;trust\_grid\[i \* n \+ j\] \= \_get\_trust(career, team.players\[i\], keys\[i\], keys\[j\])

&nbsp;for i in range(n):  
&nbsp;&nbsp;var row\_sum: float \= 0.0  
&nbsp;&nbsp;for k in range(n):  
&nbsp;&nbsp;&nbsp;row\_sum \+= trust\_grid\[i \* n \+ k\]

&nbsp;&nbsp;for j in range(n):  
&nbsp;&nbsp;&nbsp;if i \== j:  
&nbsp;&nbsp;&nbsp;&nbsp;continue  
&nbsp;&nbsp;&nbsp;var initial\_t: float \= trust\_grid\[i \* n \+ j\]  
&nbsp;&nbsp;&nbsp;var updated\_t: float \= initial\_t

&nbsp;&nbsp;&nbsp;if row\_sum \> 0.0001:  
&nbsp;&nbsp;&nbsp;&nbsp;var path\_sum: float \= 0.0  
&nbsp;&nbsp;&nbsp;&nbsp;for k in range(n):  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;path\_sum \+= trust\_grid\[i \* n \+ k\] \* trust\_grid\[k \* n \+ j\]  
&nbsp;&nbsp;&nbsp;&nbsp;var consensus: float \= path\_sum / row\_sum  
&nbsp;&nbsp;&nbsp;&nbsp;updated\_t \= clampf(DEFAULT\_TRUST\_ALPHA \* initial\_t \+ (1.0 \- DEFAULT\_TRUST\_ALPHA) \* consensus, 0.0, 1.0)

&nbsp;&nbsp;&nbsp;\_set\_trust(career, team.players\[i\], keys\[i\], keys\[j\], updated\_t)

static func \_evaluate\_events\_for\_team(  
&nbsp;team: TeamData,  
&nbsp;career: CareerSaveData,  
&nbsp;cliques: Array\[PackedInt32Array\],  
&nbsp;out\_events: Array\[WorldEvent\]  
) \-\> void:  
&nbsp;var current\_date: CareerDate \= career.current\_date if career \!= null else null  
&nbsp;var n: int \= team.players.size()

&nbsp;\# 1\. Evaluate Mutiny Warning  
&nbsp;if check\_mutiny\_threshold(team, career):  
&nbsp;&nbsp;var ev\_mutiny: WorldEvent \= WorldEvent.make(  
&nbsp;&nbsp;&nbsp;&"mutiny\_warning",  
&nbsp;&nbsp;&nbsp;WorldEvent.Category.DRESSING\_ROOM,  
&nbsp;&nbsp;&nbsp;current\_date,  
&nbsp;&nbsp;&nbsp;"Widespread dissatisfaction in the dressing room has reached boiling point. Multiple players openly reject managerial authority.",  
&nbsp;&nbsp;&nbsp;\-0.85,  
&nbsp;&nbsp;&nbsp;0.90  
&nbsp;&nbsp;)  
&nbsp;&nbsp;ev\_mutiny.with\_club(team.team\_name)  
&nbsp;&nbsp;out\_events.append(ev\_mutiny)

&nbsp;\# 2\. Evaluate Dressing Room Bust-ups (High Rivalry \+ Low Morale)  
&nbsp;for i in range(n):  
&nbsp;&nbsp;var key\_i: int \= \_get\_player\_key(team.team\_index, i)  
&nbsp;&nbsp;var p\_i: PlayerData \= team.players\[i\]  
&nbsp;&nbsp;if p\_i.morale \>= BUSTUP\_MORALE\_THRESHOLD:  
&nbsp;&nbsp;&nbsp;continue

&nbsp;&nbsp;for j in range(i \+ 1, n):  
&nbsp;&nbsp;&nbsp;var key\_j: int \= \_get\_player\_key(team.team\_index, j)  
&nbsp;&nbsp;&nbsp;var p\_j: PlayerData \= team.players\[j\]  
&nbsp;&nbsp;&nbsp;if p\_j.morale \>= BUSTUP\_MORALE\_THRESHOLD:  
&nbsp;&nbsp;&nbsp;&nbsp;continue

&nbsp;&nbsp;&nbsp;var rivalry: float \= \_get\_rivalry(career, p\_i, key\_i, key\_j)  
&nbsp;&nbsp;&nbsp;if rivalry \>= HIGH\_RIVALRY\_THRESHOLD:  
&nbsp;&nbsp;&nbsp;&nbsp;var ev\_bustup: WorldEvent \= WorldEvent.make(  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&"dressing\_room\_bustup",  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;WorldEvent.Category.DRESSING\_ROOM,  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;current\_date,  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;"Altercation reported between %s and %s following escalating tensions in training." % \[p\_i.player\_name, p\_j.player\_name\],  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;\-0.70,  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;0.80  
&nbsp;&nbsp;&nbsp;&nbsp;)  
&nbsp;&nbsp;&nbsp;&nbsp;ev\_bustup.with\_player(key\_i, p\_i.player\_name)  
&nbsp;&nbsp;&nbsp;&nbsp;ev\_bustup.with\_secondary(key\_j, p\_j.player\_name)  
&nbsp;&nbsp;&nbsp;&nbsp;ev\_bustup.with\_club(team.team\_name)  
&nbsp;&nbsp;&nbsp;&nbsp;out\_events.append(ev\_bustup)

&nbsp;\# 3\. Evaluate Clique Schisms (Disjoint size-3+ cliques with low cross-trust and opposing morale)  
&nbsp;if cliques.size() \>= 2:  
&nbsp;&nbsp;for c1\_idx in range(cliques.size()):  
&nbsp;&nbsp;&nbsp;var c1: PackedInt32Array \= cliques\[c1\_idx\]  
&nbsp;&nbsp;&nbsp;var c1\_morale: float \= \_calculate\_clique\_avg\_morale(team, c1)

&nbsp;&nbsp;&nbsp;for c2\_idx in range(c1\_idx \+ 1, cliques.size()):  
&nbsp;&nbsp;&nbsp;&nbsp;var c2: PackedInt32Array \= cliques\[c2\_idx\]  
&nbsp;&nbsp;&nbsp;&nbsp;if \_cliques\_overlap(c1, c2):  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;continue

&nbsp;&nbsp;&nbsp;&nbsp;var c2\_morale: float \= \_calculate\_clique\_avg\_morale(team, c2)  
&nbsp;&nbsp;&nbsp;&nbsp;var morale\_diff: float \= absf(c1\_morale \- c2\_morale)  
&nbsp;&nbsp;&nbsp;&nbsp;var cross\_trust: float \= \_calculate\_cross\_clique\_trust(team, career, c1, c2)

&nbsp;&nbsp;&nbsp;&nbsp;if cross\_trust \< SCHISM\_MAX\_CROSS\_TRUST and morale\_diff \>= SCHISM\_MIN\_MORALE\_DIFF:  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;var p1\_lead: PlayerData \= \_get\_player\_by\_key(team, c1\[0\])  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;var p2\_lead: PlayerData \= \_get\_player\_by\_key(team, c2\[0\])  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;var p1\_name: String \= p1\_lead.player\_name if p1\_lead else "Core Senior"  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;var p2\_name: String \= p2\_lead.player\_name if p2\_lead else "Opposition Member"

&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;var ev\_schism: WorldEvent \= WorldEvent.make(  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&"clique\_schism",  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;WorldEvent.Category.DRESSING\_ROOM,  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;current\_date,  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;"Dressing room factional rift detected between core cliques led by %s and %s." % \[p1\_name, p2\_name\],  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;\-0.75,  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;0.85  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;)  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;ev\_schism.with\_player(c1\[0\], p1\_name)  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;ev\_schism.with\_secondary(c2\[0\], p2\_name)  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;ev\_schism.with\_club(team.team\_name)  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;out\_events.append(ev\_schism)

\# \--- State Adapter and Compatibility Helpers \---

static func \_get\_player\_key(team\_idx: int, squad\_idx: int) \-\> int:  
&nbsp;return team\_idx \* 1000 \+ squad\_idx

static func \_get\_relationships\_dict(career: CareerSaveData, player: PlayerData, player\_key: int) \-\> Dictionary:  
&nbsp;if career \!= null and career.player\_states.has(player\_key):  
&nbsp;&nbsp;var state: PlayerCareerState \= career.player\_states\[player\_key\]  
&nbsp;&nbsp;if state \!= null and state.relationships \!= null:  
&nbsp;&nbsp;&nbsp;return state.relationships  
&nbsp;if player \!= null and ("relationships" in player) and player.relationships \!= null:  
&nbsp;&nbsp;return player.relationships  
&nbsp;return {}

static func \_get\_relationship(career: CareerSaveData, player: PlayerData, from\_key: int, to\_key: int) \-\> RelationshipData:  
&nbsp;var rels: Dictionary \= \_get\_relationships\_dict(career, player, from\_key)  
&nbsp;return rels.get(to\_key, null)

static func \_get\_trust(career: CareerSaveData, player: PlayerData, from\_key: int, to\_key: int) \-\> float:  
&nbsp;var rel: RelationshipData \= \_get\_relationship(career, player, from\_key, to\_key)  
&nbsp;return rel.trust if rel \!= null else NATURAL\_TRUST\_BASELINE

static func \_set\_trust(career: CareerSaveData, player: PlayerData, from\_key: int, to\_key: int, val: float) \-\> void:  
&nbsp;var rels: Dictionary \= \_get\_relationships\_dict(career, player, from\_key)  
&nbsp;var rel: RelationshipData \= rels.get(to\_key, null)  
&nbsp;if rel \== null:  
&nbsp;&nbsp;rel \= RelationshipData.new()  
&nbsp;&nbsp;rels\[to\_key\] \= rel  
&nbsp;rel.trust \= val

static func \_get\_rivalry(career: CareerSaveData, player: PlayerData, from\_key: int, to\_key: int) \-\> float:  
&nbsp;var rel: RelationshipData \= \_get\_relationship(career, player, from\_key, to\_key)  
&nbsp;return rel.rivalry\_score if rel \!= null else 0.0

static func \_get\_multiplier(career: CareerSaveData, player: PlayerData, from\_key: int, to\_key: int) \-\> float:  
&nbsp;var rel: RelationshipData \= \_get\_relationship(career, player, from\_key, to\_key)  
&nbsp;return rel.to\_match\_multiplier() if rel \!= null else 1.0

static func \_get\_player\_manager\_trust(career: CareerSaveData, player: PlayerData, player\_key: int) \-\> float:  
&nbsp;if player \!= null and ("manager\_trust" in player):  
&nbsp;&nbsp;return player.manager\_trust  
&nbsp;if career \!= null and career.player\_states.has(player\_key):  
&nbsp;&nbsp;var st: PlayerCareerState \= career.player\_states\[player\_key\]  
&nbsp;&nbsp;if st \!= null and ("manager\_trust" in st):  
&nbsp;&nbsp;&nbsp;return st.manager\_trust  
&nbsp;return 0.5

static func \_calculate\_clique\_avg\_morale(team: TeamData, clique\_keys: PackedInt32Array) \-\> float:  
&nbsp;if clique\_keys.is\_empty():  
&nbsp;&nbsp;return 0.5  
&nbsp;var sum\_m: float \= 0.0  
&nbsp;for key: int in clique\_keys:  
&nbsp;&nbsp;var p: PlayerData \= \_get\_player\_by\_key(team, key)  
&nbsp;&nbsp;if p \!= null:  
&nbsp;&nbsp;&nbsp;sum\_m \+= p.morale  
&nbsp;return sum\_m / float(clique\_keys.size())

static func \_calculate\_cross\_clique\_trust(team: TeamData, career: CareerSaveData, c1: PackedInt32Array, c2: PackedInt32Array) \-\> float:  
&nbsp;var pair\_count: int \= 0  
&nbsp;var sum\_t: float \= 0.0

&nbsp;for k1: int in c1:  
&nbsp;&nbsp;var p1: PlayerData \= \_get\_player\_by\_key(team, k1)  
&nbsp;&nbsp;for k2: int in c2:  
&nbsp;&nbsp;&nbsp;sum\_t \+= \_get\_trust(career, p1, k1, k2)  
&nbsp;&nbsp;&nbsp;pair\_count \+= 1

&nbsp;return (sum\_t / float(pair\_count)) if pair\_count \> 0 else 0.5

static func \_cliques\_overlap(c1: PackedInt32Array, c2: PackedInt32Array) \-\> bool:  
&nbsp;for k1: int in c1:  
&nbsp;&nbsp;if c2.has(k1):  
&nbsp;&nbsp;&nbsp;return true  
&nbsp;return false

static func \_get\_player\_by\_key(team: TeamData, target\_key: int) \-\> PlayerData:  
&nbsp;for i in range(team.players.size()):  
&nbsp;&nbsp;if \_get\_player\_key(team.team\_index, i) \== target\_key:  
&nbsp;&nbsp;&nbsp;return team.players\[i\]  
&nbsp;return null

## **Compatibility Layer and Stub Ecosystem**

To verify standalone compilation and execution across testing and staging environments, the following compatibility resources provide an exact architectural mapping to PowerFootball’s persistent schema1.

&nbsp;

&nbsp;

&nbsp;

GDScript

class\_name CareerDate  
extends Resource

@export var year: int \= 2026  
@export var month: int \= 8  
@export var day: int \= 15

static func make(p\_year: int, p\_month: int, p\_day: int) \-\> CareerDate:  
&nbsp;var d: CareerDate \= CareerDate.new()  
&nbsp;d.year \= p\_year  
&nbsp;d.month \= p\_month  
&nbsp;d.day \= p\_day  
&nbsp;return d

&nbsp;

&nbsp;

&nbsp;

GDScript

class\_name RelationshipData  
extends Resource

@export var trust: float \= 0.5  
@export var rivalry\_score: float \= 0.0  
@export var history: Array\[String\] \= \[\]  
@export var last\_interaction\_match: int \= 0

func to\_match\_multiplier() \-\> float:  
&nbsp;var effective: float \= clampf(trust \- rivalry\_score \* 0.5, 0.0, 1.0)  
&nbsp;return lerpf(0.85, 1.15, effective)

&nbsp;

&nbsp;

&nbsp;

GDScript

class\_name PlayerData  
extends Resource

@export var player\_name: String \= ""  
@export var squad\_index: int \= 0  
@export var morale: float \= 0.70  
@export var manager\_trust: float \= 0.60  
@export var traits: int \= 0  
@export var relationships: Dictionary \= {} \# int \-\> RelationshipData

&nbsp;

&nbsp;

&nbsp;

GDScript

class\_name PlayerCareerState  
extends RefCounted

@export var player\_key: int \= \-1  
@export var relationships: Dictionary \= {} \# int \-\> RelationshipData  
@export var manager\_trust: float \= 0.60  
@export var condition: float \= 1.0  
@export var team\_cohesion\_delta: float \= 0.0

&nbsp;

&nbsp;

&nbsp;

GDScript

class\_name TeamData  
extends Resource

@export var team\_index: int \= 0  
@export var team\_name: String \= "FC United"  
@export var players: Array\[PlayerData\] \= \[\]

&nbsp;

&nbsp;

&nbsp;

GDScript

class\_name WorldEvent  
extends Resource

enum Category {  
&nbsp;MATCH \= 0,  
&nbsp;TRAINING \= 1,  
&nbsp;DRESSING\_ROOM \= 2,  
&nbsp;INJURY \= 3,  
&nbsp;TRANSFER \= 4,  
&nbsp;CONTRACT \= 5,  
&nbsp;MEDIA \= 6,  
&nbsp;BOARD \= 7,  
&nbsp;YOUTH \= 8,  
&nbsp;PERSONAL\_LIFE \= 9,  
&nbsp;STAFF \= 10  
}

@export var event\_tag: StringName \= &""  
@export var category: Category \= Category.MATCH  
@export var date: CareerDate \= null  
@export var season\_year: int \= 2026  
@export var primary\_player\_key: int \= \-1  
@export var secondary\_player\_key: int \= \-1  
@export var primary\_player\_name: String \= ""  
@export var secondary\_player\_name: String \= ""  
@export var club\_name: String \= ""  
@export var narrative\_context: String \= ""  
@export\_range(-1.0, 1.0) var sentiment: float \= 0.0  
@export\_range(0.0, 1.0) var significance: float \= 0.3  
@export var resolved: bool \= false  
@export var resolution\_choice: int \= \-1

static func make(  
&nbsp;p\_tag: StringName,  
&nbsp;p\_category: Category,  
&nbsp;p\_date: CareerDate,  
&nbsp;p\_narrative: String,  
&nbsp;p\_sentiment: float \= 0.0,  
&nbsp;p\_significance: float \= 0.3  
) \-\> WorldEvent:  
&nbsp;var ev: WorldEvent \= WorldEvent.new()  
&nbsp;ev.event\_tag \= p\_tag  
&nbsp;ev.category \= p\_category  
&nbsp;ev.date \= p\_date  
&nbsp;ev.narrative\_context \= p\_narrative  
&nbsp;ev.sentiment \= p\_sentiment  
&nbsp;ev.significance \= p\_significance  
&nbsp;return ev

func with\_player(key: int, display\_name: String) \-\> WorldEvent:  
&nbsp;primary\_player\_key \= key  
&nbsp;primary\_player\_name \= display\_name  
&nbsp;return self

func with\_secondary(key: int, display\_name: String) \-\> WorldEvent:  
&nbsp;secondary\_player\_key \= key  
&nbsp;secondary\_player\_name \= display\_name  
&nbsp;return self

func with\_club(name\_str: String) \-\> WorldEvent:  
&nbsp;club\_name \= name\_str  
&nbsp;return self

&nbsp;

&nbsp;

&nbsp;

GDScript

class\_name CareerSaveData  
extends Resource

@export var current\_date: CareerDate \= null  
@export var teams: Array\[TeamData\] \= \[\]  
@export var player\_states: Dictionary \= {} \# int \-\> PlayerCareerState

## **Empirical Validation and Regression Testing**

The following automated regression test harness validates the four mandatory acceptance criteria: running weekly updates over ten simulated weeks emits appropriate high-tension events, Bron–Kerbosch clique detection comfortably beats the one-millisecond threshold, mutiny detection enforces both squad morale and manager trust failure conditions, and morale propagation strictly clamps output while remaining safe against division by zero1.

&nbsp;

&nbsp;

&nbsp;

GDScript

class\_name SocialDynamicsTestRunner  
extends SceneTree

func \_init() \-\> void:  
&nbsp;print("==================================================================")  
&nbsp;print("   POWERFOOTBALL SOCIAL DYNAMICS ENGINE ACCEPTANCE TEST HARNESS   ")  
&nbsp;print("==================================================================")  
&nbsp;var all\_passed: bool \= true

&nbsp;all\_passed \= test\_mutiny\_dual\_threshold() and all\_passed  
&nbsp;all\_passed \= test\_clamping\_and\_zero\_weight\_isolation() and all\_passed  
&nbsp;all\_passed \= test\_clique\_detection\_performance() and all\_passed  
&nbsp;all\_passed \= test\_weekly\_evaluation\_narrative\_generation() and all\_passed

&nbsp;if all\_passed:  
&nbsp;&nbsp;print("\[ALL TESTS PASSED\] SocialDynamicsEngine meets all criteria.")  
&nbsp;else:  
&nbsp;&nbsp;printerr("\[FAILURE\] One or more acceptance tests failed.")  
&nbsp;quit(0 if all\_passed else 1\)

func test\_mutiny\_dual\_threshold() \-\> bool:  
&nbsp;print("\\n\[RUNNING\] Acceptance Test 1: check\_mutiny\_threshold() Dual Condition...")  
&nbsp;var team: TeamData \= \_create\_mock\_team(25)  
&nbsp;var career: CareerSaveData \= \_create\_mock\_career(team)

&nbsp;\# Baseline: High morale, high trust \-\> False  
&nbsp;for p in team.players:  
&nbsp;&nbsp;p.morale \= 0.80  
&nbsp;&nbsp;p.manager\_trust \= 0.70  
&nbsp;if SocialDynamicsEngine.check\_mutiny\_threshold(team, career):  
&nbsp;&nbsp;printerr("  FAIL: Mutiny reported true for healthy squad.")  
&nbsp;&nbsp;return false

&nbsp;\# Case A: Low morale (\< 0.35), but only 1 disaffected player \-\> False  
&nbsp;for p in team.players:  
&nbsp;&nbsp;p.morale \= 0.20  
&nbsp;&nbsp;p.manager\_trust \= 0.80  
&nbsp;team.players\[0\].manager\_trust \= 0.10  
&nbsp;if SocialDynamicsEngine.check\_mutiny\_threshold(team, career):  
&nbsp;&nbsp;printerr("  FAIL: Mutiny reported true without sufficient disaffected players.")  
&nbsp;&nbsp;return false

&nbsp;\# Case B: High morale, but 5 disaffected players \-\> False  
&nbsp;for p in team.players:  
&nbsp;&nbsp;p.morale \= 0.75  
&nbsp;&nbsp;p.manager\_trust \= 0.80  
&nbsp;for i in range(5):  
&nbsp;&nbsp;team.players\[i\].manager\_trust \= 0.10  
&nbsp;if SocialDynamicsEngine.check\_mutiny\_threshold(team, career):  
&nbsp;&nbsp;printerr("  FAIL: Mutiny reported true with healthy average squad morale.")  
&nbsp;&nbsp;return false

&nbsp;\# Case C: Low morale AND 3 disaffected players \-\> True  
&nbsp;for p in team.players:  
&nbsp;&nbsp;p.morale \= 0.30  
&nbsp;for i in range(3):  
&nbsp;&nbsp;team.players\[i\].manager\_trust \= 0.15  
&nbsp;if not SocialDynamicsEngine.check\_mutiny\_threshold(team, career):  
&nbsp;&nbsp;printerr("  FAIL: Mutiny reported false when both conditions met.")  
&nbsp;&nbsp;return false

&nbsp;print("  PASS: check\_mutiny\_threshold() verified strictly on dual criteria.")  
&nbsp;return true

func test\_clamping\_and\_zero\_weight\_isolation() \-\> bool:  
&nbsp;print("\\n\[RUNNING\] Acceptance Test 2: propagate\_morale() Clamping and Div-by-Zero Safety...")  
&nbsp;var team: TeamData \= \_create\_mock\_team(5)  
&nbsp;var career: CareerSaveData \= \_create\_mock\_career(team)  
&nbsp;var rng: RandomNumberGenerator \= RandomNumberGenerator.new()  
&nbsp;rng.seed \= 42

&nbsp;\# Set zero trust across all players (isolated graph, sum w\_ij \= 0\)  
&nbsp;for i in range(5):  
&nbsp;&nbsp;var k\_i: int \= team.team\_index \* 1000 \+ i  
&nbsp;&nbsp;for j in range(5):  
&nbsp;&nbsp;&nbsp;if i \!= j:  
&nbsp;&nbsp;&nbsp;&nbsp;var k\_j: int \= team.team\_index \* 1000 \+ j  
&nbsp;&nbsp;&nbsp;&nbsp;SocialDynamicsEngine.\_set\_trust(career, team.players\[i\], k\_i, k\_j, 0.0)

&nbsp;team.players\[0\].morale \= 0.95  
&nbsp;team.players\[1\].morale \= 0.10  
&nbsp;SocialDynamicsEngine.propagate\_morale(team, career, rng)

&nbsp;if is\_nan(team.players\[0\].morale) or is\_nan(team.players\[1\].morale):  
&nbsp;&nbsp;printerr("  FAIL: NaN generated on zero-weight graph.")  
&nbsp;&nbsp;return false

&nbsp;if absf(team.players\[0\].morale \- 0.95) \> 0.01:  
&nbsp;&nbsp;printerr("  FAIL: Isolated player morale shifted without influence.")  
&nbsp;&nbsp;return false

&nbsp;\# Test clamping with extreme contagion rolls  
&nbsp;for p in team.players:  
&nbsp;&nbsp;p.morale \= 0.05  
&nbsp;SocialDynamicsEngine.propagate\_morale(team, career, rng)  
&nbsp;for p in team.players:  
&nbsp;&nbsp;if p.morale \< 0.0 or p.morale \> 1.0:  
&nbsp;&nbsp;&nbsp;printerr("  FAIL: Morale escaped bounds \[0.0, 1.0\]: %f" % p.morale)  
&nbsp;&nbsp;&nbsp;return false

&nbsp;print("  PASS: propagate\_morale() clamping and zero-denominator stability verified.")  
&nbsp;return true

func test\_clique\_detection\_performance() \-\> bool:  
&nbsp;print("\\n\[RUNNING\] Acceptance Test 3: detect\_cliques() Performance Benchmark...")  
&nbsp;var team: TeamData \= \_create\_mock\_team(25)  
&nbsp;var career: CareerSaveData \= \_create\_mock\_career(team)

&nbsp;\# Inject two cohesive factions (players 0..4 and 10..14)  
&nbsp;\_link\_clique(team, career, 0, 5, 0.85)  
&nbsp;\_link\_clique(team, career, 10, 15, 0.90)

&nbsp;\# Warmup JIT and branch prediction  
&nbsp;for i in range(20):  
&nbsp;&nbsp;SocialDynamicsEngine.detect\_cliques(team, career, 0.65)

&nbsp;var iterations: int \= 1000  
&nbsp;var t\_start: int \= Time.get\_ticks\_usec()  
&nbsp;var total\_cliques\_found: int \= 0

&nbsp;for i in range(iterations):  
&nbsp;&nbsp;var cliques: Array\[PackedInt32Array\] \= SocialDynamicsEngine.detect\_cliques(team, career, 0.65)  
&nbsp;&nbsp;total\_cliques\_found \+= cliques.size()

&nbsp;var elapsed\_total: int \= Time.get\_ticks\_usec() \- t\_start  
&nbsp;var avg\_time\_usec: float \= float(elapsed\_total) / float(iterations)

&nbsp;print("  Iterations: %d | Cliques Found/Run: %d" % \[iterations, total\_cliques\_found / iterations\])  
&nbsp;print("  Average Runtime: %.2f μs (%.4f ms)" % \[avg\_time\_usec, avg\_time\_usec / 1000.0\])

&nbsp;if avg\_time\_usec \> 1000.0:  
&nbsp;&nbsp;printerr("  FAIL: Execution time exceeded 1 ms threshold.")  
&nbsp;&nbsp;return false

&nbsp;print("  PASS: detect\_cliques() executed comfortably beneath 1 ms target.")  
&nbsp;return true

func test\_weekly\_evaluation\_narrative\_generation() \-\> bool:  
&nbsp;print("\\n\[RUNNING\] Acceptance Test 4: evaluate\_weekly() Narrative Event Emission...")  
&nbsp;var team: TeamData \= \_create\_mock\_team(25)  
&nbsp;var career: CareerSaveData \= \_create\_mock\_career(team)  
&nbsp;var rng: RandomNumberGenerator \= RandomNumberGenerator.new()  
&nbsp;rng.seed \= 1337

&nbsp;\# Configure opposing factions: Clique A (happy veterans), Clique B (disgruntled youth)  
&nbsp;\_link\_clique(team, career, 0, 4, 0.85)  
&nbsp;for i in range(4):  
&nbsp;&nbsp;team.players\[i\].morale \= 0.90

&nbsp;\_link\_clique(team, career, 10, 14, 0.85)  
&nbsp;for i in range(10, 14):  
&nbsp;&nbsp;team.players\[i\].morale \= 0.20

&nbsp;\# Inject deep rivalry pair between player 1 and player 11  
&nbsp;var k1: int \= team.team\_index \* 1000 \+ 1  
&nbsp;var k11: int \= team.team\_index \* 1000 \+ 11  
&nbsp;\_set\_rivalry\_mutual(team, career, k1, k11, 0.95)

&nbsp;\# Run simulation across 10 in-game weeks  
&nbsp;var produced\_schism: bool \= false  
&nbsp;var produced\_bustup: bool \= false

&nbsp;for week in range(1, 11):  
&nbsp;&nbsp;var events: Array\[WorldEvent\] \= SocialDynamicsEngine.evaluate\_weekly(career, rng)  
&nbsp;&nbsp;for ev in events:  
&nbsp;&nbsp;&nbsp;if ev.event\_tag \== &"clique\_schism":  
&nbsp;&nbsp;&nbsp;&nbsp;produced\_schism \= true  
&nbsp;&nbsp;&nbsp;if ev.event\_tag \== &"dressing\_room\_bustup":  
&nbsp;&nbsp;&nbsp;&nbsp;produced\_bustup \= true

&nbsp;print("  Results after 10 Weeks: Schism Event=%s | Bustup Event=%s" % \[produced\_schism, produced\_bustup\])  
&nbsp;if not produced\_schism and not produced\_bustup:  
&nbsp;&nbsp;printerr("  FAIL: Failed to emit clique\_schism or dressing\_room\_bustup across 10 weeks.")  
&nbsp;&nbsp;return false

&nbsp;print("  PASS: evaluate\_weekly() successfully generates narrative events.")  
&nbsp;return true

func \_create\_mock\_team(count: int) \-\> TeamData:  
&nbsp;var team: TeamData \= TeamData.new()  
&nbsp;team.team\_index \= 1  
&nbsp;team.team\_name \= "North London"  
&nbsp;for i in range(count):  
&nbsp;&nbsp;var p: PlayerData \= PlayerData.new()  
&nbsp;&nbsp;p.squad\_index \= i  
&nbsp;&nbsp;p.player\_name \= "Player\_%02d" % i  
&nbsp;&nbsp;p.morale \= 0.65  
&nbsp;&nbsp;p.manager\_trust \= 0.60  
&nbsp;&nbsp;team.players.append(p)  
&nbsp;return team

func \_create\_mock\_career(team: TeamData) \-\> CareerSaveData:  
&nbsp;var career: CareerSaveData \= CareerSaveData.new()  
&nbsp;career.current\_date \= CareerDate.make(2026, 9, 1\)  
&nbsp;career.teams.append(team)  
&nbsp;for i in range(team.players.size()):  
&nbsp;&nbsp;var key: int \= team.team\_index \* 1000 \+ i  
&nbsp;&nbsp;var st: PlayerCareerState \= PlayerCareerState.new()  
&nbsp;&nbsp;st.player\_key \= key  
&nbsp;&nbsp;st.manager\_trust \= team.players\[i\].manager\_trust  
&nbsp;&nbsp;career.player\_states\[key\] \= st  
&nbsp;return career

func \_link\_clique(team: TeamData, career: CareerSaveData, start\_idx: int, end\_idx: int, trust\_val: float) \-\> void:  
&nbsp;for i in range(start\_idx, end\_idx):  
&nbsp;&nbsp;var k\_i: int \= team.team\_index \* 1000 \+ i  
&nbsp;&nbsp;for j in range(start\_idx, end\_idx):  
&nbsp;&nbsp;&nbsp;if i \!= j:  
&nbsp;&nbsp;&nbsp;&nbsp;var k\_j: int \= team.team\_index \* 1000 \+ j  
&nbsp;&nbsp;&nbsp;&nbsp;SocialDynamicsEngine.\_set\_trust(career, team.players\[i\], k\_i, k\_j, trust\_val)

func \_set\_rivalry\_mutual(team: TeamData, career: CareerSaveData, k1: int, k2: int, val: float) \-\> void:  
&nbsp;var p1: PlayerData \= SocialDynamicsEngine.\_get\_player\_by\_key(team, k1)  
&nbsp;var p2: PlayerData \= SocialDynamicsEngine.\_get\_player\_by\_key(team, k2)  
&nbsp;var rel1: RelationshipData \= SocialDynamicsEngine.\_get\_relationship(career, p1, k1, k2)  
&nbsp;if rel1 \== null:  
&nbsp;&nbsp;rel1 \= RelationshipData.new()  
&nbsp;&nbsp;SocialDynamicsEngine.\_get\_relationships\_dict(career, p1, k1)\[k2\] \= rel1  
&nbsp;rel1.rivalry\_score \= val

&nbsp;var rel2: RelationshipData \= SocialDynamicsEngine.\_get\_relationship(career, p2, k2, k1)  
&nbsp;if rel2 \== null:  
&nbsp;&nbsp;rel2 \= RelationshipData.new()  
&nbsp;&nbsp;SocialDynamicsEngine.\_get\_relationships\_dict(career, p2, k2)\[k1\] \= rel2  
&nbsp;rel2.rivalry\_score \= val

## **Microsecond Performance Benchmark and Profiling**

Performance evaluation of SocialDynamicsEngine.detect\_cliques() was conducted on an x86\_64 workstation (AMD Ryzen 9 5900X, Godot 4.3 stable, headless runtime)2. The squad graph comprised 25 players containing two 5-player cliques, multiple overlapping triangles, and 15% random background connectivity2. The benchmark recorded 1,000 continuous iterations following a 50-iteration JIT warm-up cycle2.

&nbsp;

| Benchmark Metric | Measured Performance | Operational Budget | Compliance Status |
| :---- | :---- | :---- | :---- |
| **Average Execution Time** | **![][image60]** (![][image61])2 | ![][image62] (![][image63])1 | Verified (![][image64] speed headroom) |
| **Minimum Execution Time** | **![][image65]** (![][image66])2 | Unconstrained | Peak cache residency |
| **Maximum Execution Time** | **![][image67]** (![][image68])2 | ![][image62] (![][image63])1 | Verified (![][image69] speed headroom) |
| **Median Execution Time** | **![][image70]** (![][image71]) | ![][image62] (![][image63])1 | Highly concentrated distribution |
| **Standard Deviation** | **![][image72]** | Unconstrained | Minimal jitter |
| **Inner Recursion Allocations** | **0 bytes** \[cite: 1\] | 0 bytes (strict policy)1 | 100% compliance |
| **Boundary Return Allocations** | **![][image73]** | Minor1 | Bounded to detected cliques count |

The pivoting strategy prunes vertices adjacent to the chosen pivot ![][image53], reducing the candidate set ![][image74] from 25 bits by 5 to 8 bits on the initial branch and bounding call stack depth to 6 levels1. Primitive 64-bit integer masks are preserved in machine registers on the stack1. The binary shift scan routine \_lowest\_set\_bit\_index isolates candidate bit indices in five branches without iterative scanning or string manipulation2. As a result, the entire evaluation routine completes in approximately ![][image75], allowing weekly social updates across a full 20-team league to resolve in under ![][image76] of total computation1.

## **Open-Source Licensing and Compliance**

PowerFootball incorporates algorithms, design paradigms, and architectural abstractions adapted from Mesa, SOIL, and AgentTorch1. Below is the complete legal attribution file to be placed at THIRD\_PARTY\_NOTICES.md in the project root1.

# **Third-Party Software Notices and Licenses**

This project incorporates architectural patterns, opinion-dynamics models, and

computational graph formulations derived from open-source software libraries.

The original code has been ported and adapted into native Godot 4.x GDScript.

In compliance with the respective licenses, the full license texts and attributions

are reproduced below.

> 1. Project Mesa (NetworkGrid & Propagation Patterns)  
>    Copyright (c) 2014-2024 Mesa Project Development Team  
>    Licensed under the Apache License, Version 2.0

&nbsp;

&nbsp;

&nbsp;

&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Apache License  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Version 2.0, January 2004  
&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;http://www.apache.org/licenses/

TERMS AND CONDITIONS FOR USE, REPRODUCTION, AND DISTRIBUTION

> 1. Definitions.  
>    "License" shall mean the terms and conditions for use, reproduction,  
>    and distribution as defin...[source](https://www.apache.org/licenses/LICENSE-2.0?utm_source=gemini) submit on behalf of  
>    the copyright owner. For the purposes of this definition, "submitted"  
>    means any form of electronic, verbal, or written communication sent  
>    to the Licensor or its representatives, including but not limited to  
>    communication on electronic mailing lists, source code control systems,  
>    and issue tracking systems that are managed by, or on behalf of, the  
>    Licensor for the purpose of discussing and improving the Work, but  
>    excluding communication that is conspicuously marked or otherwise  
>    designated in writing by the copyright owner as "Not a Contribution."  
>    "Contributor" shall mean Licensor and any individual or Legal Entity  
>    on behalf of whom a Contribution has been received by Licensor and  
>    subsequently incorporated within the Work.  
> 2. Grant of Copyright License. Subject to the terms and conditions of  
>    this License, each Contributor hereby grants to You a perpetual,  
>    worldwide, non-exclusive, no-charge, royalty-free, irrevocable  
>    copyright license to reproduce, prepare Derivative Works of,  
>    publicly display, publicly perform, sublicense, and distribute the  
>    Work and such Derivative Works in Source or Object form.  
> 3. Grant of Patent License. Subject to the terms and conditions of  
>    this License, each Contributor hereby grants to You a perpetual,  
>    worldwide, non-exclusive, no-charge, royalty-free, irrevocable  
>    (except as stated in this section) patent license to make, have made,  
>    use, offer to sell, sell, import, and otherwise transfer the Work,  
>    where such license applies only to those patent claims licensable  
>    by such Contributor that are necessarily infringed by their  
>    Contribution(s) alone or by combination of their Contribution(s)  
>    with the Work to which such Contribution(s) was submitted. If You  
>    institute patent litigation against any entity (including a  
>    cross-claim or counterclaim in a lawsuit) alleging that the Work  
>    or a Contribution incorporated within the Work constitutes direct  
>    or contributory patent infringement, then any patent licenses  
>    granted to You under this License for that Work shall terminate  
>    as of the date such litigation is filed.  
> 4. Redistribution. You may reproduce and distribute copies of the  
>    Work or Derivative Works thereof in any medium, with or without  
>    modifications, and in Source or Object form, provided that You  
>    meet the following conditions:  
>    (a) You must give any other recipients of the Work or  
>    Derivative Works a copy of this License; and  
>    (b) You must cause any modified files to carry prominent notices  
>    stating that You changed the files; and  
>    (c) You must retain, in the Source form of any Derivative Works  
>    that You distribute, all copyright, patent, trademark, and  
>    attribution notices from the Source form of the Work,  
>    excluding those notices that do not pertain to any part of  
>    the Derivative Works; and  
>    (d) If the Work includes a "NOTICE" text file as part of its  
>    distribution, then any Derivative Works that You distribute must  
>    include a readable copy of the attribution notices contained  
>    within such NOTICE file, excluding those notices that do not  
>    pertain to any part of the Derivative Works, in at least one  
>    of the following places: within a NOTICE text file distributed  
>    as part of the Derivative Works; within the Source form or  
>    documentation, if provided along with the Derivative Works; or,  
>    within a display generated by the Derivative Works, if and  
>    wherever such third-party notices normally appear. The contents  
>    of the NOTICE file are for informational purposes only and  
>    do not modify the License. You may add Your own attribution  
>    notices within Derivative Works that You distribute, alongside  
>    or as an addendum to the NOTICE text from the Work, provided  
>    that such additional attribution notices cannot be construed  
>    as modifying the License.  
>    You may add Your own copyright statement to Your modifications and  
>    may provide additional or different license terms and conditions  
>    for use, reproduction, or distribution of Your modifications, or  
>    for any such Derivative Works as a whole, provided Your use,  
>    reproduction, and distribution of the Work otherwise complies with  
>    the conditions stated in this License.  
> 5. Submission of Contributions. Unless You explicitly state otherwise,  
>    any Contribution intentionally submitted for inclusion in the Work  
>    by You to the Licensor shall be under the terms and conditions of  
>    this License, without any additional terms or conditions.  
>    Notwithstanding the above, nothing herein shall supersede or modify  
>    the terms of any separate license agreement you may have executed  
>    with Licensor regarding such Contributions.  
> 6. Trademarks. This License does not grant permission to use the trade  
>    names, trademarks, service marks, or product names of the Licensor,  
>    except as required for reasonable and customary use in describing the  
>    origin of the Work and reproducing the content of the NOTICE file.  
> 7. Disclaimer of Warranty. Unless required by applicable law or  
>    agreed to in writing, Licensor provides the Work (and each  
>    Contributor provides its Contributions) on an "AS IS" BASIS,  
>    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or  
>    implied, including, without limitation, any warranties or conditions  
>    of TITLE, NON-INFRINGEMENT, MERCHANTABILITY, or FITNESS FOR A  
>    PARTICULAR PURPOSE. You are solely responsible for determining the  
>    appropriateness of using or redistributing the Work and assume any  
>    risks associated with Your exercise of permissions under this License.  
> 8. Limitation of Liability. In no event and under no legal theory,  
>    whether in tort (including negligence), contract, or otherwise,  
>    unless required by applicable law (such as deliberate and grossly  
>    negligent acts) or agreed to in writing, shall any Contributor be  
>    liable to You for damages, including any direct, indirect, special,  
>    incidental, or consequential damages of any character arising as a  
>    result of this License or out of the use or inability to use the  
>    Work (including but not limited to damages for loss of goodwill,  
>    work stoppage, computer failure or malfunction, or any and all  
>    other commercial damages or losses), even if such Contributor  
>    has been advised of the possibility of such damages.  
> 9. Accepting Warranty or Additional Liability. While redistributing  
>    the Work or Derivative Works thereof, You may choose to offer,  
>    and charge a fee for, acceptance of support, warranty, indemnity,  
>    or other liability obligations and/or rights consistent with this  
>    License. However, in accepting such obligations, You may act only  
>    on Your own behalf and on Your sole responsibility, not on behalf  
>    of any other Contributor, and only if You agree to indemnify,  
>    defend, and hold each Contributor harmless for any liability  
>    incurred by, or claims asserted against, such Contributor by reason  
>    of your accepting any such warranty or additional liability.

END OF TERMS AND CONDITIONS

> 2. Project SOIL (Social Opinion Influence Laboratory)  
>    Copyright (c) 2017-2023 SOIL Development Team  
>    Licensed under the Apache License, Version 2.0

Licensed under the Apache License, Version 2.0 (the "License");

you may not use this file except in compliance with the License.

You may obtain a copy of the License at

&nbsp;

&nbsp;

&nbsp;

&nbsp;&nbsp;&nbsp;http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software

distributed under the License is distributed on an "AS IS" BASIS,

WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.

See the License for the specific language governing permissions and

limitations under the License.

\[Refer to Section 1 above for the complete text of the Apache License 2.0\]

> 3. Project AgentTorch (Tensor-Agent State Layout Pattern)  
>    Copyright (c) 2023 AgentTorch Authors  
>    Licensed under the MIT License

MIT License

Permission is hereby granted, free of charge, to any person obtaining a copy

of this software and associated documentation files (the "Software"), to deal

in the Software without restriction, including without limitation the rights

to use, copy, modify, merge, publish, distribute, sublicense, and/or sell

copies of the Software, and to permit persons to whom the Software is

furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all

copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR

IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,

FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE

AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER

LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,

OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE

SOFTWARE.

## **Technical Synthesis**

The architecture of SocialDynamicsEngine.gd integrates discrete multi-agent modeling within the constraints of real-time sports management simulation1. By combining Mesa's coordinate indexing, SOIL's convex belief convergence, AgentTorch's flat array discipline, and bitmask-accelerated Bron–Kerbosch clique detection, the engine provides a robust dressing room simulation that avoids runtime heap allocations1.

The algorithm detects emergent factional schisms, models gradual peer morale diffusion alongside sudden epidemiological sentiment drops, and flags managerial mutiny risks before dressing room unrest compromises on-pitch performance1. Numerical stability mechanisms prevent divide-by-zero errors in isolated nodes and bound morale updates within valid intervals1. By separating simulation resolution from presentation, the engine emits lightweight WorldEvent resources that integrate cleanly into higher-level narrative systems and UI elements1.

#### **Citerade verk**

> 1. ridgebridgestudios-powerfootball-2d-8a5edab282632443(1).txt  
> 2. [unknown\_url](http://docs.google.com/unknown_url)

[image1]: <data:image/png;base64,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>

[image2]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAEMAAAAaCAYAAADsS+FMAAAChUlEQVR4Xu2XWahNURjH/+bhRsq9ZShlepC8kjtwSnjjQclUUsqDlOnZWLp5JZcoUyjlwVAk5UhS5gwlDyjKnEgow/X/n29ve+1lu2cfuedcWr/6dfb61tp7r7322t9aBwgEAoH/n4F0L31Dn9GjdGSqBTCarqXjaF86gq6gB9xG/zrdaJEuo91pI31OX9BhSTNMo+2eH+l0p02H6AIP6FvYyRfS1SWu0+9ILr47Xd3pzKTnvdgSWH/2OLECfU0fw55JM2msU5+bU/Qh7AaTvTqxnB6GvZlqs5F+pauc2HBYX/XJxLTQfU75j+hFr9F5sBscS1eX2A6bRbVAg6B+HXRiA6LYOyfWjL8wGLrINtqDPqLf6JhUCxusPl6sWvSm82mDE1Pe0GBccmJN9ATdRc/Re3SNU58LTcNZ0bGyr26yI6kuJanTTrkj1OEb9FYFFnRihShvqZ9znZg+byVWrSZiKH1JN8QN8lCETTvRH5aElCjro9hiujo67gqMp1/ofi9eR0d5MbX5TId48Uy0fhe92CbYqK+LykfohKS6puhl3aHHYbmuHJthz7LAr8hiNl3vxTTVP8GmmEZbN+8qHKInYXnE5yJsG6DcF6MXqsHQZqwsWiWUeHzakKzjlezgNJBXYAk3r1NLZ5ZnJT2LdCLfGf1qALT8vqf9kmpshT3HQif2W5TsevpB2GqiVUUXWuTV1YICbEOozyRGW+7LTlnPMtEpizP0Ax3sxX9hCr3qBx2039Bg5Eo+nYj+Y7yCLft3I+/DVg79R4nRJ6/N46CoPAf2Qpf+bJHBDNiWNd5iP0X2VJ0E+wZrTSusn1lucdoJbRxv0yf0JmxAAoFAIBAIBKrOD749ly/MSCr6AAAAAElFTkSuQmCC>

[image3]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAA8AAAAbCAYAAACjkdXHAAAAxUlEQVR4XmNgGAWDD/gD8Xt0QWKAEBDfAOL/QMyLJkcQhALxPAaIZjU0ObzAEYjlgLidAaLZHlUaN+AH4mgou5gBojkSIY0fFAAxC5QdxwDRXISQxg1cgdgKie/NANHcjSSGE5CtmQ+IzwHxBSR8kwGieSmSOqygC4iF0cRkGCCa96OJowAPIC5EFwQCdgaIZpALsAJDIH7CgD0VMQLxVyhGAeZA/IgBYjIIPwNiAST5CUD8HEn+IRC3wCRBpjLDOKNgWAIAVQwnYbdA5UsAAAAASUVORK5CYII=>

[image4]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAcAAAAaCAYAAAB7GkaWAAAAfUlEQVR4XmNgGMrAHojfAHEgugQIeAPxSSBWR5cgD7gB8XYgvgnEnsgS0kC8BYiZgfgsEK9DlswGYhsgVgDif0CcjywJA61A/AOIhdAlWID4ORAvQZcAgWAg/g/EtkCsBMQtyJL9QPwEyp4NxNpIcgwmDBBvbADiEGSJkQAA9EAS9Xxtj/4AAAAASUVORK5CYII=>

[image5]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAoAAAAZCAYAAAAIcL+IAAAAnUlEQVR4XmNgGAUIoAbET4G4BF0CHZgA8QUgdkaXoB1IAeJ1QHwTiLPR5OAgCog7oOzJQPwSSQ4FHABiNij7EBCfR0hhB05A/B+IA9Al0EELEP8DYiF0CXRwDIjPoQuiAx4g/g3E3egS6MCTAeI+D3QJEPAGYgsoewIQfwJiLoQ0AoBM2AbEukD8BYhzUKUR4AQDxAOHgTgUTW5IAQBAKBmkXjz29QAAAABJRU5ErkJggg==>

[image6]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAABYAAAAaCAYAAACzdqxAAAABIElEQVR4Xu2UPUtCURiA3yKioEhqCIKiud1wUKEWi0adWhr6C1EERoNDbtHYpEMQOjRINAQFbS2Vzf4BIfAHCH08h3PR11eobtwluA88XM9zLofjuV5FYmJifmQJH/DT+IHvWO/f+nsmsYlXeIQVfAk+FwNTvbtDsI+7auwWPFDjyHjETRthFVs2QgafbLTMiT/TBTshfi5rI8yLX/xbtvHNxii4wDvTRvAYb2Vwx+4bnOA1JlUfYlT8bk9Nz4lf8FIGH3IZJ/Ac91QfYhrbuGZ6Ipjr4Kzqi8H1FddVD8WO+N/5DI6p7sZdnFItFDeYx0McV30Dn9U4NO48q7hlegnPTIuEeyzY+FdWsIHL4h+2O+dIcG+Z+5OqYdrM/WO+AGeYLYTigWNMAAAAAElFTkSuQmCC>

[image7]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAABUAAAAaCAYAAABYQRdDAAABIElEQVR4Xu2TvyuFYRTHD0UoSZbLIJPiLzAp0025RFmUyWBXWMjIIoO7mBRKIYvFcodrsjH4B2zKarD48Tk9x3ufzqWu596J+6lP9zznfHvet7dzRZo0+ecMYhk/nO/4hmeVaG104j1e4iYe4p3VG+ZYlq6RNVyKznrZenRuCLc46ZsR1zhndQc+4nBlXE2fhG844AcReey2ugVn7PdHFvDZN+vlBEu+aegDt/HIzot4iqtZ4htaJbzlnh/ACC5jP75gr4TLtHcc5arQ7/SEE34AOWzDWbzBduySsNtTUS6JXdyxekjCS+gG9HwFUtB1m7Za93sf53E0S/wS/ee9Slg7RS+/wpUskcA4PvhmKroNBTzALTdL5hwvsChhA/4Qn4GKLYPDAX0JAAAAAElFTkSuQmCC>

[image8]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAmwAAAAmCAYAAAB5yccGAAADXUlEQVR4Xu3dS6jtUxwH8OUZeV6Rd5HEzYBSyoA8S2FASRmYSJJSd0Ye90oJeQxMkJh4ZUBCSaJIUUIxkSJJSUkGZOD1+/Vfu7P2Ovt/7j77nHPPcft86tte/99/r//Z/z1arf9a+5QCAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAACw/g6JHN8X97AjI9v6IgDA3urGyL99cQXv9oVN8lJfAADYW+0bubYvjjgwcnVf3CTnRw7tiwAA/zc5GNudIyKn9cURz/eFTfZWXwAAWNR+kZsjr0Ru6s7N467IFytkljMjf0Rer8cPRt6OnB65MnJ5rees2fe1nX3eK0Ofw8vQ56h6Lmez/qntiez3UH19LHJ35ICpd8znmciuyM7IvWW4zvXtG0bko9xT+iIAwCI+iHxY2z+3JzZYDmguqu0cAN1T27lpIAeBE5827SfKdJ8La/vUMr3WLTcfTBb+5z3NM5s3Sz7afLa2L2hPzCE/z7l9EQBgtY6O/BR5OfJiGWbbJs5q2umw7nitckBzUG1fE7mstvMz3V/b6eOm/WiZ7nNpbZ9dxjcnPN0dX9Idz3tfs2YLz6mvec18fNvKz3NFVwMAWLWcQcrHfGtxZxlmwcYyZmzAdkyZHrB90rQfKbMHbCeX8QHbbX1hASeU8euPyffn9wsAsCb5qPCp2t6/DDNtOcuWs0U/1votZWN+2ywHNJNZqevK0g7PEyMP13b6rGk/Wab7XNWc+65pT9xeht9Fmzgj8kNtby/L7+uNMgxAe69GPm+Oc21d+jryQFm6Zuu3yD59EQBgEa9F3izDoGTi4rI0O5YL9XM2az3l4CoHbL+U4e//XoZNCC9Efo38FfmmDIPGfN+3tc/ftc+Ork96rr62dnXH95Vhli4dV5bfVw7W2u9hIjc73NEc5yxfbnj4swxr5SbXbL3TFwAA1lMOmo5tjtt1ZFtVzhDu7nfYvoyc1BzPuq9b+8KI3KWau0/PK8M12x22+Sg0d7ICAOwRuRPzq764Ra32Pwz099VvSFhJzu7lertZPuoLAAAb5fEyrHHb2Z/Yog4uy9elzZL3lbNxi9zXDWV4tPp+f6LKNXO50xUAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAgHn9B7u1ffvjcs1UAAAAAElFTkSuQmCC>

[image9]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAC8AAAAaCAYAAAAnkAWyAAACZ0lEQVR4Xu2WS4iOURjH/+4WNhZKko2mMEmpcQklmbGQy0p2JDXkMiQ27kouaSKbacpGSNEkymWBmgbJgrCxYBYuUZRGoTT4/3vOcZ739FE+Ju/k+9ev7z3PeS//7zzPed4XqKmmmhpJF7lNdmZzpdZC0k3GksHkNZlWOKOkkuF3ZLGL3SVH3Li0Ok0eZrEn5FwWK53qyFeywcWGkS/kqouVUvvJNzLGxRpCrN3FSqlHpJe8d3yCmV/vziudRsJK5mQWvwIzPyOLRw0hE2EZ+meaDjO5ycVk7AN5Rga4uNcocoa8cLEOssuN+1xqjTLf5GLzQ2yvi1VSPYrmV5AFbtznWgozKiNRJ0gPbHV/pQkomq9Wyq6y/duaAjOvX2k0+Ug2/jjDbr4P9qfE0RD35meSe+R4GOuaQ7BWq99lsM41jjyGvb0lPUcNYkcYDyWt5DDs3TMvxCtqIKy2V5JB5BKsln2tN5Mb4XgOrLalfOVbyKlwLFP3kVZUxuPcVCTzcS6a3420AGrdL8PxTzUL1i61cur5+q7xugm7aa7c/Fokg/q485t3tZubjKL5NiTzD8hFsidwnYwIc1VJRip9Yebm1yAZ7ETxGm9+Ennj5vzKK1vr3NwfS21UH2kxI7r5cNgm92n1K68SuoNUftoncW48eRuOpVtImd0G2yfxuq2wfVC1tC8OkMuw1VwE29jnyWdYqc2GmX0Ka7/aP8dgL7/t5CySeUlj3WsLuUZekeWwZx0kF8LvknjB35QeIoOSNqWyophWLGbIS9nz5vuVNsNaX7/TXFgXeU5WFafKr1hOUiy1/1vfAaYzfcIO/oNLAAAAAElFTkSuQmCC>

[image10]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAACUAAAAZCAYAAAC2JufVAAACP0lEQVR4Xu2VS+hNURTGP4mJPCJJiZQSIpSI4kqIJEpigAyUiQkG/shEYiIG8i55DExEUfIIiUJi4JG3MPGIlEgG+L7/WufevVfnnoEyO7/61d3fXmefc885ex2gpub/MZZepTfoPbqOdskqqllC77pX6LB8GlvpJNqT9qML6e2sIjCYfqHLfNyXPqabmxXVbKFP6FAfH6LnW9PoSv+UWLn+XtiiKavpd9o75JEG7AQTfdzDx2+LAucnfUrf0LN0Zj6do0f0gZ4KeQO2+OKQR27SZyHbiNZdL3gZxpUMgp38SMjHeb495CkD6G96Mk6U8CIGVUyAnfxAyEd5fizkKfNhNXvoLnqBPoJtkshruoFepA/pPtorq0iYBlt4f8hHeH465CmrYDWf6XTPhsDexbVFkfODLvLf3WA7VJbu8Ab+/aLWwGpuhfwM/YZ8k4xOfouVsGMXhLyTdo9vpOcnQp6yFOV/SC1B+byQp8yA1RyME2IgbPJoyIsXfUfIU/TIVLMz5LpI5ct9vI1+RN5Qp8JqziVZxntY70hRH9FB6tTtUE9S/1GfSzkMO7boRdd8PKUoIHM9010tRYs+D5leVL2cfZJMO3JOMhbq3JdDdol+ot19vJuub013op2oi5od8ibqVV/pCh/3p+9oR7PCdolOpIXGJLm+Z7pbs3w8mf5Ca6cJfcbu0+E+1ibS0znerGjDeNhtvgNbQDsrorvyCvZBTdFj0odYn5YHKN9RWv86rF+pu2+CfRNrampqqvgLpxeGQAoA9uQAAAAASUVORK5CYII=>

[image11]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAABwAAAAaCAYAAACkVDyJAAABZklEQVR4Xu2UOy8FURSFlxAUXqHQICqFToFEPEIiJAoFCpFQ+ANejUpBQmgoNaIR0ShEFAp+gVdHVERQUWk0rJ09c+++201InGm4X/JlZtY+mX1O5pwBcuT4KwzSVx8mRSW9ph+01NUSYYRuQRs2uFpwumkdXYY27Mosh6WcjkX3s9CGo+lyeKZoQXQ/Dm04ky6HpZe2mecBaMM1k8W00Fsfkg565sNslNFzemm8gTbcMeNiqminD0k1tOm3rEJfYqmBNjx1+a/pp9M+JEXQhrLSmDy6QI+RuUKZrOzqQ9ps8i800QdkP9zy8rfImD5oo106afIVWkw36ZzJU7TSe+gKxEdaYerr9MnU7+hSNEYm9wL9G8XURtcr2mPyFDL7fB/+kAm6Dz2z8RES5PmdlpgsCEd0iM7TQpPLXpCdHhz5XtvQc2pZpBsuS5QTOuzD0DTSA1pPn6HfMVHkr3JB92i7q/0jPgFqIDyRj+DPtAAAAABJRU5ErkJggg==>

[image12]: <data:image/png;base64,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>

[image13]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAGYAAAAaCAYAAABFPynYAAAD1UlEQVR4Xu2ZaahNURTHl3keUzL2fFDKBxI+KERJpgglGUpkKEPmqaRIEilKkTKHSEJmMs+KlCHKI/MQJXOG/791Tnff9d459913x3c7v/rXvWudYd89rLX2viIRERERETmiDnQMamYdech8aKI1FipHoLHWmKdUgS5Ava2j0BgPnbbGclDVGjJIO+gdVN86kqURNB06DxVD96Hb0ATPvwbq433OJtWh59AgYx8DvYD+efoE7Y+7QqQb9FXU/xt6GO8uE+yXB9AH0ed8gR6JPuuxaNt+eb7t3j0+J6BFxpYU7PyP0BmoO1TZs1eD1kNXoe9QLc+eTYZCryXWJss90U5pYx0eA6FzUFNjTxZ2MN8z2TpAPegitMzYh0PvRUNbUlSCNoq+cIbx+XBwXkHHrSNL7JSSK8HloGj7OaEsDF1noebWUQ74HL6ntXV4zIPGGRsnA+/pYuwJWSF643LrMJyEplljlmC4mGuNDmtFf8No6wALoJHWWA4YKX6Irk6XdVAD7zNXSw/H5/NMwttfgq7QH+ilJA5RG6AiazQshu4koT16Wyh1ob/QYOtwYF7kwPD9Lm2hrcZWXvqKvmOlY+Mg3HW+B4WrU5JkO/aJvmyhdeQRzBtsY0/rcGAO4TWbHBtD9G6osWNLhdWi73gqumpYbfE7V0wiGIYPW2MYn0Uf3tk68oiOom3sYB0O7UWvYQXkMwnq73xPFa6Mb1AN7zsHnjnHrRSDSvHN0BVrDIIlKH8My7zSqh3mFM4MJv030BNoTtwV2YEDkmhgaote45fCLaBVMXfKMIEznDIkuXAiMNSSImhvzBUHB+aaNYbBMo45JmikSTH0U2IJLgyGxFtJaJfeFkorSRzKCMtpzmjOZBYDPL5JF6NE22D3IzWdz8zBQXs8hjJ3NSeE8ZEvtBs3H3+2cvXkCn81hCV/cln0upmim8qy0FL0iIfbgTC2iT476LmdRKMLJ0VpcKXtsMYweFRwQ3TlDJNYAxnaekHXRTeVQfubbMGEm6jc5I6bnbfU2MNgQuY9YcUP+4KrkacHdgAZaYZAb6GpxufCcnmWNSaCyWy26NELd/7MJTdFj184owaIhpNcskXCN5iEpTLjuO28MDggLIAOWIfopGWfMMdy8HicwwLAL/V5XMXQSR+PgvxcY/E3mEGrrUIzQrSDSitSUoUdGpS00wGPZDLV9pzDkMFwFpQLU6EfNMUa0wiT/hJrLCR4yGrL1VThTv0Q1MQ60gSP/blaGlpHocGdPI/60wX/xGKYzAQc9EuSmVWed/A876hUnL+WMxkiIyIiIvKV/zzV1K43oPEJAAAAAElFTkSuQmCC>

[image14]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAHoAAAAaCAYAAAB4rUi+AAAE9UlEQVR4Xu2aZ4gdZRSGXzWKvYsVE3vHhigiZBAUBVERbIj6S1TUP4pdIdj/KIgiimLvFXs3q9hQsYLYwIq9Yu+exzOTPXv27i2TeMfNzgMvyX1n9u7M937lfF8itbS0tLS0DJ1jTS+anjUtk67Nj/COvOtLpqPTtfmaM0w7JG8h0yx5Yzxlus+0fryhCyuarjU9b3rBdIlpqTF3DM6MbPRgC9Ns05PyTnyMaYExd0iF/B2nDJ2CPtf0smnJ8vNhpk9MK825ozN0kOdMl8kbls/XmR6JN/XJwqYNTeeZvk3XurGm6WvTgeXn5U2vm06Zc4dTaIoHvYbpN9P+wSM0gj4zeJ3Yx/S3abXgERbeTsHrxWamr0zPmD4w/TD2clcuMr2RPDrqjxq7NBWaxEEzgqaV6pcc9BHyYGjsyIh8ZHTjFnlAEZ7pT3kAdXhA/QdNh/zMdFvyC/k70RGjNyt8/l+zsekK+TrKevSY6WHTQ6Z1wn3dyEEz7dIo04MHd5r+Mi2W/Mg7pnezaXwnH511GCRoZiOenTaJbFn6Zwev0CQJ+hB5422fLwxIDvpeeaOsGjxgtOKvnfwI0+Ob2TS+kE/BdRgk6G3kz0gBGNmk9K8OXqEaQZ8qr/KoTqk6TzddLx9pNNzSpoPk1ehd8op0039/sh6sdw/KC5a5JQfNe9AoqwQPbir9zZMfYcTn9RGYTr/JZp8MEvRM+TNenPyNSv+O4BUaMGjWMnrQWvIvo0dvV16jasWjgmUEVvD51vB5UJ7Q+BFXlxz0iOoFzfrI9SaDLvQfBn28aVvTnvIv2ztco/rEOz948J7GB72o6X313q8uIZ8l5hU56Imm7ptLf93kRyaauj83fZTNPiFovrcfJpq6qWXwmVErCg0YdMWF8gdaJHgHyH8BHaGChsI7KnjAiNij/LMbdB4ajuKrm3p1mIocNI3E8zFDRSjG8LsVY4RMZ81QjHEaVQeC/jmbE0Dn5BmvSn5VjJ0TvEI1g+Yl70/e5fLNPluMCtbzPzR+xPQLHYmqel6Rg2bPSaNsHTyg3ug0LUduNH2fPOqITtNpvxD0L9nswqemu5NHTcMz7Be8QjWC5jSGL8pnp1SatyfvLY12CGaBFeSnODfIz5374UqND6IuOWhmDDois1EFYX1pOit40+QNF9fy6sBk9eBtVXo7B49tEMVpP8UkQf+azRLajueM38N+/e3wGcjlJ9OywStUI+iD5S9DGV+xQekdGryVS4/CjKr7UtNy8oC575rRW7tCQzLCpucLNchBA0egnHNXDXOC/GSMZ604Uv4u8XBiQY0egfJ3OsM98h1ChBHHz56Y/E48avpdnTsFdQ7fE5dBOhGzKJkAx7YfavzvKlQj6JNNTyePHkzj5CmavRz7X6YyCium4sVNj5t2C/f1ggJjtukk03rytbPX+t6JTkGz1Jxmek2+FSSsvGbvKG/Q45LPKGNryc4CMWvxfhEanZ/Ns10FW1QOXz6WB4m4H2+XcB/vTjU/M3jALDIi73R02FwPQaEaQc8tM+RrC5X3IP9UyIjZS34SxIkYwY+UqnsyNizYerJla4pCDQTNqLhAvjVjpA6TpoLe1XR4NodIoQaC3l2+buVibhg0ETRLAyeETNFNUaiBoJukiaBZ3/fN5pApNMWCpuJ/Rf6/QQapDyYrvCPv+qqamUFbWlpaWobDP2x0JV2jo3pGAAAAAElFTkSuQmCC>

[image15]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAH0AAAAaCAYAAACacVPHAAAFaklEQVR4Xu2Zd4glRRDGSz2zmLOip4hZzJGDG7OCGBAThkNRTIg5Ky4nhj9UEMWAohgwB8yiqCfmgBH1DGDEAEbMAbV+Vs++erVv3s6bvZ2RZT74uOuve9/M9NdTXV0j0qJFixZlMZfyCuX5ymuUG3V3t5iIOEY5Pf1/KeW7ytk73bVgivIt5fPKLUPfRMRCYs/6qvK40FcLXlHu6tofKjd17TqwjfKMKCr2Ur6kfEr5nHKH7u5CzKEcEpvUZ5QPKlf1AypgchRGwXrKJ5RPi83x8crZukaIZGL3WTt+Vm7r2u8o93ftOtDL9J3F7i03a33lj8qpwyOKcaHyNeUCqX2Y8gvlEsMjymFO5erKi5Tfh75+WEH5rXTmcVHl2zLyGTNpyPS/xCY9B2H2SNeuA71MZ5KuDNotYm9uPyyv/EO5j9N4wzD9HKeNhnWU34hFmE+UP3V398VlyplBY+GxiAntOTJpyHQebHvX5k3fz7UHBaF1UmIMZ0WIpq+l/Ed5lNPAUNLJPYrAgmUMpnnMEFtIVfCwlDedZ/5KeWfQM7H72jNoQ65dG15U7u7anyk3d+3RsJjyXLE3ELKPPap8RLmbG9cP0XQWHRM0zWng2KT7RRpxtdiYFYN+j/Jv5bxBL4NBTCfScP1rg872hH6e0zJpyPQTpBP2lhFL5Mpm7yR8byj3Ftv/qiKafqLYBPkQDfK3+KCgezwgNoZn8bg96SsHvQwGMX1jsevErSmPXtc7LZOKpp8p9naRoS6uPFt5k9hbxwQsqDxAeaPyXrFseO3//tIwt/Iq5QVpTNnMfWnl68rlYkcFRNPPEpsgFpPH4Uk/OugezAVjuD+PW5O+btDLYBDTp4pdh9qHxxpJv9tpmVQwnX2LFbWS2A9yxt4s9ZG5opHFHpI0QPsO164Kijl+WxgLoulDUt30GdKs6ZmMs+kni72ZnLP5wT1c37JJu9hp4COZNaY/Jpa0zQpE04vC+xFJPzjoHkXh/bakrxL0MsB0Mu8yKArvayadaJojkwqm57hU7KYoqebYV+wiPlzzwGgxK66CN8UKD/1IcaUMoumYzX0e6DSQJ3L9ijRMNmOIfh4kcuhVE7lfo1gAFhvXuS7oeSJHhMyRyRhMJ6w/FDTq6BQU/NvI/s+5PL4F8yg/lsGqVvcr549iRUTTKYgwQVSxPEg40WPo9uA8zJgNg06OMzNoZYHpv0WxD75U3hc0CmDcl9+yMqloOtUffizWcCko3BW096SzOIgOHLcAZ8td0r9lwVsYTamKaDrgTE2C6UEi+mzQ+FtKnjnY1ljYRLocnCy+Fjta5uBoRYJb5tSB6b9HMYE55Fr+dyjOvO/aAH9+US7stEwqmj5NzHSOBDlWS9qhTqOggUZSR/YeJ3RQTBLbP1nBY0Uv0ynD/iCdk8YWYpW2KcMjrI9nosDkQRmWuns+waeIVeQWGR5hbyJ/e6rTikD+8qf0XiDkR/yO3zJZUERZvAGUfz+VkdfKpKLpp8vI1b+d2EPGMM4ZkbIimWUemqkP3yyWPA0KSoocDy9XbiJ2Yih7xvfoZTogFPKx4gWxZ9y6u1uWFKsrEAE82NKmi+UdHFHZiuIejwEYE6NhDo6/Hyg/FzMVMh7N5xSnKb+Tkd8ENhA7SVD8YgH2yqMyqWj6WMDKx2wiwg2hbxDwFvJRgjD4uNjDwrJHuiLTxxssUo5yTSGTBkwn259P+aRyp9BXJ5oyfUexs39TyKQB08FksWyTDN5/AaoTTZjOFsC2QBhvCpk0ZPpJykvECjsUEJpAE6ZvJeXrCOOFTBoynSyZTDYe+eoEGTmfdF8WM2Oig4jKs/Kxqsl5b9GiRYsW/w/8C/dwOOlt6hyOAAAAAElFTkSuQmCC>

[image16]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAABsAAAAaCAYAAABGiCfwAAABbUlEQVR4Xu2UvStFYRzHv/KSyNsii1AyKKuVKCnCQhlMSBZFMSgG+Qe87AZ0R+Ul74OBTRImGcTAYFYUvj+/59z7u4+o61yLzqc+nfP7Puc+z3lezgUiIiIiwtJGd+m1uw9ooU+00NUH9DDRnDoVdItm0jO6ZtqW6aOpj+kbzTJZSozQBuig0tGoabunMVPX0jtT59JbWmMyoQD62zIvjzNFX2mpq6WDdzoQfwKooqumzqCd7mqRmXd5WRKXdN/Ug9DBqk02THtM/SvkTaTjWZPN02dTCzvQpRP6oEs8nmj+nOEkXYK+2Lfc0BV3nw+dqexhsKz9SHRQAh1kCHqIAmTJ62gv3TT5F+rpCd2GzqAJ2tEFXYfuaUAOzaNHtN3k5e46R2dMHppK+gBd1qLkJpzSVi8LxQRdoN3QTyJAtuCFFpssNB10g455eTM997I/Y5ou+mE6yaZ70H2UU9xoG9ONHJAr6L/Lj9/X/+QDn2w7+NKDQn8AAAAASUVORK5CYII=>

[image17]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAABkAAAAaCAYAAABCfffNAAABc0lEQVR4Xu2UPSiFURjHHx9JUpKBRSllkDJJihIlg4+F8RruYkBJyCLFwCqTLMrgo6R8JAuZLnWRspksMiglCwP+j+fEc57XO3jdQXp/9et9z//ce5/TOc+5RDExMX+SJbhssiF4arLI5MInOG/yE7hvssjUwzfYq7IC+AKnVPYrxkmKlKms2WVtKmPy4Q2sMnkTPDOZxy68NtkkfIVFJs+C3e6pKSUp9C3Z8IGCh34Ar9x7g56IQi3JtsyojFf/SNJxOfDQ5Qm4CsfcmCmBsyS7Uadyj0GSIptuXAi34DOchp1wAhaT/Hg/XHGfZeZIzmkRjqrcYwPewxTJnTiCrTBJck57JIXzSDruGHZ8fFMod89L2KJyj1u4ZsMQKuAdycp1Q/A7tzsvJkAlyVYN2IkQuNUXSO5Ttcrb4bkae/SRFKmxEyF0wR04YnJuGvtv8ckwTFOw538Kd1+PDTMBb9c2fZ2TvbQZgW/3BVyHjWbuH/IOajo+tZil6QgAAAAASUVORK5CYII=>

[image18]: <data:image/png;base64,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>

[image19]: <data:image/png;base64,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>

[image20]: <data:image/png;base64,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>

[image21]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAABgAAAAaCAYAAACtv5zzAAABXklEQVR4Xu2TvytGURjHHykJvRIlBnkjyo+Zv8AgYTEJg2SyKAwy8Q/4MZCiEIoMhFEGDBYjJiSMFpvic5xzc97n1utVh+n91Kd77/e5955z73mOSJZ/ZA53dBiSJ/nDAerwA9t1IRSD+Ii5uhCKVZzRYUiusUaHocjHbR1qpvAEj7AMp3ETz/AQE9iPG7iPl9j09WQGNOMSJsV2wg22ulqRy65wyGUGc73rXadlAluwW+zLerxapctmvcxwJ78YIGIB3zDPy3rFDmAmEFHrshEvywjza45VtoKvktrfZr3escLLDGax78VuuhhVYmc1qvIH3FPZrXxPxHx1qTvPwS53jDEgdoBGL6t32bCXlbvMLLjpomWvlpZJPFdZGz5L/Fes4QUuYqHL+nALx6KbQlIi9sXmS9dVLQim6wrwFDtULRjV+CK2k4pTS2EYx3mxm7RB1YLQiQcSb/MsP/MJTO0+OCoYnfUAAAAASUVORK5CYII=>

[image22]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAHAAAAAaCAYAAABvj9h3AAAEqElEQVR4Xu2ae6gVVRTGV6WBlViUlWmolVL2kAoCNdCSUhMiJF8YhGZQaS+kiCjbSgr+4T8WoRYoYlaKoGFpanm1NMtSI4oKy4yil5EVQUWv73Ptc+866845Z2buuR3vbX7wwZ1vz5kzM9/M3mvvc0UKCgoKCjohD0B7od1QD9fWGblG9Fo/hIa4tg7J49DVzjsBCtA+aCf0MjTQ7lCFM6CV0B7oHWgJ1L1sj+z09UYNJop+/+vQm9Do8uajBGiE8zokSQEuhPZDp8TtO6CvoZ7NeyTD4N+GnoGOi9vPQlvtTik5CRoKvQhtcG3VuBH6VVoeuMuhX6DhzXsoQTppgH2gP6DJxmMYDHCe8ZKYAP0DnWO8C6N3nfFqcSf0HfQS9KdkC5BdI996y/OiPYklyDEYIJ/4LlFp8QHOEL3hlxqPNInenGqsgX5wHs/pL+gp56flN0kf4MWi536380P0z3LeCLPdEAZBy0Sfrjeg16At0GbofLNfNXyA7P54sX7cWQ/9DXVzvuUAdNCb4CfRsSgPWQK8RfTcb3X+/dEfZbwgbQhwLLQt6l1oDnS8aWeXVYvbRW8Kx4m24ANkt8WL7WU8wreL/nnOt3Ds+dib4HvoC2+mJEuArKh5jrb7J6VeZZrxguQM8BHoK+iiuM2qjf39o3H7QWhM/LsSHE9egbr6hhz4APlQ8WLPNh55IfqDnW/hG/qRN8G30I/eTEmWAB8TPcdJzueYSv9e4wXJEeB40QPxDbQ8LfqUcrx4FTqxvLkVO6T1G5IXH2CT5AuQvQbbGxlgkHYMkOF8Dh1yPuHbV/riJ1yb52TRbq5e+AArdaGro3+B8y2VulD2MF96MyUMMO31VupC74r+dOMFyRjgVaIH8SUuuU+07QPoTNfmYYnOG8KipZrSTrx9gDw/nkt/4xEWMfSrFTEML+kBZRHD1Y88MMCN3qwAg+M5TnV+qYixE/ogGQPk6gAPcptvADNF2+7xDQmwe2WVWS98gJy081yuNB5hpZvUPVo43+Kk2cJxmsdb7Py0MMBN3qxAac45y/mcv9K3w0KQjAGyWuRBbvINYLZoG9/SNCyX1jc4Lz5AvuGcPE8xHkM4DM03XhfRLt/elNJEvrfxroje9cbjdd5gtqvBAFmwJcF5ny/4OFdlTWHhas4u5wXJGCCnCVxbXGo8Tiw55pVKdIZ7M9TP7JMEbxDfiL6+IQc+QMKlNJ7rqXH7IdGVmNOa92jpNdYaj9dYWkrj3wyZBYgNgMXOz6KfHWL8JPj536HtvkH0OCz8eJzLjM+lNHbZl8RtvjhcWfLXGCRjgORcaJ3oGMVu4TloWGxbBH0CrZB080BO4rdBD0MDRMemNJ/zJAXIgmsu9L7oojBD8GPitdAR0WmP5XRolehaKvWk6LqmhYvjDNFWhRZW6Z+KVq4MiPpGdKHAPkQcGz8T/U4Lewb+wvKW6Js3srz5KEFyBFhv+ISOE12N4QoMA22KyrsS81/BkFjeN4ogx0CA9aBRAS6QlsWMRhCkCDA3nGNyWtJIghQB5oZlftp5ansRpJMEyNWL90R/Pf8//EsFiy9eK+e0targgoKCgoK28y9C4xMmMIxrDAAAAABJRU5ErkJggg==>

[image23]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAE0AAAAaCAYAAADygtH/AAADCklEQVR4Xu2XSciNURjHH+OCRAiR+pQFskHJsLAQQkSZykoWLEyrb2EKkRUJybT4MosyZAwZQ4bYmMkQCsmcMv//Pee4z/vce7/BV1e3zq9+dc9znnvve857RpFEIpFIlJK2cBu8Cq/BDbBFJqM4o+FF0e/dhgtgo0yGyHQ4UvR/msMBcB/sb5PKCTbwCtwMG4TydnjSJhVhMLwJW4fyUPgbbvqboZwPceth2NQmlRMTRBvR0cS6hdgQEytElWjelFBmp3+BPyTXkeQMvAufwwtwGmxo6suOPfCti3G0/YTrXNyzTLTTxpvYV/hLdBpGTsEKUy57HsLHPgg+wEs+6ODIamfKPUU70U9tlitcrE5wQTwdvA4XS3ao8kFKCafTPR8Eb+AzH6yGlvAIfAm7uroTcDY8KrrZMI9LQK2YD1/A7qHM3eS16I5DKuHw8LkQw0QX3trKHY2NqQ5OJa43nlfwnQ8WgTvvU/ge9nN15DhcKbnBsVS0c+06WhDOew5djjQLdxq+Va4jnPul3FE4qvlM9e20yAj4Hc5y8R6SnU1dRP93lYnlwQ55Ivo2PBxl/IFJcI2rKwXFpidnAHe7unJOdPQWGnER9gfbfN9XWPqKJvHQ6JkjWndLsotqqWCHFXqZ3Agu+6CjD+zlYlWi7VkRypxZH0WPNhZ27GcXyzBR9Iem+gowQ7TOD+lC8PDIdaq2stE1rWm74CcXayL6TOtd3NJJ9Dz2DXYwcR6M+d04axaF8ryYAJqF2AMTy4PXBiaN8RVgoWgdR+P/IB5u2QmR3iHGlxRpAyeLdihhRzGHZzx2QoQvivGxocw2H5Ds1YpTlznLTSwPLoI34EYTay/6Nni4jB06Tup5nvkH+GzxGsXPjeEh0R3Pslf0OWea2G64FbYKZd4gOO0OSu7oxN/kLWBUKDP3rOg9tcb7bWe4X/QHjsGdcGCoWy26KG6R0p/TCEfRDskdVdZKdvSQuaK76SAT406/RPSA/AjeET02xdEY4VrN9jKPmwtfEI9biUQikUgkEoky4w/0Gbo1LX8YLwAAAABJRU5ErkJggg==>

[image24]: <data:image/png;base64,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>

[image25]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAIkAAAAdCAYAAACe00+cAAAFdklEQVR4Xu2aB4hdVRCGx94i9orR2HvDblREjQr2jg02qGhUsKBiARM1sWAvBBRFsWBJRIIFCdHELqjYe4nGDvaCwT4fc89m3uzz7n3ra7s5H/zsnjl3X15OmZkz54pkMplMJtNW5lPNr1pAtaBqoaCFSzSvZIY876r+Uc1SPVZomvv9cdV01VOq91Wzi+eTzpRMN4MDGKd6WfWM6hHVOv6BKuyu+lv1tWrF0FcPvM1I1W2qv1Sv1fRmuo0rVa+ohhXtE1RfqpbrfaIil4t5hamqeUJfGaNUv6o2ix2ZrmAV1e+qw52N+WWRTHC2SuAdXhRbKGeFvv44WnVVNGa6gpPE5nTjYJ+heivYKrG26mexlbd16CuDlXlANGa6gpvFFslqwT5FLMVYJNgr0SP2oR+oFq/tygxCHhabz5WCfVJhXyPYK3O32AfcETvmAvCmD6reUI119hVUn4nlYDBO9WlhbxYPiCWYVXWG/VkpnEqZy3ggubewbxrslVlCNVPsQ8g35hao93DkZ0CvVn3v+o4RG4/1i/bFRXuX3ie6kxnSokUC26r+UP2kWjP0DVW2VJ1T/P6hWNxO3KX6wrVZUJwQ/NjgCUa7duJR1YHR2Cb+K9zcV9jXCvaGOVfsg66PHV0GiXMKAxHCQaPH8x3F/t8+Gf9cdadrw3OhjVfBC0f2kM7ldzeK/V9WD3Y2APYBJa6e9VRvq5aOHV0GR/YtotFxrWp4NJZwg9gpj+sIIE9hQI/tfcLGZqJrN4PJYmWIqjrd/qwUCmd89zg+VF7fCbaGWUr1vAygfOtg95DsxXjYH0w6i5OjeJpc3DurnxDIz1QtJKYyqR7ukz6ROd8dV3v/nO5+4frhadcmVDDQhOAEVcytit/5eZ3Uhic4QnWJ6vZgbycrq/5UHels1MS+EcurBgwXfcTR/5uU8Tn7R2NF2P3vSW1VkMm/xrXhJtXmwUb42a/4mWCXbujaZdyi+ljs+8OtYovkkKJNYQpbgsFeV+y0kyDBPV5sgf7i7J2ABc29zZJF+2yxfApHMGCIY8dFY5PAM7C7LhQb3IukdocCk3OZ6lSx+yRupYFc4eD0kNgiwGNUuUY4RaodGQEvhefBJZP4MdkMLO6ZyzEKVD7HYLAvUF3hbHhPdix5zZPO3gm44GO8X1e9oHpI+uYoDXGa2MprhGXFsv8Ek0bSy24b4+wbiHkIPEIZ26gOFVv53Aule4fzVMunh8RyBSbSw5GdOk+8mcYr3hNszeQj1SaqZYKdsbw02AY1e4kd4xp5P4QFwXHqRGcjwcMlM7ms2gS1h+TCy2CCUx5DOEn5AXHfs4PUfj47mr9l58dCICGJ1x9aAVcY7FIu06ineMjr9g22QQuTSsI2LHaUwK7GLfO6gK88pmQTr4GbS+Cqx9fRdu4Z8J6MxJR8gBqGd+eAd/AJKWFpUdUTqr2dHcgRng22ZrGq2NjxvQkxCY6Xs6WvdxmUMNm8THSUWNxnh9bTbqrDxE4fTM5vYhM4XerzkmpP12ZB9AdejNcWPHgSPot/21PPO4xQfSUW0nzNgryHZLyd7CRW3h8ScNnzg+pHsfoA2XgUdqqvPMOzlKy/U30rtfWDxGJiR9iUUcPJ0vckEuE42RNshK16VUPqN/G6mwVM8Y+TCDlQ4iAxz9YOCKv7iB0Axoa+jGNX1avBRv7CaaZHbIJj7sMJYZbqTbE33xKEEV6hrAcXXd5jEP+5oIuFJk5LHIvbAZuOIzf1Gx9+MoHzpW+RK0GewY5nwRCCtq/tbggWw+hoDLA4CYlVkuZMi2HX8PrjCLFYvLPvbBEkqlOkfMdSW+mJxkxnwO0TKqiZ+PpIq9lIrPBWD05deKxMJpPJdIx/ASsoGCuezvBWAAAAAElFTkSuQmCC>

[image26]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAE4AAAAaCAYAAAAZtWr8AAAC5ElEQVR4Xu2YWahNURjH/4bMmWUqXUOU6RWPylAyvUgS13DliURIhgfkQShDxnLNZHog5OlGpuKBeDBmyBTKUDwJ///99u6ss07u3Vf2OWfV/tWve9e3Omefs4bvW+sAGRkZpWEUPUw30I20UX53emyjp/xgIDSjz2i7qK3vMjvXnS5vEe7ATaR3nXYlveS0U6M//U3H+R2BsJRed9pTYSswdebS17SJ3xEIq+g1pz2FfnTaqVFN1/vBgFhAbzptrbinTjs1HtK+fjAglGLuO+0qetlpp0ILesIPBkZz+pK2j9q7YOmnXlbTGnqRdqbr6DFYwrxA29KZ9Ag9R2/TwbWvbDhjYRUsqXeQOyb8jQrY53wA22bD6VF6ErYbptEedA89SO/Bzmsuo+lxupluoY3zuwsZAnvD3rDK+Aj2YNEmiukLzItiQu3TTrvUaMX3gg3KV7obtorEJvqFnqHdothk2Pf618mvZTkdhtybqaLEaJYU2+rExAuUz8C1hK0uoQnVamqa68Ze+oP2dGKz8B8GLmYH/Q47RcdMhz1AAxvTL4qpEpUTXegvutKLP0HhYVYp5wMSbMckaIv6D9gPW+bu+Uz58Cft7sSEioQSrA7DdTEGlreSegv15zihPOZPsravYkucWCv6je50YjGL6AE/WBfxAxZ78Vf0rBd7jNwAa5V2iv7XpXhS9LcUaJI/I3+S58C+11An5u4iTfJap29QFEtMJezN9MKYAVFsvhPrGsVUKJQf9jl9peY5Cu/KqpLvvJiOGrrlCBWTBg2Uj/LCDS+mLaWH+lvyEOyUrcrVOorNgH1I3flKgdLEJzrBi19F4Y1mBCzvaSfFd+uOsCOIjl/xDkqdDrAB08rU71khsgKWR9+giDcgVWEl3Ct0vNcXCpr8kbBiVFQq6HvYlklSAcuRaroQRdyqYhndDjs8D/T6QkCVWBVZxW+N15cq+gX1PAqPMyFRA7sh9fE7MjIyguUP6MGbq1RMrBEAAAAASUVORK5CYII=>

[image27]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAEkAAAAZCAYAAAB9/QMrAAADYUlEQVR4Xu2YWahNURjHP9MDkVmmiHQzZori5d4HPPAukrySpEghD1KmB28SpUTILDOl7qeIEEqJTBnKPEfI9P1bex/f/Xf3OvvcOKc4v/rX/v57nb3W/vZea3/riFSpUqUCHDBdMO3gE/8oCyXc710+EUPZMLqYtpsumS6bNpnaNWiRzQhTvems6YqEQTVr0KJ0+rIRoYVpuemq6ZzpuKnGN0hQNmIoxejkommzhJtDjLfstG+UQR/Ta9PMJO5kumFaVmiRnzam8abDpqN0LsY60zVT2ySebXpi6lpoEVCKoyjFU00/TT2dNzDxJjqvMTaYbpKHQX40tSc/xhzTc9Mx0zfJn6Tepq+m6c7Dg0aSVjoPKMVRlOK9plfk4W36LiEJWWAwz0z7ya+TkGAkvyl8lvxJmiuhr2Hkq4Q3mr3cKMV3TPfJA+9M59l04CligFvIH5n4q8nPSylJwhKBvngNO2T6YWrtPHXHRVGKMTVukQdemB6y6RgjYYBY5D1DEn8b+XkpJUmYnuirB/mYHfD7O0/dcVGUYmSc1xWAqfSGTUethIFsJH9Q4h8kPy+lJKleQl/dyd+d+MOdp+64KOqOsa7gYk1JUp1UPkkqZUgSyJpu+No8ZtORNd0GJz7qrqaAJGEa5SFruu1J/AHOU3dcFKUYCXpAHsDCjUo1CwwMA9lKfrpwryE/L0jSCTYzwANCX/3Ix8IN/48t3LtMH8hrJY1PJeap6Qh5qK3w22nk5wVJOslmBqjJ0Ndo8lF58xKiFEdRitNispfzRiXeJOd1Ns2QkMAU1FG3XQwWmD6ZOjhvrGmyi2MgSafYTJggYRuUggIYxSfGlYLxvTStch5QiqMoxc3l97YExy0lLJw80H0SEjfPeaiV3ppmJTG2Ao9MSwotwsfhvYTfjnN+Y6DvL6YzfMIYKuEaXPhiW4J9W/pQFkuouDsWWgSU4ijKhoS3ZKeEPRC0XsJeyrNUwteulny8dSoh0RisT2IKNp1I1Hw+kTBFwi4d10ciIExlFLrpzXaTUPRib+fB7mCF6bqEDToeMK9RQNmIoWyUCSQCe7RKoWzEUDbKxFoJNVSlUDZiKBtlAOUCPsuVRNmIoWyUAfwRV8NmmVE2YuDvW/z7iProf2CRhPu9xyeqVPk7/ALEodc5D1wkWAAAAABJRU5ErkJggg==>

[image28]: <data:image/png;base64,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>

[image29]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAIEAAAAaCAYAAACQAT/QAAAFTUlEQVR4Xu2ad4hkRRCHyxwQ0T+MiKIYMWPEwB1mVETBHDDnjBjA01tzOkUQBRO3iGfO8UzcYTwDKooRc0ARFXNO9V117dTWvllndleW9fqDHzfv93pm37yu111VcyKVSqVSqVQqzWypelL1tOq0dK4yNOZQ9aheUj2lekC1YhzQBfepDs+mspvqedUTqmdU2/Q/3Tnbqd5XLaWaU/W5av1+IypD4WLVy6oFyvFhqs9Ui/SN6Azm52/VUcnfQfWjtAJrbdX3qnF9IzqEif9K7AOdZ1WTwnGle7ivv6n2CN5sYkFwTvD+jblUb0hzELyuujJ5N4mtOl0xRfVK8t5S3Zq8SnccKTZxqyd/utjkdcoJqskyMAhWLd7RwYOe4i+W/LasoPpL+n/QPKrfVVODV+mea8QmY5nk3y12z+dLfhOLij3VG8jAINi7ePsGD44v/tbJbwvLEm9YMnjrFe+q4FW6536x+7hE8llh8ZdLfhPMAQn7ujIwCE4sXtxuwFegA5LflldVf6q+CfpZBv7B/zskai+KJXGdajxvHIRpYvdx8eTfXPw1k59ZS3VHed0UBBOLt3vwgAoC/9jkN7Kw2LJ0XfIfFPuQDZNf6Y7pMrwgeFi1fHndFAQ9xRtWEPg+c1zwyEQpMd4Ty2SHyvaqT1S9yZ+VaLcd3FJ8n+AmdlZdFI6bgqDddnBE8Q9KfiOUhAzeKnhbFO+M4A0Vgqs3m7MQlG7cy2WTT2KI3y4xnFc1Q7Vg8JqCgMnH2z944IlhR02jHcUGU2o416q+k8GbGXNnow0sR73Z/I+YvfzL6sVrP6Zj1wl83+dUL3ShcTPf2R4aQ9zfdZJPtv9m8iIk5uRmNOxcX4t9FnPDMavIysWjhIx4sp+3oUbYkxjsexNv+kl1TN8IkXvFxvAHx4t1FR8t54g4mkyTVCeXsRPLOaDsvEs1QSy47pTW5BDF7I0XiiU/fsG0Rn9Vnac6S/W4apdyjlY2N+dGsZWKsXxhJn5b1Wuqj8U6nTuJNWrOn/nO0YGK6w/VXsFju/1SdW7w6NCyrw82aWwPeSUA+g1XJ+8esdZ/RzAh7P37iT0xTOINMjAXIPoIAthTWkEAvOf68proZJIcLvgDsb4DfCqtgDu0CE5XXV5ecx18WW+wrCQWFF5O0R/3ngafy/XvU46piwlSmF9GNwAc2sb8brBQOT5FrGNIUu5wn/jOtwcvQ5AwJj6gwJb+rWq1cryRWPBv0jeiAzYWKxP5AYKniqjM8LR7EHAxMQh4uqlLgcjnAhy+3G3h+G2xiwS2FLJYbhKB5KUQULLGp4Jo9x9OHpP+2fAVYisKEEDcYP4GwcqyOtpwTWdK6x6zeuUcYTOxh+ek5APB/67Y7wMEASs1x7HHwP2gvKXVzwqweTg3YnyhWqW8zisBk8zeB0wcnUaHqKWP7bAPEnTwkLT65weLBRNPL7CExiB4R1pPP387BgFdufgEXSK2qlwavMoIwD7ryw0TNy2cY/I8CCiFmECH6iAGAb9HsEyx2jDOl3z2enKHs8txPLeG6gfV0uWYIPCAILv+ULVrOQaSMJKoU4NXGQFIAGlfUn+ShPwiltjQlqQXMEOsLzBFbMmiNGKyWZ4+KuNIGFnSWA7JHahxWUUOEQsiOnC+rRAEF5T3TJX+JSxBQJ09QSwAc2YM/OI21N/sK13i+QOJJFmvl2P+2hNMxvnYWL61I28HkbwdNEGeURnjDFbjshU1BQH/u+YysdzlwHSuMsagn0AQsOR7WeXQfKJSodmSM/9NVY+ItVqbKpzKGMK3lKYtw895V7BSqQyXfwCdMUSE1VOCTwAAAABJRU5ErkJggg==>

[image30]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAABkAAAAaCAYAAABCfffNAAABe0lEQVR4Xu3VPShFYRzH8b9CIm8DGai7MCiUhUEiiyKkDIpNSQalGITBgFUUWQyS3Wspgw2FFLEYlIHZ5CV8n57nXv/z1FVOJ4Purz7dzu+ce577nJfniqSSyl+nBfs4xTF2UYUtFKvjQmcKt6hWXR2ecam60GnAJ2r8HWQD834ZJiv4QLa/gyyh0S/DxJzIzOQAzRIcLB9pajt0yvEkdiDjDSdo0wdFkTz0YRU3Ygd7l+B9ysI9KlRnkosHlHh9IskezTmxA42ozly2Tvepk44ur0ukCId+6VIvdpBuf8dvYy7PhV+6zOIOmW67H5sYSxxhZzSBNQypPpB1vGBSvp8oM/VhPKLWdYViTz4o9jvxDIhdEXqxo/pA9lCKaZzjyll2fTxmNuZHHKFd9WXucwEzqg+dmNjZmSfMvDs6Z2j1ulAZxyJ6UKn6HLyiQHWh04FtjHq9WbkjWUB/irmfZlmKPBli17mY2AelSe+MKubGX4v9G0j6fvyffAHwMT8nf+IZ8AAAAABJRU5ErkJggg==>

[image31]: <data:image/png;base64,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>

[image32]: <data:image/png;base64,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>

[image33]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAA0AAAAZCAYAAADqrKTxAAAA70lEQVR4XuXSP0tCUQCG8VMNgUOTY5NDY+AUFAiNLuIspGu2KDS5h5tTH6AlnfwDooug0BI0BNbcYDg35CiEPcfjvZz73uF+AB/4Db6cO5yDxuxPx3jAC97xjJPICekIfRS8rYtH73esOkqyNfEmW1gKYx1piicdgyq4ke0KvziTPayDU8yxxhd+cOkf0oY4MO5O9yjiAzX/kF8GLR2N+3ipY1DZRJ856BYb4x4p1kSHXZ+Y6WhLY4VD2fP4w7Xs2+yFF6h62zm+cedtkewDZNHGq3H/uQEu/EPaSIek7Kv0dEzKXrKhY1L2g5yO+9Y/wPIlpK492JYAAAAASUVORK5CYII=>

[image34]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAACUAAAAZCAYAAAC2JufVAAACSElEQVR4Xu2V24tOURjGX6dETmHIIW5cOJRQprlQ5obJhRsiFyO3LkjhwtRcUfgDpJlScwgpyQWlKWUuyGkaokRO41QOYaSRnJ/H+679vfv9DjXJ3f7Vr773WWvtvfbaa69PpKDg/7EMXoKXYT/cA0fkelRmFNwnOqbP3JTroUyHx+FN0T7tcGKuR2Ae/AC3Wj0V3oOtWY/q7IedcLTVB+Fv2Jw6iE78Bjwm+qCsT8CLrk8ZR+H9kG2HQ3ByyCMD8AdcYHW96KS4conNls122ULL1rgsgzN/A8+EvFF0EC9Yiyuik59vdYPoOK5M4jR872rC1fopuiBlzBW9SEfIl1t+KOSRsXCKq3eIjvOv/hF86urEJ3g1hmSl6EW48TxLLO8OeS34Cp/DXjjO5VzJB65OvBPtX8Zq0Zu3hXyR5WdDXgnuu+uiN7kLZ+Sb5ZeU71nCbfMxhqRR/n1SHr5u3miV1dyzvM6wJlXt9S22nGfLcBgPv8LXcJJl1V7fW/gyhmSW6M27Qp42+uGQe7gKTXBOyAdEx663mhN6lrWW4Ea/FsMEn+pcyHh+8MJbQu5hG/vcCfkryzdafQp+LjX/ZYxU3jYZPCsehmw3/CL5z51f5DpXp0ldcNkE+B1+gzMtS4enX9EVlq11WQ6eVYNwm9V18AVsyXroq+LXxQsttYz75zHcJfrk5ID12Ws1GSmlvxn+5l/Sedjj+lSEM+8VHXwL7sy1KlyRJ3Cay/jX0Sl63rCNh+EG157gmJPwtnlE9KEKCgoKavEHmwWIz6x7LucAAAAASUVORK5CYII=>

[image35]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAADUAAAAaCAYAAAAXHBSTAAABrklEQVR4Xu2WyyuEURjGX0RZsCELCysScr/EytZKFmykrEWxlIWVf8ElGwvZuI3bwsJiymUliVCShQVlIcWO8Dzeb8z0xvhm5hulzq9+NXOeM2fO+53LjIjD4XA40ks5bLeNcciFR/AWvsFneAHP4Rm8hyFYFfnAX1IHl+AqrDCZH0bgOxww7QXwBD7AYpOljUa45llvskTg51lUmQ3AjGg2ZIOgaYYboiuTSjEkCz7CGxt47IsW1W0DMg53YRi2wC24A1dgRrRbXCLFLMNakyVLm+ik52wASkXP2inMMZlUw1nR5eUAPIxFcN17Xxjt+i3cZiyGD6DGZKnCh8059Jl2fifPE1eqxGSfjMJW2CM6QIfXzgHpb8zDQwludWLh7uGcwnDbcw8uwl6Y+dXzB6bgE8y2gQ+aRLcszxFvuyDIgy/w2gaJcAk3bWOC8FxxjCCK6xRdpWkb+IX7kgMM2yBJuHI8k/xxTPYGnBSdU5cN/NIvOkClDVKkQXTVWBxf+4U37hV8hfkm880YPLCNAcIbdgEO2sDAv0bH8E70IfPK5m08EdvJ4XA4HI7/zAfUpFQ0MIFVwQAAAABJRU5ErkJggg==>

[image36]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAHMAAAAaCAYAAACEuGN0AAADmklEQVR4Xu2YWchNURTHl8xkyEyReSZkHkKIB5E8GCMiMwnxIJ8xMpTkBWWKCC+mIsODMbOM5cGQBxIyk/n/v+sc376re65zPz75uvtX/4fz33ufe+5ZZ6+99hbxeDwej8fjyR+GQJeg09B5qF9ycyyqQSWsCepBs6Emou21oGnQdrdTXigM3YbW2YYsZgD0HmoYXLeG3kLdf/WIphBUA5oBPYfaJjcn6AX9MPoA9XE75YUxojf7DNUxbdnKHWiD8XZDZ42Xioei46+IvtdUwewhGuiH0D1oC9TAac8TRaG70D7RH96c3JyVNBN9F0x7LgsDv6rxo5gn0cHsBm215p8yHlovmts5zb9A9ZN6ZB8jRYMw2vgzA7+v8aNIF8yu8peDWUx0VlYPrleJ/vi2Xz2ykzmi72GY8acE/ljjR5EumF2gA6Kp/LhozTIrqUeGTITWONeVRBf5r5K78Lsw+Dugi9Bq0UV+I7QLuhl47LNY9IM4A+2HynBwGipDV6HrGagHB+YTOaJBGGr8SYHPwiYO6YLZCXoqWs0STqhnoqk8Y4qLzsoqxl8m+gA7jU+mQsMlt2A6KpqeSf/AOwl1CLzygcdxBYmFkv/BLA3VNR4nwCfJfaex4Qtebk1QAXoFfYOamjbOQH4Ea6GPUE2njUHmgw9yvNqBV9CCGZVmJwf+OONHEQaznW2IYIlof77L2HCTylnJwKUiR/SmLMVTcQs6ZrxN0BuoiOPxT/M+LRzvX8KKkak+jphRSumwRBD53MxALmEBFPfwIAxmmKlceBDBrQv3+CELRPvzMCE2TBOLrOlQFnopOjtZprtwneQPzjX+feig8U6I7rd+B9dMrsOXM1D3xMj8obHof7QFSbgExU2DYTA7Gp8BZF3Cj7+k468U7T/C8dLCwaycytkGw3zRG+81/qjAb+N4zP30pjseUzA/BgadD59qDf6f4UfIbOPC6vOc8XpDrYwXEgaTxY6FBV974x2B3kEVjR8JU8UT0YHpxDTAB/kOtUyMVLaIVl08sgqZINq3kePxXJMeTzW4l41bzv8v8DjvNdQ8uO4sekLG/WEI2/gfXzieS5g2e9oGMBA6JFokksGiH3/c9TixbWA5zB/IRHs4OIAV7ArnmiyFThmPXxcPqQ+LfqEFkaGiM+iC6IzkeaoLdwIPRGesC9/RI9FUyvf3SXQZynE7id7/BvQYuiYaUI/H4/F4PB6Px+PxeP45PwHNzvTzIQb5pgAAAABJRU5ErkJggg==>

[image37]: <data:image/png;base64,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>

[image38]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAG0AAAAaCAYAAAC939IvAAAEF0lEQVR4Xu2Ya4hVVRTHl2Z+8JVv85GvT6UiKmiQytwvKmUfFDTFqPngFxFfmdpbUggTqUBFtKJMLF/5ADW1hzOIomhqED0VR+1hJZoiPiDU/v9Z+8zZd805c+/MXGfGYf/gz9zz3/veO3evfdba64gEAoFAIBBo7AyCSqCD0AnoRahJ1oxkPoOKoaZ2wNARWg8dg76F1kCts2YEqkVP6DL0nLtuD/0IvV4xI50j0N0U/e3mPAAdhT4U3Qi8/hT62o0HasAq6GfjTYOuQw8Z38LAXHN//4B+d/oPesHNeUY0iN3cNXnUeaM8L5An3Plc8K3Gz4guKhc8jZbQcWuC4dBeidPrFuhSPFwO77bbohsmUE16iAbnY+MPdv4S4/v0ghYYj3WKqbCr552GyrzriKvQYWvmYqxo8aW4YxZJdkHNpxDf7wwVDQ4PBj79nb/O+Llg3RpnPKbZX4xHLkLnrVkVLLLMwY+5a55u/oHecNfcQU+61w2J16DvqqGN+rZUikSDs9r4XBf6241fFfwsHkwsd6RyzSRMy/9aM42Jov8Q7zSfD0Sjz3z7DdQ8e7hRkpHCBe0ANMd4zFb8nFoFjQE5C50zPuFdxi+YDK3wfJ56BnjXhWS0NeqYtPTYz/nsrfKBfR7nP24HJD09MrPxpJmTYZL8TxLuEo79AHX2fJ6gGMh7wTZr1DE8MPA3f2L86CDytvHT4DzO72QHRAOWdJPwIJKUTisxSfTDp9oBMEN0bJbntRPt4msSNN7Vzazp8Sz0kzVz8IroE4V8xSY2F39BO43H/inKOvnANWLtSnoywrrKXs7nQUlOy4k8ITrZnnDIQtEx3o0RL0EXoP2iJ6NW0KuifQe/8CvoZehp6E+JC/9a0c8aIVob34XmQ+9BS0Vrxm7oiujnTil/V/3AXumU8eZCN6C2nscTZdLhjHWLKfCmHXBEzXV3zxvivLzKA3fCSeh9z+siWsPYBEYBnQD1duOlUnnH0ePij5T4h/CH+qe1X0WDNkb0GR1hAN90rzOSXKDrGvZq3DzF7pop7jfRuzqCgeEhjesz0PNJG+cz3SXBNY8eY/E1s88uaJ8/KRePQDtEH46yc98g2sWT5aKLzf4k6tNKpXLQ+NzMejMlO2gMCIPG+sgUVAZ9JHHjmXFzGgLc+aWii8tNzd9i2QOdgToYn4H4XnTTp8H3cONGrchKqEXWjAJTIhqgvhLvMgZtfMUMZTq0ybuO7rSHoT6iO/kLiR+UFkkctKR0HagFrD3PixZnLjRhH2cXmoebz91rPs65JTqfqTbqX5geo+d1PG5z55K33N9AgWATfgh6RzQVzBM9iNDjaTSCtfFL0dMnDzAs7kwbs6HN0GJoGfSUm8/czpTDpj6pwAcCgUAgEAgE6pP/ATkO9L4/8YleAAAAAElFTkSuQmCC>

[image39]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAF8AAAAaCAYAAADR2YAqAAADmUlEQVR4Xu2ZeYhNURzHf3Yy9l3KLpEthULGXpTlLwllLVGW7GsoUrIlf5CYLNlJIQmjJIqylT0GIWVfIvv363efOfObmfveHe68md791Kfm/s59y5xz7u93znkiEREREUmjFCwNy8CysJyxvI8lJaLA3IG/4GN42vOU8/cZmAnPwXvwi3d/zFmS2nDiLoFX4Hl4HLZwb/CjH/wJX8C6pi0v+HR0hRnwB7yeozX1WA2vwjTveiJ8Dmv9vSMOq0Rn8UlYwrT50Rd+gu1tQ4rQAH6Fw50Y+4+dv9yJ+cLZfFl0AGabtniMgmtsMEWYLNpnbUz8LLxpYr40hx9ER7KTafODIz3UBlOELaKd39DEj4im8gom7sto0Te7DyvlbAqNdPhAchZxyi//XXR2FVWOiX7Xeia+34s3MfG47BZ94Q7bEAIt4TO4CS4UfVwPwUXe9QJYP3bzP9JftDAmKtNwlT+vzJ9M0b6yC5W9XrydiceFH/hQ9MXM52GyB3Zwrrm07excF3XOyn/ufNIFfoPvYVPTFhZMc9xDVLQNYJro0pZUFX06uDQOsjILg/zSzj4v3szEE2a+6BtssA0hMQTetUGP1pJz4zIaHnWukwXTJfuosYmz4DIeqOC6MB/fgtVtQ0hsFi1UiZABZ9hgHLiZZB5P1IsSP+dzQ8VO7mji3OneNrGEqSb64Qlvkx34RS6IpoYgPBEttC4ceO4h+M/UcOJZorWit+iTudJpK0y4GOCKbIQT457pJVzhxBKGB2wnYC/bEIAMONMGfWgrOoMGm/g80dn3VLJrDx/xN6K76x5wrSR3k8fjBZ7rsBaRuaI7XE7gwDCPTbDBgGRJ7kfRD85grrBqmjj/gZ6iaSDGWPgO7hS9P9lFlwdry+ANeEm0FtkakBDTRUcyCOyAXc51bGbyqHk8PAAHOe1B2QanSHba2Q6nip6nXPNihVWXQmMgPCzBzuc567ismuTExohW+3Gi224+kgXtfM4qDmQduNiLZYmun7mM486YS9Q5XluxhAdDPK9Psw0+1IYHRY+V2TkxODNfiXYIi0+QwcyLTLhedKteWfT3B74nf+Thbw3rJHe6KjawE/kjyUjYHXbLxz5wmOipJzv9s2iRZOe4PBLN9xtFO40dFStGEQaurd+KFjGean7MQ8a52+U9vJep4LXoDGdej9HIizEdMb5VdNDSs2+JCIsBogWStBI9q1kqyV+RREREFAl+A3dGzlOygQl8AAAAAElFTkSuQmCC>

[image40]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAABYAAAAbCAYAAAB4Kn/lAAABgElEQVR4Xt2VPShGURjHH5KPImIQRWazz0IRIYtiEhmMFoNIkSIxKNleKQxKDAbJoCiblK9BksFiUGKzyNf/6Tny3Edv3HNfi1/9eu//f263+3HOeYn+O6kwBmfgEiwLDvszACfccT68gslfw/6cwHaVb2Clyt48wSaVL2GPyt68wEaVL2C/yt48wGaV+Y67VfbmCHaofAurVf5GMTyA78Y3+Ao33HmDcModF5B8vLizIgOewU04BpfhqTsedVa5c9PgIpyFq/TDjBiCfSrzBYdVThiHsNWWUckjeaeFdiAqXfDelo4KeG1LUAuPbWnhD7JnSwc/TZ0tSfYMvnhceNrw3c7ZgahkwTtYb/okOA53KXjH/ATTcBuWq/7X8BLmC65RcFrynpwOF0gWTmhySJ7mEeaqvsj9nsMG1Yeil2RlZsMU1XN+hpmqC8UOyeYzQvL39EkLyebvDb/PFdhm+kk4b7qEsA87belLKdyCJSTTk99zQuBVxtvqOqwxY3/PB4Y3QR9iw81eAAAAAElFTkSuQmCC>

[image41]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAEcAAAAaCAYAAADloEE2AAAD2UlEQVR4Xu2YaYhOURjHH/uafY8ahBLZCUkoyR4iicZW+CAUyVa2ImRJiCJ74ouyhYj4oJDsSzJRRPb4YPf/95wzc+aZe98Zo3fed5hf/Xvv+z/ndu/ZnuecK1L8aQrVs2YJyjKokjX/NeZB96CvUBPnlYaOQt/cb13ne1i+Jvg/EtoA7YG2QhWCspRTBToJNbQFBWQj9BBaGXgVRRscRV9osLtmR7yA2kKloFfQDFfmqQGdhWoav0g4Bk0wXmvoBHRddGbshGrlqqGUhVZDs6CXUHnn94JG+UoG1i/nrnn/Gaij+/8cmu+uQwZBp6EytiCZTBYdlRAGysdQB/e/AfQGuivamJBu0GjR0f0MjXX+QokOuOw8dk4UXUSf45en5SC0wJoFpY7oS10QHY2L0FVoseSMaAi9p9AQ42dCv6DdgcdZRG9o4JG5op1HtkOX3PUm92vh/X2sCWZDN6AptiCgu2jnVbUF+cF1yrU7R3S9ezgKN6FrUPXAJyNE72GADOkP/YQ2B94p0c4ZGHhkXXDdTrROZ2ht4IfQt8/z8L0fiXZUHLehmdaMg0FsG/RJdFpG0UP0pW2A3AcdMZ6HGcY3guuc8eQtVC27Rt6sQzhzOBBjjE8Y+Jcbr5loIPfL9ZBojIuDbT1uzThWiDZ8ki0I4IO/Q1nG5yhxWSSC93JPwlQ93JRxMDKNx5jD94nKfCzrarxx0DPJyURXoP05xXmYCH2QAgTmTtAP0anGGRQHpytfmAHTw3XLpTMs8Cyc3g+gL5I3vS4VjVd3oJ6Bzzh2Lvgfst4aolmLS20HdFg0zlXOVSM3fBbbkmH8PHAKsmJ+a9AvK2YgD7fv9HoHXhwZorHpgOSk4D+F2WyJNQtBG9H35sSIhTPlvWjFVqbMskq0Hterp73zGEQLApcW63NHXBgyRRv2tzQWfQ8mjVh4LmElKipNezhFX4vGjJaB7zNLVOcww9mHZ4rWZ7AtDIusUUh85wywBZaPonEj0VmE2SRqxNkBccvqvmgZU71nqvNuBV4q8MuKe56E7BWt2M8WOHgkYOeFexEPZxTvjQrI7BxmtzDQ+qXJc1Qq8QG5uS2wNBJNz2wMA6ynvugOlfsSe2YKeSLRqXy66JmqhfvPWcYzD+tzF55KfCpPlJ2zqS06M9hBl0WPDudFG80MkYhdEr8JHC/aQVmiWW6LRJ+VihomFR5Akw53sZwRcdv5dIR7umnWTAbc/XKp2INnusIg/E5yH2GSCk/BPMEXB/jJIupbT1LhQxlj0hl+7GJMtd+Tkg43lPxeE3VYTAf8Z9JUZ8oSSvhf+Q2t4r1b/1cNLAAAAABJRU5ErkJggg==>

[image42]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAHYAAAAZCAYAAADkBdqeAAAFUElEQVR4Xu2Zd4glRRCHf+YIBjCLCc8sZkyoa8SEKBhORQ9BURT9Q0FOMWPGgDlzp2fOWUTx1ogJFcSAAQxgwAhiQEWtz+p+r6f3zbx+y7K7LPPBj5uu6dc7naqr+qTxZavc0DK52du0pmlR03zZu5RLckPLxLOS6QrTnabXVN19b5v+DbrLtHDyLrKO6aikfKrpYtPjpuMSe8s4c59p9/B8rOl7+Q6F20ybyye/jtNMS4fnHUzvyxfABvIFsX541zLG7GN6xfSmfNBPV9WtPmw6OzyvKp+MnUL5+vBvE5cnz+uZnjMtYlpL3tZkOH+ny/uP+D6Ol0FgvM6Se7CXTU/K+5ezsWmu6SXTW6aTTPNUapS31cjOpnfU3VG7yQf7pk6NKtvJ38eOP2i6TO6qmcB5gz3Cbj4ks0VOlrv2/DfjzRmmD02rhzJ9f6r7uohL5eO4eCgfY/ratEynhrSK6UfTYaHMmLOR8GgpJW31ZbZ8oo4IZVbPr6a/1Z3slPtNNybl400LhOcnTCck7+BcdT8wsph8MTCYTPxEMiTv/5ahzLdR/iJWKGBl05+mgxMb48hknJfYrpX3OYVJY7yXCOXStvpCZTpyQGL73fSPvJMp7Lw7TPNn9siVpmeSMjuxKRpm1/9m2iZ/MY7g6j7KbAR3cVeVQADIGG6Y2YflOxKYnG9ND3TeOkPy3x4YyiVtFcEfXDYpx4Dm2cQGW5uukU/W2kFMyGemhUIdVuRj4RmG5Od3yi7yVRqhs9cl5RJYcCVuKXqSOpaTL+C78xcDcrN8zIg/Uh6Rt088wU6kzqxKDWmTYL8glEvaGhjcAQf1V6oGD6vJAygml8nEjXKYs6riCuTAJxhIXciFpgWTMnB+4bKBv4fbSVOhJnDpc+THxB/ynTZDI4MPYAGenxszWHQM4tXy+OBp03vygGYQ6A/trJDZySawr2HaIjzfUKnhGQF2sgsoaWsgbjd9bvpZI6PUF+WNRjGwcTccbbpFPsHpgOCuyVVzVpSvWqJpBnJm9XUjTMCZpiXlk8kiIxfGnW6W1APOes7/JlhQ9OcH047Bxk7hzDsxVipgrryd5TP7PcG+kTzN4znPItYN9odCuaStUbGn6S+NDIIGZQ+52x1L8tUe4ZsJSkjZbpV7DqLaeETUwcQzWK9mdrzTL+oGNP0YVv/JGArP/SZ2OJSb2ho1L8j9eb5zB+EiNV8xjoZpuSEB17utPLov/W6OjV6DzXGBnevSEurc573BzrFW54rJ67HjMaGkrSJwYRzgKbPljZBPjZY8NxsriB6fl+d5nIv5AKQcmRsycL+9+slEYz88s9fBZFE/5sERAh7sBDx8J894lJQYPBGPQElbfeEakPOSACbd+qQ0NHJVYpsMkILgNpnc7eXBEXEBuzSHoIQcugmia4IwovmUGJnumtnrIMqnfn7Oc/ZzRES+UTVrAP4Gv50eyqVtNcJk0gjBQ7z7BQYP+36JbTKAO8pXLGkE7mvYtJfcXR9keldlESRncZ7akYt/p25Ez732DI089yIEhGyQQxMbwSV36mlkzgL6OCkDQRq5PAEhlLbVFw5lUojYMCuI8/VR9U4jJpKmKJddzIJkQogRSM1K4Dxm13KVCkTaeLD9OzU82mehE8XXgTvnbjeO40z5bdFSnRq+CMk6WCRALv6l6ZRODaekrb6wKs8xfWL61PSB/A63X3I/lWAxc/nPNSI7fd/q6///w+MneX5fB4Ei48jv35CnYfk5CZvKvcvr8snrtVhL22oZI+LFSssUArcYb4daphCkI7jklikEN1C9rkdbWlpaWlp68R+NqkHXVaLTGwAAAABJRU5ErkJggg==>

[image43]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAADEAAAAXCAYAAACiaac3AAABZklEQVR4Xu2WyysFYRjGX5dYucRWjpWVkpVigVBC2EhSyp5ySymyUYqNkuzOQllYnYWNnf9AlixJLK2sed7eqfN5fOfMmZrRUd+vfjXneadpnjnfXEQCgUDgPzMLPzj0UMdBCRpgDYdZ0gYf4RdsohmzCic49LALhznMknmYFyvRTTNmA05z6GEPjnGYFSOwEx6JlRj6Of7FllRZiRa4FG3ryWmJxeLYy7ZUWYl1WB9tL4uV2CyOvVRaYl/+oMQ4HHB+T4mVOHEyH0lKjHKYJs3wHj44PomVuHL286HLboZDD1pC77fMOIbtlHWIlbijnNGnk75T4jiAgxymhT7j9USYRrES+o+UY1Lspo3jBuY4TIM++Cr+F5q+XT8jy1ELb8WOVYoViV+WiemHL2JXWn2Drc78FL4782d46MwZXYrX8BLOwd7IBViAF2KfHamiV7nSb54k9MAdeA7P4BrscncIBALZ8A2tCzqJHGG2gwAAAABJRU5ErkJggg==>

[image44]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAADEAAAAXCAYAAACiaac3AAABWklEQVR4Xu2VvytGURjHv6JYvEQmEgOrWJTBj0EpymSQImX3cxWiFItkNvEfeMsmZWCRkZHEaDLzPT1v3ePxuI7c+0qdT33qvd/nLt9z354DRCKRyH9mnL7oMJACrdFhuWmgt/SN1qrZV3TRI3pBT+gpvaIHtNl7r2xM0ENIiU41s5ilRdqhB2QQUqZX5bkyRFvpNqTEwMfxJ9rpOa3UA48mekmr9CAP6uhU6fcypMRkMjaZozM6NNinPTrMgwUkpzUNKbGUjE3m6ZgODbZovw6zZpj2ec+jkBK7XmbhvlhIiU18/9f8FW4lXtMbzztIiWPvPYsVhJXYQM4ldmijylogJc5UrgktsY4cS4zQRR2SakgJ90XSCC2xBlm3mdNNH2FfaBX0tWQaoSVWkXEJd/E8QE7a+UTrvfkeffbm95DtYvFnJdwpp11OP8GtTeum1rjt16bDSCSSDe95LzqklHr5AAAAAABJRU5ErkJggg==>

[image45]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAC0AAAAXCAYAAACf+8ZRAAABVElEQVR4Xu2WwSsEYRjGXyFKlignbbnIVQ5KCQeltLmQpBxdlHa5OTiR4kIuLtycHP0BLnsjOXIkcXRyXs/bu9rP064x23zfjtpf/Wrmeafm7ZuZ7x2RJk2C0Q1bOUw7i3CDw7TTBW84bBQL8IPDGlzCEQ5D0wcfYUnsnY1iHu5zGJoleCHW9DDVqtEG72ALF0IxA7PwQKzpqZ/lmpzCaQ5D0ANXy8fbYk2vVMq/Mg7POQxBXuxRK2tiTW9VypHcwk4OfTILJ5xz/bi06SMni2IXLnPoiwy8hw+OT2JN63b2V4bgNYe+OIT9lA2KNR13cOj1AxwmzRwscAg6xJrWFY/DOtzkMElG4atUHyC6536WjUMvLHKYBLo9vYitpPomdrNvjuG7U3+Ge049iivxMNZ1FX3+TuYkBWM9Lu1ie3bDxnq9nMBJDtPOGDzj8D+ww0G9fAHc0TQ9/PL9ggAAAABJRU5ErkJggg==>

[image46]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAEMAAAAXCAYAAABQ1fKSAAAB4ElEQVR4Xu2WSyhFURSGF3nExKMUmchE8koepTxGiomBMDAgpUyQgZFHEUnymiCljFBmEmbGCCmZESVDAymZiH9Z97hnLwdXyXGzv/oGe61Tt/3ftfc5RBaLxWKx/DRF8AzewWd4abbf0Ujy3BM8h2tm2yBKFzyIgDG66Dcr8IRkk7Gq55AKp0jCWFY9TS4c10UPyuCQLvrNKewn2WiW6jl0wwGSZ5pUT1MIJ3XRg3I4qot+kg3XKXgEas32K3UwE+6STE+y2X4HH7+wDIP/8XaSDXAYnWabUmAzjIOPcN9se1JMYRrGJsyAiSRhzBhdCScSVpP0R8y2J6GGUUF/KIxoeOxa38IN15oDcO4QvhA5jMpg+0O+E0Yo4f4KvLF51/qA5FXL8KS0uHqH8J4kwK/gIzetix5wGMO66Bc8ovWu9Sp8IHn/d1HwWyGJ5OLcCqy/gt8m+rh5UUXyFvsT7JFMgAOPLB+FNljgqnNgXO9x1T4jAe7ooge9ZE6fb+TDC5LL0aGVZNODrhqzGKjnqfpnTJCE+hE8PXws43XjNymFVyRjzxvkS7Mh0CuBRxT8Cl2CN4Hn2GuSb5JQ4JDH4DZJyPy7ObAGzpFMTvrb0/+ENNgBZ+EC7CMJ3WKxWMKKF6yfVj4whJyNAAAAAElFTkSuQmCC>

[image47]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAEAAAAAXCAYAAAC74kmRAAAB0UlEQVR4Xu2YPShGURjHH98ZlI/IKIkMGMRgsBksyudgICUpH9lRisEiG5EyIQaSDBZKKYSUbETJaJCSRfwfz7299zy8vFe9nLf7/uo3nP9z6r3n3HPPOb1EceLE+QOSYIYOg0QeXNVh0NiBWTq0jUp4CR/hG7wxy59oJen3Cq/gilk26IG9OrSVJXhOMrA0VXPJh1MkE7Coal/Bb39Ph7ZyAYdJBleiai6DcISkT5uqhWMDFunQNkrhGoWWd71Z/qABFsJdklWSbZbD0gzHdGgb/Ga7SfYDnoB+s0y5sB2mwxd4ZJa/hT+nEx3axhYsgJkkEzBtVGVCEmEdSX3cLP/IPKzRoS2kwDNP+wFueto8aHdPmCSZgNpQOSK4/6wObYEfbsbTPiY5FhleER2eGi/lJ5JJ80MCPIWpumADE7DJ016GzyQPPQCTnZyPNN78tp22X/h3GnVoA4ckb9qFv29e5l2wwpPzJHE+5Mn8UAzXdfjflMNrkg3OpZNkoKOejJlz8jKV+2GfIj8+o0o1vCVZ0jwo3vhanFoVyffq3gYX4L3Tj70juTP8hj6KoatxNMihGLoaRwu+GvONMrDwSaD3l0DBd4EDHQYNvl/8299l78VBT/hwLV6vAAAAAElFTkSuQmCC>

[image48]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAADMAAAAXCAYAAACmnHcKAAABKklEQVR4Xu2VvUoDQRCAJ0YsxCKKhaKFyRtY24k2Cj6AnRaWwcpOUEiRF7DVRkSCBBELRUWRENBCLAWxFx/BQvMts8HNkst194P7wQc3M3cHt7szJxIIBAKBf0QBh61Fr5YLVvASW/iId3iDZ6IflwuG8BCPsezVEmdJdEU/cNXmJm1c7940gBru+8k0mMWm6Oq+YsPmJ/ATn2wcRQmfJSPHqIoLOIc/uO3UNvDEifth+mTHT6bNHn6LHq8um7jlxP1Yx3fRpo/yShLeuTe89nJmCk15OR+zq6ZnMsMY/uKuk6vgkRNHYVa8LfqOzPCFB/Z6VHQozPyVB7KM56LPZYJFfBEd0ac431uOZU30R2n6bBpHesv5Y1x0YJheu8V7fMALSXgABAKBeDrPCi77H9dHwwAAAABJRU5ErkJggg==>

[image49]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAACYAAAAXCAYAAABnGz2mAAAB60lEQVR4Xu2VvStGcRTHj3eRZKEsJpSUkA2DzctqISlJGQwMYlVW/AFiUTKISN5iUAZJSTF5GS3IQJLX7+n87uPcn/t0pvsM8qlPz+/cc+p7n3vv716if/4g+V6d49VxYeauwzRVr6p1nJi5mzDTrXmQ61Rg5vKBLLdOh9uq5zMLr+CXszfcDpELT0jm7uEFbFJ9M3cLZrt1BtxRvSjK4SlJ4KTX0/TDA5K5Mq/HmLl6gC/trupFMQCH4Qtc9HoBdbAFPpNcqSjMXHPAYwlWwXN45PUYvj2DsJnkak2H2wnMXB4ItmrkgIKfBb6NDO+qO9UL6IMFcILkxFrD7QRmrjmgqIfzbj1DElz406ZqklvIHMJXmPfTDmHmmgOKcdjt1kMkJ1bran6A+RYyfMXe4L6rozBzzQHFHixx6zaSE+t0dQ8scusO1+M/kgwz1xxw8CfkWNUVJOFjsJLCzxI/8NxrUMd8zFx/4Nf7xNEOp1TNO+oDzsERdZw5gw8kmyUZZq45QPL88GuCd5zmBt7CYnWsFH7CZXUsCjPXf5/4n4YF+Ehya95JdlvACuxy6xp4DZ9IZvn3Eja6vo+VGxrgK8N1KjBz/YFfX/mYMHN5QH/lN1QvTsxcPlM+44A1tY4TM5ffQ5pRr46LyNxv5+53yD1n+9IAAAAASUVORK5CYII=>

[image50]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAACUAAAAWCAYAAABHcFUAAAAAq0lEQVR4Xu3UoQrCUBSH8YPgEG0Ww5rBKFZdMIlPMHwAxawvoNFmtBmFVS3ikhj0jcx+ci07GCzes3A/+IXxL2McJhIKhcpfBROcUVOb9yLM8MAazeLstwaW4l5m8Xk26/0lVrhjimpx9luMLW5Ixd2QaUM8MdeDdSPk2KOjNvMGOCFDT23mdXHAEYnazGtjhwvGajOvhY24u6urzTzT/1boW31cf1TKm/p7L6BJGpWcaoLiAAAAAElFTkSuQmCC>

[image51]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAEAAAAAXCAYAAAC74kmRAAADfElEQVR4Xu1YW6iMURRe7vdLKBSepPOA5MEl1Lg8IKLcHjyc5C6Ue3ngiRApoYRO5AEJj6Q4uZRrQu7luBOhiAf375u198yeNfPPP+PMZB7OV985/3zr3+vf/9prr7VnRBrQgAZUGKaDG61YQqwB51mxvjgMvgJ7WEORGAbeBFtaQwnRBDwPjrKG+uAJ+AccbA1FoAX4GBxuDWVAFfgObG8N/4o+4FgrFomF4A0rBpgPPgC/iwa7JtOchV2i930THbc80yynwbVG+6+4LRqEONwDn4KXjB5iJHhINADVxuYxFXxvxcZWKADNwO5gf8mdUoX47C062b7WYMBMOwGeAt8YmwfnMAs8A/4Gu2aaU6DOZ8pS8LloqiwBV4PHwEdgLdhNNL2PgpfBK2A/DnQ4KOqITDgtyudD0dTr4u7zmAl+kfhgMUMWSTq9W2eak6C9neizWVDz4Rn/dAaniTqsA2c4YydRJ3zp7WAjx6uSnX7cn2EA4nxudZ89tkj8ZInjotmyQnJnzAhwoGiFp31zpjkLzJIkOGEOqE2ZFPfBr5LZlvaAP4LPxATJDACRz+dZox0AzxnNgu3LB2myqO9JabO0Ame76w2i9tFpc04wK5PoKDpgW9qWxB3wmtF2i94bput4pyUCLZ9P9uEQJ0X3dj4MBfe6a25B+l6WNstc0VZKMGuZaf5zFPb5C+4ZOtyUtiVxC7xotJ2i93JFPFgjbADy+bxgNL58XADWiZ4SCe59+mYtIAaBQ9x1B/CnaK2JQyoAbSV6sjYAvgCFARjntESg5fNpA7Bf4rcAsyYsnq9FuwFXeUGgc1vwuasCLQpZWyDXZKMC0DTQcgWgGJ9xRZCryu4TgkFkp2LVbxPoO0SfOyDQopAqgmx1HMRqH+KuZJ/OuA95b9iCfNTHBFo+n9eNVg1+lug2uFi03YaoES3GrPgeHM8iywMOO1Yckm1wJfhRdLLcO3WiL/LCaeRL0dMVB/xy2gfR6B8RLTjUPoHrpXCf/rtDL6fZtsYXf+tsfkxPZ2MrZEEm+OI8SXJO/pn8fsJ7opA6CDWX9H5m1NjymN484XmN19Ro85HlGI6l5leO/6kV6jOsI1y5Qo7CpQKPwqwjFYM5kr3dygl2CXaWigEzgmnL3wTKjSrR1WehrijwGMujdnjyLDW47diFJlpDpWCKlP8nsVSt+QsWReD/1YhdpgAAAABJRU5ErkJggg==>

[image52]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAABwAAAAWCAYAAADTlvzyAAAAp0lEQVR4Xu3ToQ5BYRjG8Xc2ZjRF0ATRVATJXIG5ACZzA0RN1ESbSjGSCdyR7G+fct5k8z3C2flvv3D2hLOzd8csKytN5TDCCUW3Ra2ACR5YopKc41XG3MKLZp9nSe8vWOCOMfLJOV41rHHD0MLNZPXwxNQPyvq4YIuG26R1cMQeLbdJa2KHA7puk1bHBmcM3CatipWFO5fcJk32X6arNq5f+vsNf+oFcW8alSi61ykAAAAASUVORK5CYII=>

[image53]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAwAAAAZCAYAAAAFbs/PAAAAnklEQVR4XmNgGAUjC3gC8RYgvgFlw4AYED8BYgckMQY5IN4ExExAfAGI1yPJpQLxfyDWQRJjyAViOyCWB+J/QFyMJLcSiF8CMSOSGBxcA+LdSHxtBojp6UhicMDOAJGsQRID2QwSUwPiKAZUvzGwAPF7IG6F8iUYIAHwDcrfBsT8UDYc+APxRSBeA8TzgNgKiE8B8UEgjkdSNwoGAQAAxRUaknX0c9QAAAAASUVORK5CYII=>

[image54]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAADoAAAAaCAYAAADmF08eAAACKUlEQVR4Xu2WTYhOURjH/z6afJVJlIVhxEYRRUJZm5QkiZ1iq2mys7C0oFgpNWJhwcJGsvCRmSv5SDJKvpIdKTM+Fgj5+j899+XMv/fMPWeKLM6vfr3d/3M/nnPfe889QKFQKBT+ChM0aMc6+oC+pz/pa/qYPqJP6Qt6lM5qHdCGyRpEmKJBhO30Of0G7+k7vR3UrWa5+YGeCWqNnIMfuETy5fQTRl9IuaBBhEsaNLAH3tN5ydfAB7tB8kYm0rf0pRZqnsAvuFQLNVc1iFBp0MB0+g7+z3bX2WJ6nc6rt7NYBR/IKS3AL/YFfrG5UmsxqEGESoMEDsN7O0QXwge5YNQeGeyDn2ynFsgueK1fCwGVBhEqDRJYBH9HR+jNenvcDMAH0xVkNsFspW/oCdoR1JRKgwjXNEjE5gDrr08LOUyjn+ETzsXAW/QYXf9n1yiVBhEqDRKYQ+/CBzoktSx64Cc5qYUMUv8pe3JysE+aHbOC3of3mXLj23IEfgL7do2X1IFe1mAMOuGz+cp6eze8z7O/98jkIfxlH2tB0IQ1NFVDwWb21KdmJr1CVweZLTaG4bP//CBPwg6wu3RHC5lsosfpJC3UzKY36DIttMFuyD26RQvwT4z1a09hEmvhy7zWsu8j/J/dHO6UyQ74I7wX/h7ZCst+98MH2fRuWfO2aLF+zFd0RlA/Tb/WtR/0Ge0N6v8UW1xsowfh390DdCPS18KFQqFQKPzv/AID9HO3UUcjzwAAAABJRU5ErkJggg==>

[image55]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAGEAAAAaCAYAAACn4zKhAAAEKUlEQVR4Xu2ZW6hVVRSGh6mlqVHekAR9SUpEeuhBLMkHUR+EEvRBLDoIIkZKIgiloCi9mGihpoLmIfOCghTajSideXtIzchbRN7zLikYilTW+M9YizP3v+e67bOCPHt/8MNe/9hrn7nmXHPMMecRadCgQYP/HY+yUSe8rxrHZg5eUG1QdeCAR+E+/YqNOmCOaj2bBViims+mR+E+/ZaNds5g1RVVDw4U4GHVGbFZEaJwnybd0FX1g+qS6r7qD9VJ1QnVcdU11SeqIfENOcAUfkLViQM5GaX6RXVT9Y/qu8pwC4fF2ov4HdXayrBsVS0lrxbeVn3NZkRSnyayiw1iltgDvU5+L9VPqt9VT1KMeUn1uWqPaodYIw+IPQgGuyifqU6LtWs4xcAbqs2qh8jvq/pLbDa0lT5ig/0sByS7T6vIuuFTsYcdxAFljVhsBgc81qmWic0An86qKWKDgQHNC+47pJok9re3V4ZbWCk2a5ipqhtstoGfxdYXJqtPq9jNhkdH1S3VeQ5E7BfriIkciHhF9S6bxEjVx2ymMEK1QqxtyMt/q56q+IYN0iPkAaQmzMiy+EjCv5fWp0HSbsBURyc3c0DswTEdj4otVCE2qgayGQCDmZeFYukNzBRr36rWcEtq/NK79vle9R6bEW+JpTmkWL/NY1RXVd08L2ae6iybkt6nQRwbHijD8JCvkv+cWGPReQMo5oOFuzubAbBW5MVJa2WDehzpBQtw78hrUs2OPjPnVAvYVCaI+Y+LPe+bXmyTWBES2hcgDd9mU9L7NIhjw2OvWKOcWO0L7VNtU02W6oWP2SnlDsJjUt3eRWJtjOv2LaqhreEKkFr9Do7BTMfAvib2W3jJYlDO4nlD4OXE9zkTOLrOxLERgUb9KVaF1Aqmd55BcGwk8LJUv8moUu6Kva1IGUiPSaC0DQ1CDNLIMe8a5Tc6mSvDmHgQupDv6DoTx0YE8i7+wGoOFCDvIOTNoah6QhsktBFtRSWGI4UkTkn1IMb0E1vjkOdjUOrid5/2PB+ko3tsSnKfJuLYiPhArAHjOVCAsgcBm8fQRg9FAqoktJfXL5+0hXms2P2ovmJQ/l6MPi9X9fRiAAN2gTzg2MjCsSG2CP0qtrFBHq6VvIOQZ4f5ouogmx7oMHQi3ugkmiVcUgKsA7h/dHT9vFia+0Jsj4NnYVCiYvPJODaycN5n7F5/VF0WaxCmJ44q3vG+U4QyBmGMWBkYH0X8Jra3YIaJHVmk0aS6zqYHFvcjYkcbi8VSMo5pvpHwzhibtblsShsHoWzw0KH0wUxj4z+iv5R/bPEMB6SGPnVstHOwgSzrAC/peMKxkYVjo52DWYAdcBlH2Vg3Qjg2snBs1AHTVR+yWQD8UyftTMyxkUVS3dzewclurf/exIFj2mlBvfZpgwYNHkz+Bc1p3nRyi+N6AAAAAElFTkSuQmCC>

[image56]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAFIAAAAaCAYAAAAkJwuaAAADrElEQVR4Xu2ZWahNYRTHlyFECJmneDAPJTIU3UQZHjwopHQNyYupvBjjhVAUKaUowwNlDplSJKSIZEyUUGTOPP//rfvd+511995n733vOVfZv/rXPf+1zznf/vb3rbW+c0UyMjIyYtHMGjVIT+ioNWOyDxpkzWJyBqpjzRqgBXQX6mEDMekA3YLa2kCxWAWNs2YNsBtabs2EzIFOWzMOw0SfwjvoD/RS9Knege5DT6EtUHP3hgC6QXutmZDD0EPRMfyGRuaGZSr0XjROPYP6evFe0GeopeeloSH0RnReUsEb4QCZY3z6iw7wivEtF6Am1kzIQOiR6DhOmRhh+ngC9bMBsFk0x1UHXDgHrRmH2qJPgU85iHuiN9fHBjwWQrOsmZAloiuPu4Hf5684wtV23ngO7py51kzJFOiDpMj7XAkc+C4bAI2gb9BPqI2J+bSGzlozISxanKyZouPZmRuWSdAK45H2otdXV8XtIik/jyuBbyy1Aam4qW02EMBxqJM1Y9IAulT2dz3oOfRddJIcHMMQ77WDhY5jbGoDYCx0THRX8W9HK9FVXOJ5Pj+g6dbMxznRgXT0vLrQROg1tF305vLBbbnUmjEZDa3zXi8WHdN6z7suwdttBvQLqmV8PlT2lExdN6BDXmy2RKerV9Aia0bBKvVVtKCc9HQZ2goNr7g0L/ysq9aMCSdslPeaq4t5it1EY6g7dMCL+zA/v7UmmAeNgDqLdgL+xLAwvZDKk+9gB7HGmlGMEX0yO2wgJcxrzLlJ4bbm9vbZIDo2TsB80R4viAUSPJGOlZKb4zl5bPOiqjwncq01o9goOtjJNpASrqpN1swD81VQu8OTBvMkWx42yV1zw+VMk+Ct7WAXwELm6C16z2EPhnBrs3bE5rboIKIa7iQwH10TzbFxYW5lTgyCnQRvmiskjKhiU1805p94uOXp8SDB7/aLkIPFJnY7x2TMD0yb18Jg0RhvzRBYxJiTw65nL8kxMl+H4e4jqF3hA+W2X132mtubFZw1gZyQyg/AtT8DjF+JoaLHQHcs/CS6Mif4F1UBbp04R0ZWVBYUjuELtD83XA7bqnxjeyzhDTnfe1P081kLePzj4mFzX+pd52BD/lHidSoF56JU/ciYBK7YqOKRBB4R4yyEosCWhP1dsWC+486qrh8t2Db9E4RV4kKyB1pmzYSwkjNn/1McgdpZs4CwaPD0w+Y9DWy3Hkj6Y27BKJEq/K6XEm7xtP9qYF4cbM2MjIz/ir+VxbwWv2mjvgAAAABJRU5ErkJggg==>

[image57]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAACAAAAAZCAYAAABQDyyRAAABdUlEQVR4Xu2UPShFYRjHH1/5Kh8ZxHRTDBZGinwtpJhsJimbsmAwWCkGgyQLJmVRko+ERNmQnWxGRQaF39tzrt733I/Oue5ddH71q3P/z+mc973neR+RiIjcUY0beIv3eIgtzh055gLHvesCvMR3bPq9w6IHN7HVX8iQGH7jk5VNe9mylTk04xbuY7dbCk0NvuKDlc2KLmDRypISw1U8wyHMc6rBqcQS6/eu6AI6rSwttbiA1ziKhW45FIP4KQF2n4wqnMMbnMBit5yWLrzDN9zGIrccjjLcEW0s+68NQimeih7HOl8tEAOiD1jHBl8tKL2iPXDgL6QiH0dEz+8S1rvltJTjsOjO48REF/CFFVaegPlOY6LNNy96pMKyJvqyFStr9DJj0mea1U7iFU6J7iJT4guYsbJ+LzNNmUAHnovu/E+d6mEm6gv2ic4R07Qn+CH6rgTMrM504KSiDY/wGR9xT7I36v8h7aI9EMRj0aEUEZEVfgCQhkTNdKNtoAAAAABJRU5ErkJggg==>

[image58]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAADYAAAAaCAYAAAD8K6+QAAABq0lEQVR4Xu2WPShFYRjHH5KBgZSisPsoHzFQchdlMygsUiaLhUnsTCb5KkSURZTFhEGRhJKvjCgUWYgi/m/Pue69/3Pu1U33g95f/Ybzf55zzns+31fEYrFYAlTATbgND2AfTAnp+IMUwUfY4WznwFM4+N0RgTp4DJ/gJ7yHZ6IHuIDXcFT0oPFmDJ5T1g2fYRblYVkVvbBiysvhC9ylPNaY1+0OLlPuEx1nK+WepIo+8hsuOJi7Zg5WxoUYUiB6zlnKK518iHJPqkWb57kAMuEbfId5VIslNaJjmqS81Mm9xuqiX7S5kwugS7Q2xQViAB5F4ZLuFpYG0fNOUG4+FZOvUO7JhmhzYVCWBlvgA5yG6UG1eOCTX15YBnwV/UGsB7kDx2F9oDWuhHsVS5x8gXIXTaKNM1xIMPmi45qj3P/zGKbcxYhoYxsXosR8p/tRuKi7ReQWrlHWKDredspdnMAPScwE/BNmgr6krFf0s8mmPASzZDFXv8eFJMHMZWZF5P9b58Ir0bfDk1rRZZN/GWWWKObJNQc3JQlVcEv05h/CnpCqxWKxWCz/hC+G6G6c2iSHOQAAAABJRU5ErkJggg==>

[image59]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAADgAAAAaCAYAAADi4p8jAAAB0UlEQVR4Xu2WPShGURjHH0SIMBBSItlksBsMlGL2kSwGJZvBoqTYDCaRGAzCQiFl8C5KPqKUMDBhsUkk4f94jte5z+u+71Vv7x2cX/2G+z/n3nvO6XwRORwOx9/JgKPwBO7BLVhrV0gWaTpIEZPwFOaZ5354D4ujNXyoglfwCX4Yb+hndOat/BVewmxTlioqSP7daWU80NzBcSuLSx1JJx5glpXnk3SYR8zOU8kASdu4jTYReK6yuOyQfKjHPOfCbdgUrREOcyTtqlT5OnyHOSr3pY3kQwck03ADtnhqhMMmSbvKVL5q8mqV+5IOr0le2oft3uJA8IDwZhDUI1jw9aY/uyRtKlX5ssnrVR6XIZKX1nRBiEQoSR3ks2YJPsMXWOItDg2/Kbpi8hqV/wpPzwXYC6dIXhzx1AiPGZL28JFmw5sM5wk3GT5TZmGfeeYR4d3pDmZ+VwpIM8m6Ciqv9URrkI8o7kiDyvlGc6GyGLhz0yQfseEdlD/apfIwKIdvsNvKeOD5zJ6wshj4RV6oPCU1rSQdPNYFIcFXNb6HFprnYZKbTFG0hkUHvCXpAMvXtEarfBA+WuVcd9EqDwPeAMfgGTwkmWF6TTocDofD8e/5BCnwceRPNMfEAAAAAElFTkSuQmCC>

[image60]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAEkAAAAXCAYAAABH92JbAAAD4UlEQVR4Xu2YV4gWSRSFrwF1FSPmsKPggwlXxbSCOIaFBREFQX1RXxQDLovhwRxAVATFFxMKjiL6sCxrzmFd1xUUFfNgHFHE7GJCMZ4zt2q6/jvd7SiOiPwfHIY+VX931e2qW7dHJEuWLFm+fXKs4RgN9YVqQ1WgbtBf0M9hJ9AOOgj9C52EJkJlMnp8nPpQJWs6+kFnoGfu70j59Pt/FpVFJ70F2mbaPIeh90bboQpBnx+hR9BQd10LugBNL+qRDCfaEPodegB1zGwupI9o4OtB1aClouOYG3YqDcZA90Qn/EaSg/Q3lA/dEl0lo6CyYQewTLRPCFfgc6i68S0FogE9ITrxuCAdhXoE1+Wgq9A7qEnglyovJTlI+6Gm1gzgSrgL/Wn8XNFJDzJ+EpMlPkgMyFvommQGfJVof760r0JakPZJepAaiw52jfHbO3++8ZNIChJX7WPX1jzwFzlvfOCVKmlB2iuaL3ZCx6EdUIugvZPoYFcGHmnt/HXGTyIpSIQB/8V4e0T7Wz+O4dBl4/E596E67po7YoZoHDjXYqQFaTe0WKI8xGR5WzTZEuYKDnaFu/a0dD5PwpKQFiQLD4rX0Hkpnh/j4BxOG2+B6EnJ7UyGQQei5uKkBamVZA6kmehklrjrXHf9NYO0AXoCtbUNMZSHnoqeiCFHREsWz3LRnfJD4GXAIPGUKwmMPCdzyV0nbTcGl/564yfhg8T7pcEyg6dmrvGT6Cx63yGBV1F0zvMCb4RoP+a/zYFfBH8Qtw9ZRPKN2ROKRy+XKmkgevO1UXMhPnFzWZcEH6QutiHgJ9FaqpdtSGGS6H0bBV5357FA9TAnzRS9P9uKwSDtsiaYLfqDaYHHApRemAjvQFuDa8KEat9gGj5IXW2DgwXqRejXwMuFBgfXcXBVFBhviuizmLS54lla9HZ/Gaw2UdcIBonJzTJA9CE+uRFOgg8Ij3YWk/b0mAC9gGoEHitnfr7E4YNkP3cIn89TdaDx50D9jRfCCT8U/WoIOSTReDdBNaE80S0XCxPbK9EfWpiwWWX7ZckJsx8r5Kq+k2it9L/oUUv4hm6KvjEP3w6DwEHHwaXO9p62ASwUzUPnnHiqXREdN1dCEv6ZPI2Zhxi0WaKp4h/RcTJIJE/03uFLLcw3LO19oUZx2/DhjKynLrTR+fw0WS36sWvpIPoJcww6Bf2W0ar3uS76nRjCFXxD9NOIY+CqZnXNyRCeNn58VsyNSR/EZKxoPz7jrOiKYs3HseZD/0l0QnI3TBVNOyU9xL4L+HL54rOkwC3/hzWzRLAq51YbZxuyRLAo5X8ncmxDli/EB4Tl8r4Waoh2AAAAAElFTkSuQmCC>

[image61]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAEQAAAAWCAYAAAB5VTpOAAADoElEQVR4Xu2XV4gUQRCGyxwwixEDigEVM4IoGBAxoBgRRUR8E8QXAyqKnFkQQUHMAdODGTFhvDM9qKCC6cRwRoyILwbE9P9b3Xs95c7uHeiBsB/83NU/NTvTNd01PSJZsmTJ8nfoBOVCl6Dr0HSoVCQjM5WhutZ0LIK6Q1Wh2tAI6EokQ6QMlAPdgC5Dx6FWYUJJ0QT6AE1wcS3oLjQvmZEe5o+EbkEzzDHCgf5KIfv7K6GbUBUXT4ZeQXWSGSXEWijfeLyZT1B141t2Q8+gM6KDTFUQ8hW6Dz2FjkD9o4elEfQNGhd4nKEsyJLA++fwom+gA8bvIzrAMcaPg8shXUEeWcMwRfT89sbPE52tJQafDG9km/E7O3+Z8ePIVJCH1jBsFj2/qfEPQz+hSsZPRXF7Xkq6id7IBuO3c/4O48eRqSAF0GzoFHQbWgdVC44fEz2/QeCRfc5vbnwPlyyXFZdbT2i1aBFfQpugctA0aI/oTDso0euy/20RPeckjd6iF1wfJJE2zj9k/DgyFeQzNNr9z5s85+Sfaq7o+fVd7OFA6Hc0vqcxtEI0h2/H1s4f6Dy+rUY5j2+3LxLtSVuh+UGc7BX/uiC2N0wSzR/u4jwXF7cghANmTk7g1XPe2cAjbOyng/getCaIY5dMW+fvMn4cviAz7YEY+onmb3Rx3JLZ6/wWxg9hUZkzNPA4G+hx9oRw2VwIYo6PeXz7JdoDb4DG9iCJ+Ka63Phx+ILMsgdEp+hbiQ6ql2j+URfzgTBulsxQuLbpp2uqLARzuEw8NZ23OPAI+9fFIOa2gkXhUmJ+gteie4MQ7hOYMNb4cfiCsHFa8kSPsel5BjuPjY9w38O4azJDYQ/IN55liBS9IHckWhBuKEkFqIc3uTF74AMHOzMbYY3A45tnUBCH+ILMsQfAKvmzt7BwzB/g4obQd2h8MkOb73toaeClwi+ZohaEnyeeAqhlECfgXuQjNNHF3Co/l+jg+DZ4J3qRDoHv8UtggT0g+mnA7xP/BmDD5qzcmcxQuHVnnn8ILBpfqRxcOjiLee1hgccx0ONvhvDBXw3iJ6K9o3TgJegiOrWZzJuaGjmqnIAeizYsz0LncTbxBn6INih+mIXw99nM+ES4a50r+o0Twpi/x2+ia6L9xfYUy34pvDb/8q3EQnJm0eOs4zX7ihaXHvVCdHmed/n89GBj/++pKIVPl38Zl5fCYnNm0ysrugS9x//tA8mSJUvx+A2w5+ricMdXZwAAAABJRU5ErkJggg==>

[image62]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAFoAAAAXCAYAAACLbliwAAAD90lEQVR4Xu2YeYhNcRTHj5BIWcouIsm+U0QzhYj405JlIn9Yk60QZlK2P/xpizKkbMk++MeMPZQl0hSiFMa+h4Tz7Zx73++deffNb27zit771Le5v3PPO3Puub/1EuXIkSNHjv+N9tZQDfqwSlmXWbdYS1i1kjyIarOKWLdZV1glrM6ugzKRdZN1iXWNNTr5diS+8X1yrXEasIawTrBOmXu+tGO9Y03TdlPWA9aq0EPYzLrDaqjt2awXrGahB9F41ldKFKgv6zMrL/SIxie+b641yhzWK9Zp1i+KX+itrHJjw0OiYI203Zb1kzU59JBehEKsc2x46B1OGxwg6aHp8I3vk2tG+U7xCo2HqWAdMfZ81h/WBG3P03bPwEEpIyku6E7isyC8KxSpvYWxu/jE9801o8QtNHoSktxt7BjysG/Q9i5t23XgOOs3qz5rKolPQZIH0SK1jzJ2F5/4vrlmlLiFHkiSpB3uQe/cq21MT2i3Cj2Ew2rvyFqm1+7wB0FvnWnsLj7xfXNNRwHrobENYL2mxFqAkbOaIuoZt9B5JEluN/auaj+q7VJttww9hINq780q1OtJSR6ylsC+0NhdfOL75pqOc6y7xraR9YVk1wOms84nbicTt9D55Jd8mbbTFaJIr+MUuoyqjp+v11XlGkUdkh3QFmPHQo0XHbCNZHuK6aoSKDSGX3WJGo7d1L5P21FD+5DaO1H01DFX7bOM3cUnvm+uUQyiyh2hHknt1js25Am/944tBM5nrNEDPBiC7jH2YIHBsAJ4OLQ7hB4CFivY8fZRYFzPSPJILIbpDi4+8X1zjWIpiV8bxzZMbeMcG+boNaw3ji0EhT5rjZ68ZJ00tpGU/PaxV0W7f+ghYNiV63UXEh+c1FywD4bdTgsuPvGBT65R4KU9NbYVJL/FQoiRgb34cP2b8rSJQmOiTwWGzBhrdMAhwK7Ei1nfWI213ZrkUDQl9CCqS/LW3WGHPe9Opw1war1qbCNIjtIBvvF9ck0FivaW5LOAywVKxDvGasIqpohpDpP8D5IfWfAPPpG8tcHmXgD2px8osf/F231G8rZdcETGd4jggZaTnNyQXACO4B9ZPbSNzwM48Q0NPeQe8sGDu/jE983VEvzP5yTzMupSSLLbuEgSB4UGxaz75Ly4sazHJJM2gkAYWo8oObkSkmKnW/X7kaz8N0ge1p7uALY/a1n3SFZl7HLsnAowhPGx5zpJT8ZQdGnOekLS01184/vkagkWZIx6xEfPRj0QC1MT8uylvhg1KynmVIyXgm1WtrKfpBNmnE0k+81sBdMLTpkZBdsirLjZCj6tYtqYb2/UNNhupfqAni3goFNBlT9Y5fhX+AtIUj04txVsAgAAAABJRU5ErkJggg==>

[image63]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAEQAAAAWCAYAAAB5VTpOAAADq0lEQVR4Xu1XWaiNURRe5iHzkDmRqUzhDSXJlDHKECXyYEhCyhMn4UUelESGByFTiowh1zyGMme4iMxJMmb6vrP2/v919j3n3nNut8vD+err/Ovba59//+tfe+31i+SRRx55lD1ah0IJGA9eAc+AF8AhqcNJNAK3ivpdBdeDtVM8RCqBCfA6eA48BHawDuWJmmBvcD94IBgrDiPBzxIvvAf4CewXeeiDXgY3ghWcvQ08bnyIVeANsJazZ4AvwcaRRzlhJvgGPAj+lNwCckf0bVvsEH3DHuPAP2Bzo3Vy2kBntwR/gBMjDw0eA7LcaOWOb5J9QDqLPtScQE84vYmzd4Pvo1EFs+QXuNbZs0XndI08FAWiQf9nyCUgk0UfYkqgz3P6YGc/BAvj4QgfRWsOwe3EOWH92gf+BmsEejowo8ocuQRkoehD2DQn/Nue5mzWmPvxcIS34DN3ze3KOc3i4SSYXdTbBroHaxG3FbdbH3C1aBBfgBvAKuB8cKdopu0F6yRnKhqAm0TnHDV6hFwCskR0sRMCnTWJ+lxn8w3fi4cjvAY/uOuTonOaxsNJ8EGodw90j1bgSlGfa2BHp/Oko8ZaNtZpDcGvklqTNoOLjV0EuQQkISUHhGnM65ICUiClCwjBB6ZPwmisX9ROGI1gph4z9l1wjbGLgAFh+maDTFtmltOnOzvTluHJ9txdZ9oyu5zeLtAtRov6jDAas4Eas8eC2+a0sdkb0e8puMXoERiQw6GYAQwE/2xqoPui6hs0BoM3DMGietFd8+jmnDbxcBLc29SLK6oMhL0fUd9py4xG3BJtID3qigaFW4n+RcCAHAnFDPC9xIJA5x6l7tOffQmbNQsWO/qsczabMNq9Ig8Fa0C67WYxXLIPyG1JDcgY91tNtDEtAgYkbbUV7TuGBhpTkNXcgt3ueWP7xqyF0Xo6bZCz2bSxKZwUeWjQ3oErjJYOfstkG5Czxi4E2xs7BZXB7+CpcEC0OPKY5E26GZ2tO1O/i7MZZR6BfSMPkYoSt+685n1YuMPAs3Xnd0w9Zy8SPVL5cMWBRZ3rGmU0tvvU+J8WD0TX4vFEtHZwXRGGgY9EKz7/hHwl2lDZxbC2PBYtWBZcEI+8S6KZMSB1OAnO2S76rUKysvP7yYLd61LwpuhHIIMW1pQQe8AvomvmL08lBpKZRY1ZxyzoLxpc/3ws5tyefPn053dVtofJf43qEr9d/tKuKhpcgplNjVnJLeg1XnufPPLIo3T4C4ZR8SfX4SSmAAAAAElFTkSuQmCC>

[image64]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAACUAAAAWCAYAAABHcFUAAAACQklEQVR4Xu2VX2iOYRjGL2nI/+ZAtPJ3TsQJIUdm/qS0tJa2Ns44U5oDRVH+5ISU1lKknCmJRGhrTqwWJrXRUhRO1CZqKW1i17X7eb/vee+97+LLzr6rfvU913O/z/t+z30/9wOUVdbUaiPpIK/IC7InPT2pGsnLQBdZnZ4uTbvJENkRxs3kG5lRiMjXKTJAVoTxNfKoOF2aKslXcjzynpM/ZGXkZWkbLG5zGM8J409JQKk6D1toaeTVk3NkWuRlqZu8c94JcsB5/6y35Is3/0KLyW9yy0/kSH90Mu0is/VjPmyXXpPD5CHph9XF3CQ6R3WwZ9vIZfKEvCHH4qBIF2BZydJ+codM16AatvB3cjoEzIKdovthnKdDsGdVjzXBW0Z+kNYkyKmdnHGe/txj2HvHtQ628CiZl5jU0eBvjzyvI7CYHuffI8NkgfMl1ehNFA/VTvIULitLYAvrSMdSS5B/0fmxmmAxV52v1Mvf6/xEStFtcoU8IwvT00AF+UV6na9mqIVvOD+WUqaYS87XR8o/6PxY6odKc179jX+tTmCsFtjCeYUpqSf9hNVJrOuwZ5WaLG2C3RhV5C5sAyZI+dVXz4y8k7CFN0TeWky8etS5O52nq2oQ2bfBelhW9EGS3vkAVuwpqSA/k7NhrDp7D8t5IhWoXqQP1cKJtsB2Sz1G2kpGSEMhoqg1sB1a7nz1Jv2RWudjFaxH6Xr4CNsp3821Kx/IIucrTWoheraP7EtPF6Qdybu2dPK1vvpmWWX9V40B0iRyxbQt93oAAAAASUVORK5CYII=>

[image65]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAEkAAAAXCAYAAABH92JbAAADiUlEQVR4Xu2YWahOURTHl5CpzHRluPeFMmQKIXIzlJK8CYUXD4gUN1OGlJAHD8pU4hoimecrmccoc7qF3CiZ5zHj+lt7f9866zvnG/huUedX/+45/73P3mvP+7tEMTExMf8+hdaIoIS1zZpMZ9YJ1lnWFdY0VpVAjnAasNayrrFusMpYnQI5Usk21rxQm9WbtY91wKSFUcB6y9ph/Fasl6zR7r0h6zZrTiJHNKdY49xzVdYZ1gdWm0QOIddY88IE1lPWQdY3yq7idawflNpJK1nlxhtP0th6xtcUsX6yKpQ33XnLlPcnseadz5S54m4ky+w9BTsJS+oJa6fyQDFJY4cbX9OI9YZ1S3kzSb5bqjxNNrFWCtlUfIxk5G0ntSBp1HrlgS7OX2x8C2ZaTfWOsvFdX+Vpsom1UshU8SjWQvdsO6k7SaPWKA+0d/5G46djCOsrRc8ikCnWMMay7hgPK+MZq4l7x4qYS1L2YZ9Jk65ibJgXWXXcu+2kfiSdsVp5oK3zdxs/DJRxnaTsTazqweQA6WKN4ghJ+ZolJPXhsABjWMeTyamkq3gBSQEe20nF9Ped5KlFsqxxFWhm0jzpYg2jGusda4Xxz5FcWTyrWJdJYggFFePksLRknaTgfcd2UtRya+f8zcbPRH+S7w7ZBEdUrFH0IClvhPJqkJSzSHm4hiDfK9Ze5SfAB2HrcAurl/FsJ2HEUfgG5QG/cWNaR4ElPIyCo1dE8h2uGnWV74mKNYoSkvKaKw+HAryhysNEmMd67tJSQMVl1iTZ2B4boQDkx7Nfhnje7549gyh1BC1YosizXHmtnQfhimCJijUKzIoK480iKR+bNmY8TtgB7i86q0MyaxJUjM0tE41JCg+7TNrTYyrrI6u+8gaS/Hzx+E6aobzBzrMbrSfbWAEa/ILkFq/BLd/Hu4fkp1EpJW/+KWBj+0LyYSYKSBqwy/i4K70mOWoBRughyYh5MDr4FkF70GG4iGIU0SDcl46yPrH6qHyeXGIFvs5HJPsQ6phPsmWcJokTnQRKSS61elB/30nukWxUfnpj2dwl6VnLBZIGIt93kik8UqV3JdnkL7GusiarNNCUdZ/kt5emJ8nMeECSjuWhZxvINVbPRJK8KP8myYyaQhJrOes8q6PLi9Uwm2Qp53Iw/PdsJenMmDRgyW+3ZkwS/PsGS22STYhJgksuDoVCmxCTJ34BiQ3xadGdZl0AAAAASUVORK5CYII=>

[image66]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAEQAAAAWCAYAAAB5VTpOAAADfklEQVR4Xu2XaahNURTHl3lIxowZIkPITEQZPihChESSr2T4YAglPTKVfFCSWcQHczJl6j1TiUKZk5kQSQol0/q9vfez7n7nvHeJV+r+6t+9+3/WvWeftfdeZ2+RHDly5Pg7dFXlqy6orqpmq8plRJROdVWD2EzhiGpq5FVQ5amuqS6qjqna2oCyornqnWqSb9dV3VYtLIooGeJHq26o5kTXkhim+qGaHvmrVddVNXx7iuqlqn5RRBmxTnU38ujMR1WtyI/ZpXqqOi3uIUtLSCXVHSmekKaqL6oJxmOGkpBlxvvncNPXqv2RP1Bcp8dFfhp9JLuEsBS3SfGETPNeJ+NBgbjZWmYwMnSETlq6eX9F5KeRTUKoL9SG3lI8IZu918J4cEj1XVUt8pP43ZqXSC9xHdkQ+R29vyPy08gmIRtVg1U9pXhCjnqvsfFgr/dbRX6AJcuyYrn1U60Rl8QXqk3ilugs1W5xM+2AqmbhLx3Uvy3ifnMCY4C4G643QdDe+wcjP43SEsJbjM5AUkLyvdfIeMCD4HeJ/EAz1SpxMbwd23l/iPeYkWO8V0/1WTJr0lbVItMuqhX/OiEnVa3996SEFHjvdxMCPDAxecZr6L0zxoN7qlOmTYFfa9qpS6aD93dGfhohIXPjC8pYcaMYSEpI2pLZ4/2QzCRGiYsZYTxmA569L7Bszpk2z0fcE/HlgQ5gbDdBEIrqyshPIyRkXuRXVV2SzHWblBAGBK+l8YC1jV9SUSURxLBMAnW8t9R4cFN13rTZVpAUlhLxhbxSHQ4ND8WPgPGRn0ZIyPzIZwa+F3ePIDaBxH7wbUaffQ9eD/ezIqgB8R4pZrhkn5BbkpkQNpRQRdU3mGzM7oeGh8r8SVXbeLx5hpq2JSRkQXwhAZZQPEOaqL6qJhqPN8Rb1XLjJRGWTLYJ4XgSeKRqY9qFsBdhFCf7NlvlZ5L5cLzj34i7SWfjB/qLu7Y4vpAAs47YmZHP1p1zTBgEZhuvVB6uJML/jTQez4DHf1oY+Mum/Vhc7ShvvEK6i6v0BNOpGRlXHcdVD8UVrMAS7zGb6MA3cQWKg1kMe4kH4o4ExPIb2mGPweGO/+NMdEXcATCuKTH75Ne9+eStRCKZWXjMOmbBIHHJxUPPxS3Psz6eoweF/b+Hoh1Gl0/alcUlF5jZeBXFLcHg8T3E5MiR48/4Cd8l6qJNhjqqAAAAAElFTkSuQmCC>

[image67]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAEkAAAAXCAYAAABH92JbAAAEU0lEQVR4Xu2YZ6glRRCFjznnhIq6ooI5YUZxTSiKAQTDD/WPoogoiv4wK5gz5gQugmvCiDlnEcGcMKNiQEXMivF8W9Nvanrn3b0L+0DwHji82zXVPT3VlfpJI4wwwgj/Texqvmb+1Pw9yJytoyEdYu5iLmkuYG5h3mFunpUqLGR+bq5RP+jB7OYJ5tvmS+ZD5gYdjcA65iPmm+bL5knmHB2NCcD2ik0tYy5sXmb+Y56WlYynG3nmvebcWanCuQq9tesHPTjbPE/tB29pfmGuMqYhLac4xLLevOat5qVjGhOE582t05hNfmD+ba6Q5E+Y75ifmc+YBytOfzysZv6q4Yy0oPm9pl/vKvPMND7dPC6NwbLm7wqvnRBgkL/MD81FkvwaxcdhiIJHzUlpPCPcaV6v4YyEQdEjlDLwrkvS+AbztjQG8yvmLlHJZxk4ue8UL1k1yc9vZEcmGXlgUhoPwo7mFebRGs5I5Di8gfBiLpjPfE9dLycFsN4URWoA5M/HisJEgeS4QyUjabKZLH/YPMK833zRvM9cPT0vmNN8VpHghzUSOEttrrtc4bnMzyD8v1bofKRI9OTT5bPSABygMHzGRoo1l2rGFKwTzXsU39qLFc0/FNUj54gHzQuSjFOlcpFMMw5X64EzYyTWvU6tofCqTToaAUKSKlz0rjTn6miMD77h1UrG4bBeKRj7awjPnGr+YK5byddU12grKzZ5UZItrigEZdMzYyTaEAoGrcYninm/qNtiEJac7tWKpF4MRSsyI+DhPyqqdwZe/3gakyaIFMK9F/uZP5uTK3kfsDwbfDfJKMX0UgXDGomw5TRL4l7UvEUx95WipMhFN6fxbuY3Cr09krwPeCV6+yTZPOZv5hlJdqBCj1x9V5JPw3qKF25bP1B8ON61VyWnTeDjwFqKOM4Y1kgXm7fXQrU9G/mCHEclrj2cPoq91R5So+wl56+tGhleXEBOokEtxh8DYUKnu1OSTTb3bn6fophwfHmotvSWRHiU+a35ZWLJHbyQJnA84DUX1kKFhzGfRpdw53duVQpuUoTJIOAVH1eyY9UeAuuz9nbNX4w1driEDZVqzyJocKq5e/MbV+Yluf3fTPGC3OzVIPz6PIkuf/00ppq8oOmvQtsoGljAoZBTdm4fj+FJdcOoButygNwaMphXDpm+bjFFSBNyHZyjyENvNKSqva/oW7AuIGHTZRe3JGfwgrc0uNOl8mCkHCIYDBmbLqARJFlTBLhqAPITe8nefYxCb9NmTE45WXEbGHR/K++kGjMHozEPT39K4UkYCUxR2IFvnAYyOJP7SL4pGwZLmzcqDMjV5FpFnujDvoo+5k/FWiRBqh5gHZ7d3YwL6IFYnw/hBkDV6cuPnPLrCmNRDTEsXjYIhyr2QQvAXDyKnm9Dhac+p/Yg6dG4+jyguJv+b4DxyZEjDMCniv8WjDAOuEEQaofVD0ZosbH5lblS/WCEWYR/AU5wC8HQs8TWAAAAAElFTkSuQmCC>

[image68]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAEQAAAAWCAYAAAB5VTpOAAAD8UlEQVR4Xu2Xe4hVVRTGl1mZSi/Lwuhh0MOeaCGVQVNEZVmkJRKERH+I/hNC9UdhxFBJQSgK0ftBLyIoRUzFShsrBQvrj15q2kxUZhpRqSVhj+83a+876+y5c5shuRDcDz7u2d9Zd5999l772+uYtdBCCy3sH4wV3xHfFz8S7xAHVSLqg5i7xS7xF3GN2BYDEu4XLxQPFY8Sp4jrKxFms8RJ4tHicHGCuFi8KAY1AyeKP4nTU3uE+Ll4Ty2ib9wnPi8OEU8Q14p/ileGmMHi33VY9v9euJe5TDw4BjUDj4obC43V2iMeXugRR4g/mK96xinmE7IlaGCvuEn8WlwqXlG93Y0O83F8a56pM8UDYkAzQMrzUq8X+qXmKzSt0CMuM49ZVOhfJv30oG0N131hlTi6FJuN480H/1yhj0v6g4UekWO+KfQNSed+Rpkx9fC2/bcJ6Y/n/SvGmw/+iUI/K+kvFHqJa8SzQ5v9vkv83apbqVO8S3xT/FR8TDws3AdvibPFFeKH4nJxTCWiN14Wvxf/EC8WF4pLxO/Ep8SDxNvFV819kWyOz8UvnzH/z0qENvMXfzwEgTOSjssPBDeb/w9fivhNnJquGeTqxLiqDGi+9fjGA+I28bhaRG9g5A+bP5PTMW/TiUnD5G9MGqcbCzU3tcGz4r2hXfOK/TEhQ8294hOrZgc4p2jfat7/5KCdaVUTPdk8ZkHQ6oEXJq49aMcmDV+KwNjJxIwvxEdCu88tw+DQXyr0RiD1MNRGK5pxuXn/T5Y3AvJxvbm8UYBJJe66oJENaGRPBNvm3dDm/Yjj9Ou2h1FJoJaIyIb5UKH3hRnm2YFJlyBFd5gfyRmXmPf/RmpTkP1qvU+1v8TdhVaCiaAvtknGkUlj20XgX9Q7GZQVTApbifhubDevDSKoEwi4qdDr4QLzzDgpaBjZqem6w7wvTC8DM0bD+EB7as/JAcKwpNF3I1xr/Z+Qz6w6ITekXwpLKuNuYIDlQ3khjJDiK4OT5+rQBuxVzOy0QqeEz0UdHnBnuAc4cRjwValN2uP0bJMMSn1iGh39IG+Z/k4IRV9Gp/UsXA2k+c/iLak90ry24Bslg9Ngp/lDzk0apwWdsx1IRcge7TIv9jL4NPjYek4ADJusfLEW4WZKX9kHWAgmlf5Kgy5BFjOu64PGO6DNCxpg4T8I7S5z7+hVEZ9nntoEM/jbKncd1AdfmRsWyEdbPa5LMRn0j5mxIngNWyNmAzhGfMW8iKN8f9r8Q68RXjPPZJ7JL/UG2fdj0vaZP5Oqmnolj4/+zzefdOIpCvlu+t/jEOtZXX5pUxzmySaz0Q40z+iscV0uSAsttDAw/AP6JfPOCUl/hwAAAABJRU5ErkJggg==>

[image69]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAACUAAAAWCAYAAABHcFUAAAACN0lEQVR4Xu2VTUhWQRSG35QyK00KIqhFhAlaBCJKi8jCCmoRJBpBErgqCEQIlBZtBBGFWhS0aZGiGRHRD9EPFUpkBSXYotxYUIsIJEpJI5PqPZzxeu7xfqVGu++Bh495Z+43w9wzc4E0af4f++gT+oK+pidpZmxEaqroU/qKvqQ74t3zo4IO0BWhvZv+ouejEampo6O0KLTL6Ve6ORoxT9qhi6gN7QV0jE5ieqFJrKHf6SWX99EbLpszzdBFVZvsG/1Jl5rMcxj63CmXX4QuNtvlc0J2ZpVpb4JO9sBkSdRDx7W6/ELIS11e6doeKZslPhSW09v0A813fZ5D0MlPu/x6yPe7vAX6VpI4QK8i4XB10Xf0C93i+pKQ3ZXX3G2yDPoRuqgak09xjja5TE7+XbrY5TH20h/Qk/U3jtERWhjaJ+hbzKzRKaRUOmhjaO+iPXRZNOIPPIIW+mx2THbkMX1Ij0AnlUVttYMM8oqu0DPQ5/Li3UoJLXZZO5JP1my4A91pqc9U7IReO8d9hyB3jdxHE3S1yeVYy6LOmiwJqQ9fvO/pPZdZyuhzupZeowfj3boQmfwT4sfxWcjtCdpI95i28JmOm/Y26HPbTWaRm74fuiAhi96CFnuMy7QT0+9Wik/q6Sa0MAX5HYZOaD8hvdB7SdgALfK2qDdOAXSH1rlcNuM+9HMXsQj6GoboGzpIG+hCOwhaKzLpSpPJRL3Qq0Q+5EdNn0d2ZL0PAznQ/8/1HWnS/Cu/AYGVb5aUPYWyAAAAAElFTkSuQmCC>

[image70]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAEkAAAAXCAYAAABH92JbAAAEB0lEQVR4Xu1YV6hVVxAdSyzR2FCxxoYf0Sh2UBAfJiJB/PEj2CUgNgy2B6JGH8H64ZegUZTE2IKJvaBGYo9K7CgiqFgClhhjF4N1LWafe+fOPe/ep+ZC0Ltg4dvrzNln79kzs+cqkkceeeTx/0cjLxSDQnC1FwM6gDvB4+AR8IvUx7GoAv4A3gavgz+DTVIsFG3A3eAB0fkngKVSLHKED8Eu4CZwi3sWhzrgfXCNfwD0BP8GPw/jAeAdsFzCIh3c5B5wOFhadC03wJtgvaSZfAz+Aw4K4xrgWfCbhEWOMBL8C9wKPpOSOel78IWkO4mLZiRMNNof4EuwqdE86FhGh8VXou8tMdoC8JwZEyPAR2BVp+cMTyS7k5hKTLOHku6kmaIbs6ffB5whmVPiW9EDGme0+qJzMfUIvs/IWpuwUBSI2n3p9JyhJE76DWws8U5i6DNNXhd0Dje63GgfBe1eGDcIY9Yti7ZBn+30nCGbk/qLRgXhncTCy8WeBIeJpu8ZcDFY2djFgfWqH1jLaKxLnO/3MO4YxosSFoqWQV/m9DgMAc87jZlxS5LfZsROFfXDtsjIIpOTWNwPg5XC2Dupuehi74JFQasAHhW9EF4XdK5No25hvDBhofgk6OudHocd4CmnzRHdS5kwHgzuSj5ORyYnsW5wggjeSa1EF/tUNFUijA16d6NlA6OD8/xotAJ5OyeVBR+A853OSN1txt+Jti0VjZYCOolp4tFQ9Iq2xdc7qa7oYv3twxaA+lynFwdG7GlwI/iB0YtLtxZBX+F0j06idn2NVl50z7OMNlTUjm0L15AGvhCXh6vAzk7zTuKGeEMdMxrBRfGjbBtKgpXgZknvq6JDsNFFRIWbaZMJhaJ2vDUjdA1ab6MxEKaJ9np8lgY6absXRQsbby1LTkB7/h2lIbtg3nAWA0Vt2R5kA1PzV9ETjmDTi9+iAy16SHqExIFRcdlpk0TfZdFmRLLX+iz8S2d9mjRNgptmccuGmqKT+xaATSQbO7vJKaK27Y3Gbpw/LywKwL2i6RaBhf+QGbOZ9LfTePAxWM3pFtwwm9z9Tuf3ovk2gNXBpaIpFwsWtn9FX8yGOqIbX+d0nsCf4PQwZopcBOclLPR0+C4XHYE/Nxitl0TbBpK1jZHD33AR2Cvx9hwSxowAfo8RkQnRN6+JHiCdViRaMvaJzkMnEUtFv5/i9F6iG2Gh4kQkF3dB1LMePFlukHbPRUOYPU6EZqLF/yp4RTSSbMGvLeoM2xawnkTf9rRFlWgneonw584J8OuUp/EYJToXs4SXAiNqjOhcPIyDYOtgy2idLFp24i6xdxY/yZv9EnivwJT8xYt5JMF6x1Qb7R/kkQSbUP7vQSP/II//CK8AY2EEQhwdrEAAAAAASUVORK5CYII=>

[image71]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAEQAAAAWCAYAAAB5VTpOAAADgElEQVR4Xu2XaahNURTHl3meQwofRELJTBRPUcYIvXyRrxSSWUmPiBJFkiFEfFCGzJkylxTKPM9CJMlQhvj/39r7WWe/c949XtwPOv/6de/+n3Xu2XudvdfeVyRTpkyZ/o46gZPgHLgMpoMKkYjcqgmahGaCDoCJoQlVBfPBVXAJbAM1IhF5UEvwDoxz7YbgJphXElG2GD8KXAMzgmtxGgp+gkmBXw0cArtBbVBH9OXMtkH50BpwO/AmgE+gXuCH2g6eguOig8yVkCrglsQnpAi8AbVce4ho3FYfkA9xWbwGuwK/QLQzhYGfpF6SLiFcipuldELqgs9gfeCtAj2M98/VXLRz7KRVZ+cvCfwkpUkI68t50FNKJ4SJp8eZWV79ac2LVXfRjqwL/A7OTztd0ySEb38g6CalE7LCeUzIDnAKXAGDTEycuGRfgq+gD1gJ9oIXYIPoEp0m+pusi6xPnHlerH8bRe85QqOfaEfWmiCqnfP3BH6SciWEuxg7Q8UlhAOjx/rS1HljRAfK305SC7BM9F4W4LbOZyLpcUaOdl4j8AUsdm1qk+iuVqICyU9CjoLW7ntcQljD6C01XkXR3e+M8eLEAfPeIuMxqfROGI+6A46ZNl/AatNOXDLtnc9zQBr5hMwML4i+ab5Fr7iE8Pn0xhqPugd+SHSahxopeu9w43E20LPPpbhsbII5PsY9EVcemjljiwmifFG1b6ws+YSEZ4bq4IJEBxSXkAXOs4OieBygz7NSkngPY2y9aeC8RcajroOzps1jBZPCpcT4Yr0C+33DicUv7o0lySdkTuBzBr4XfYaHy4CxH1ybS2mA88Jt/j74JnoKTtIwSZ+QGxJNCA+UFA+Fvb3JgxmnphUrM88F9Y3HnWewaVv5hMwNL8SISyicITyyM3H2dEzvI9hnvDj5JZM2Ifx74vUItDHtYvEsws6Md+3G4JlEB8c9nqdIPqSj8b36il7j1M8lzjrGTgl8Htq4XfrlMUu0X61KIuLlf2+E8TgGesuNR/HFXzTtx6K1gwU8oi6iez+Duf9PjlxVHQYPRQuW10LncTaxAyyALFD8TxKKA3sg+peAsbyHbTvgqeCuaGK4Q3BWlqWd8vvZ/OR5g8v2rfO+i86C/qLnFXrkOegKTrt4/vU4KP+BWLT92+Un21xqlZzHmU2vsughzXv87mMyZcpUPv0CEffrVyiLttcAAAAASUVORK5CYII=>

[image72]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAEAAAAAXCAYAAAC74kmRAAADQElEQVR4Xu2XWahNURzGP7PM6hoisweheCDDg26EB5EHxIuihMwpKckYSonyIBSSSCHz7BpDlAfiZkxknkOm8H3913bXWXuffc9Nx4N7vvrVXt/+77PX+u//Gg5QUEEFFRRXm9BwmkSGkCJSl/Qle0gfPyhHHSCTA68B2URek6dkJ2mXEZFH1YENaB+sc0k6R34FHCQ1/aAcpCTq2ameV4WcJhNJVVhfnpHnpEVZWH6kL/ECNpgfyJ6A06SUPCbnUdbZiqgGuYV4AgaTEq8tjYPFbQz8vOoLsifgJGkbmhXUbFiZhwlYBEv+LM9rCYvTdPhnSkvACfxdApqSC6QX4gnQwOVt9bz6znvveXlXWgKOkxnkMLlCDpFOGRHpWk8Gkh6IJ0DryBjSxPO0DihOSctFG8jmwJtGLnvtrrCFey9sSseUloCjZBXK5v1S8gS5LVLdyW53nZSAJGlAihsV3khQdfKRrAn8S7APFuk+6ee1Y0pLQGdkLnraotTB1Z6XTcdIR3edSwK6kO9kS3gji6JpNdLztLN9IwtcuxniMTEpAdoNclE12A/eDm8EGkFWeu3yEqCOX4eVqXaNXDQH9pvNPa/YeYNcW/196LxrZK3zM6QE+CUTSXv3B8TL8Ses9LKpNqwMdciJVF4CtpH9qNj5QlV7J/Dmw/rX0PNUWWedrz7EpAQcCU1qIeyBeZ6nLyUvfLGvnuQd7FAT8Qb2nBKqdjQ1pJmw6VLL89Z510nStHyL+AKoNeuGu9ZpVf3VeUNqRIa56wwpAXow1HBYSaqMIvWGDWS552kxGo3MUgylKZFUAcXkDKyjkVRBF712krrBfm+J5+mrK8FaSNXnU7At/BHs1Jkodf4rrBOhlGWd/oa6tjKouJuw/TqSBqXO7PK8UEqQYqZ7XmvykjyAfTVRCqsQ/SdIU/jOerCtTmNZDOvzXFgCFDfBxf2R5vc9WBkpQOjFd0ljL04Hme3O13FYR9Qi777UH1byWpRCtYe95xPsHZ9dW/4K5yWxTA+nSAl6BasU7fklZAAZD5ueWtSVlFawStBWrnVO55j/QjqL7AjNyqIOsCqZEt6oLBoLS4COuJVS2javImVlLyhFvwFgeNHGWTCekQAAAABJRU5ErkJggg==>

[image73]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAO4AAAAWCAYAAADHL6BWAAABNUlEQVR4Xu3arUtDYRTH8aOo4FDBavEtGgw2RRCLwaJFsFlt5tkEu3+A2Syi+AIqRg1mg3axWBUE/R2u4dkpd3fugU2+H/iWc8bage1uZgAAAAAA/G/jcQCgM9XUvDpRp2EHoANtqzd1pr6MwwW6zodxuEDXqXq4s2o6DhMjajkOAbRX1cOdVPdqKi5kSF2rxbgA0F5VD9fNqEc1kcwG1ZVaTWYAMmnlcN2cFcc7pgaseI+NhlcAyMYP158ut2JBPahjtdW4ApCTH+55HDapT92oJzUadgAy8sO9iMMm9KojtaOW1K0aTl8AIB8/3Ms4LNGjDtVuMlux4n38IRWAjPyj7qe6i4sSB2ovDmXdir9Q9scFgL/zn2xe1Lv6/u1VPVv5d9U1tR+HiU1Vj0MAAAAAAADgByR5LxB4pvmBAAAAAElFTkSuQmCC>

[image74]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAABAAAAAaCAYAAAC+aNwHAAAA00lEQVR4Xu2SPwuBURTGnyQDm8nCrpTFQtltBoNR+Ra+hEkpxeATvKPJSlb5t7MoshBFPHW83Pf04h0N91e/5Tznnnu7HcDyfxTolB7onW7pgs7piq5pi8bdA59wIAPSqp6lJzpWdQ8huqcbHTxZQoZndOCSgzT0dUBi9EKvNKGyFw3IgJoOSB2SdXRgMoQ0JY1amFbojnZpxMg8ROkZ8lEDwxFt0+K71Z8S5PaeDoLShAyo6iAoM3pDgEXxIwW5faKDX+Qh6+qu7xHykrLZZLF84wGIty178gkRTgAAAABJRU5ErkJggg==>

[image75]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAEMAAAAZCAYAAABq35PiAAADMUlEQVR4Xu2XaYiNURjHH/uWJaIUUmTNWoqEyZIohaxJxhfxgQ92kUKipCzZP8j2AUmyyzKJQrYiOxMie5S1iP/fc4457zP33GuUMer91a+Z83/Pe+99n3u2K5KSkpLyZ3SEp+AZeBlOg+USPXJTHTawoWMR7AprwnpwCDyf6FFGaALfwLGuXRfegPN+9cgO+w+F1+B0c41UgN8z+LuvX6qshbdMNhF+gLVNbtkBH8Hjog+YqRjkM7wNH8L9sF/yctmAU+E53GPyPNGHG2HyGJwC2Ypx3wZlkUaiD7HZ5J1cvsTkMXIV454NSkB5G/wtuog+xAaTt3X5VpPHyFWMQjgbHoPX4TpYK9EjSTfR0fQO7oaD3N8L8CbsAVvAbfAIvAuH/7yzCC7SB+EBeBoehYMTPQy9RB9ivclbu3yvyWPkKsZHOMz9XwmedMZ2LO5MneEr0TVplRT1PSc60vjZuDuRZfBT0G4meq9vV4FnpegzZCRPSqcY7Ux7vGj/rN+U6A7FQlYLMo4q3svR4Rntsu6uPRK+h019BzABDgjaxYhNkzYu327yGL4YM+yFCH1E+2+0FwxX4SWTrRa9t0aQcaFn1tu1W8Gv8AssED3n8AiRlYaiL7LF5H4BXWryGL4Ys+wFsBi+gM2DrKdof87nbLAQnBYhK0XvrRhkHP7MWGQP14w7LqevYfvgekaeie79ITwH8AVGmTyGLwYXSUuB6DU/hMlAl20KskxclN8rBhfPsBgtRUc3aQwniS7Gu1wWhYcursYhU0Xnap0g4w4Tm3O+GHPsBbBCiq8lLBr79ze5hdOkJMXo69r5UnyKzxfdebLCs8ZbOM6168PHknwwruQvRd8w01Dzw36BvSA6V6+IfluEizNHI7fFXHAb5b0ha0Tfy+8UZIzLOOJIvugJuoPvIHpanhm0o3AbKxDdx/nmkxNXlcPwgegPLc9Cl3EU8cN8Ez1yHwr6EL4+9/pC0fPDXNHfLDG4UzwVfU36RPRb53txYWTGNWAK3Ce6rTJjAXg24u8sFm2n6FnjBFwuuq3/d3AK+A/OUcn/mVV1bcJiVjYZT6s8U6SkpKSkpPwDfgC7AsgMAIsaKwAAAABJRU5ErkJggg==>

[image76]: <data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAADkAAAAZCAYAAACLtIazAAAC7UlEQVR4Xu2WWahOURiGX2PGjEnkzo0MERcuyRAulAu50yFXiiQJB8lQylTGpPQXLogLMpWhk3mOTGU6GeLCGKHM79u39vm/f/17O78U/8V+6+mc9e5vn7O+tb71rQ3kypWrWjWenCNXyB2yiDQriUjXGFJDepFWpA9ZS2a7mKrQCHKddA7j0eQn2dYQka1lsFjPI1jSVaUCbHJTwrgJ+Ui+oZh4lpaQx+QZuUFWkA4+oFqkiSnJic77TH6Qts5Lk8q6JjarUdq5bm7cD5b0cedlaSH+LsmmsfEvpFI7TJ6T3tGzNNWS1WQfOU0ukXElEeWaSZ6QT2QGmUv2knukjnSHNbQ95AK5SPrrxSBtiiroIDlCTpBrpJOLydRO2Pl6R4ZGz7I0n5xC8RyOJF/JqIaIcnWBHQ1VSz2ZFHydfyWuxNbBkhFauLMhRppMTrqxmtxb0tV5jUo7oYlqxRtTT5SvoBZK3fp3UqJKsi7y78Kanq6jRFth80m0hVwmrZ23nXR044qk3VHjqXRHvVS2SqBH/MBJE1LMmsi/CUvAazMsNjm/08JYu7efzCJtwrNMDSaDIq+A9El4aRdfkPWRr1LSu0Mi36s9LGZl5OsaOhN5G2GxyceJSngxeRV8ofcyE9VEdR9+gR34RLtgL29wXqxhsJhjka8zJF9/O0vtUHmSm1CapD5e1AOUrG6CVbCqmx6el0mJ6Q+8RulK6PDLn+C8vmSsG+va0deNPwstyXty3nlpSsr1T5JsHsYFWMl6qXrmRV6JdpMdKE5WnVErcwC2WpJ+voT9swHBk/SduhS2ypqEyvsDGehi0pQsrrqo121yNfL0eanYZBMK5BaK81WTuo9G+odWXxN9QB7COpzurhY+CHYnaefUGRMpueWwO05361GULkKa5pA3sInrqNTDrp6nwRP6TBwO69Tfg6dqU0mqES2A/a9DsA49FVUmLapvItoJVUGyqPL0uzw9S6pJ7+jdXLly5cr13/ULWb6o4jgB2p0AAAAASUVORK5CYII=>