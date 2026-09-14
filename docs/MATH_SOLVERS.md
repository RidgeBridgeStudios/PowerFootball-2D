> [!WARNING]
> **PARTIALLY SUPERSEDED — scope note.**
> Sections 2–6 document solvers for the abandoned 22-player real-time engine (`HeavyPlayerController` turning penalty, `Pseudo3DBall` flight, ball-intercept bisection, `PassUtilityScorer`, `FormationAnchorMath`). That code now lives archived under `legacy/`; these formulas are retained as reference math for deepening `QuickSimEngine`, not as current implementation guidance.
> Section 1 (`shared/UtilityMath.gd`) is still live.
> Start with [architecture-pivot.md](agent-errata/architecture-pivot.md); canonical contracts: [CORE_INVARIANTS.md](CORE_INVARIANTS.md).

# MATH_SOLVERS.md — Ground-Truth Mathematical Solvers & Closed-Form Formulations

Canonical mathematical specifications, derivation proofs, and GDScript reference implementations for **PowerFootball-2D** simulation layers.

---

## 1. Kinematic Point-to-Segment Projection & Distance

Used for passing lane interception, defender occlusion checks, and boundary snapping.

### Mathematical Formulation
Given a segment from point $\mathbf{p}_{\text{start}}$ to $\mathbf{p}_{\text{end}}$, let segment vector $\mathbf{s} = \mathbf{p}_{\text{end}} - \mathbf{p}_{\text{start}}$.
The scalar projection parameter $t$ of query point $\mathbf{q}$ onto $\mathbf{s}$ is:
$$t = \text{clamp}\left(\frac{(\mathbf{q} - \mathbf{p}_{\text{start}}) \cdot \mathbf{s}}{\|\mathbf{s}\|^2}, 0.0, 1.0\right)$$

The closest point $\mathbf{c}$ on the segment is:
$$\mathbf{c} = \mathbf{p}_{\text{start}} + \mathbf{s} \cdot t$$

The squared Euclidean distance from $\mathbf{q}$ to the segment is:
$$d^2(\mathbf{q}, \text{seg}) = \|\mathbf{q} - \mathbf{c}\|^2 = (q_x - c_x)^2 + (q_y - c_y)^2$$

### GDScript 2.0 Implementation (`shared/UtilityMath.gd`)
```gdscript
static func closest_point_on_segment(point: Vector2, seg_start: Vector2, seg_end: Vector2) -> Vector2:
	var seg: Vector2 = seg_end - seg_start
	var seg_len_sq: float = seg.length_squared()
	if seg_len_sq <= 0.0001:
		return seg_start
	var t: float = clampf((point - seg_start).dot(seg) / seg_len_sq, 0.0, 1.0)
	return seg_start + seg * t

static func distance_squared_to_segment(point: Vector2, seg_start: Vector2, seg_end: Vector2) -> float:
	var closest: Vector2 = closest_point_on_segment(point, seg_start, seg_end)
	return closest.distance_squared_to(point)
```

---

## 2. Kinematic Turning Penalty & Acceleration Curve

Governs inertia and weight in `HeavyPlayerController.gd`. Players cannot turn instantly without bleeding forward momentum.

### Mathematical Formulation
Let $\mathbf{v}$ be the current velocity vector and $\mathbf{u}$ be the normalized movement intent vector.
The cosine of the angle between current heading and requested direction is:
$$\cos \theta = \frac{\mathbf{v} \cdot \mathbf{u}}{\|\mathbf{v}\|}$$

The turn severity $\gamma \in [0.0, 1.0]$ maps linearly from straight ahead ($0^\circ, \cos\theta=1$) to full reversal ($180^\circ, \cos\theta=-1$):
$$\gamma = \text{clamp}\left(\frac{1.0 - \cos \theta}{2.0}, 0.0, 1.0\right)$$

The effective acceleration rate $a_{\text{eff}}$ scaled by turning penalty factor $\mu_{\text{turn}} = 0.35$:
$$a_{\text{eff}} = a_{\text{base}} \cdot \max(1.0 - \mu_{\text{turn}} \cdot \gamma, 0.10)$$
$$a_{\text{base}} = \left(\frac{v_{\text{top}}}{t_{\text{accel}}}\right) \cdot \left(\frac{M_{\text{neutral}}}{M_{\text{player}}}\right)$$

If turning against current heading ($\cos \theta < 0$), brake friction overrides acceleration to bleed momentum:
$$a_{\text{brake}} = a_{\text{friction}} \cdot \max(\mu_{\text{turn}} \cdot \gamma, 0.5)$$
$$\text{rate} = \max(a_{\text{eff}}, a_{\text{brake}})$$
$$\mathbf{v}_{t+\Delta t} = \text{move\_toward}(\mathbf{v}_t, \mathbf{v}_{\text{target}}, \text{rate} \cdot \Delta t)$$

---

## 3. Ballistic Pseudo-3D Flight & Height Trajectory

Simulates 3D airborne ball physics projected onto a 2D plane.

### Mathematical Formulation
Ball height $z(t)$ with gravity $g = 980\text{ px/s}^2$:
$$z(t + \Delta t) = \max\left(0.0, z(t) + v_z(t) \cdot \Delta t - \frac{1}{2} g (\Delta t)^2\right)$$
$$v_z(t + \Delta t) = v_z(t) - g \cdot \Delta t$$

For a lofted pass or chip shot across ground distance $d = \|\mathbf{p}_{\text{target}} - \mathbf{p}_{\text{start}}\|$ with ground velocity $v_{xy}$:
$$t_{\text{flight}} = \frac{d}{\|\mathbf{v}_{xy}\|}$$
$$v_{z0} = \frac{g \cdot d}{1.8 \cdot \|\mathbf{v}_{xy}\|}$$

Visual projection onto screen coordinates:
$$y_{\text{render}} = y_{\text{world}} - z$$
$$\text{scale}_{\text{shadow}} = \text{clamp}\left(1.0 - \frac{z}{300.0}, 0.35, 1.0\right)$$

Bounce restitution on contact ($z \le 0$):
$$v_{z,\text{post}} = -v_{z,\text{pre}} \cdot e_{\text{bounce}}, \quad \mathbf{v}_{xy,\text{post}} = \mathbf{v}_{xy,\text{pre}} \cdot \mu_{\text{ground\_friction}}$$

---

## 4. Bisection Root-Finding Ball Intercept Algorithm

Iteratively solves for the earliest time $t^*$ where a player moving at maximum speed $v_{\text{player}}$ can meet a decelerating ball.

### Mathematical Formulation
Ball ground distance under constant friction deceleration $a_f = 180\text{ px/s}^2$:
$$s_{\text{ball}}(t) = v_{\text{ball},0} \cdot t - \frac{1}{2} a_f t^2 \quad \text{for } t \le t_{\text{stop}} = \frac{v_{\text{ball},0}}{a_f}$$
$$\mathbf{p}_{\text{ball}}(t) = \mathbf{p}_{\text{ball},0} + \hat{\mathbf{v}}_{\text{ball}} \cdot s_{\text{ball}}(t)$$

Player reach time to meeting point $\mathbf{p}_{\text{ball}}(t)$:
$$t_{\text{player}}(t) = \frac{\|\mathbf{p}_{\text{player}} - \mathbf{p}_{\text{ball}}(t)\|}{v_{\text{player}}} + t_{\text{reaction}}$$

Root equation:
$$f(t) = t_{\text{player}}(t) - t = 0$$

### Convergence & Invariants
Using bisection across interval $[0, t_{\text{stop}}]$ over $N = 8$ iterations guarantees:
$$\epsilon_t \le \frac{t_{\text{stop}}}{2^8} \le \frac{5.0}{256} \approx 0.0195\text{ seconds}$$
Spatial precision at $240\text{ px/s}$ top speed:
$$\epsilon_x \le 240 \cdot 0.0195 \approx 4.68\text{ pixels}$$

```gdscript
static func calculate_intercept_point(
		p_pos: Vector2, p_max_speed: float, b_pos: Vector2, b_vel: Vector2, friction: float, reaction_time: float = 0.08
) -> Vector2:
	var b_speed: float = b_vel.length()
	if b_speed < 10.0:
		return b_pos
	var b_dir: Vector2 = b_vel / b_speed
	var safe_friction: float = maxf(friction, 10.0)
	var t_actual_stop: float = b_speed / safe_friction
	var t_stop: float = clampf(t_actual_stop, 0.0, 5.0)
	var safe_speed: float = maxf(p_max_speed, 1.0)
	var max_travel: float = (b_speed * b_speed) / (2.0 * safe_friction)

	var lo: float = 0.0
	var hi: float = t_stop
	for _i: int in range(8):
		var mid: float = (lo + hi) * 0.5
		var t_eval: float = minf(mid, t_actual_stop)
		var travel: float = clampf(b_speed * t_eval - 0.5 * safe_friction * t_eval * t_eval, 0.0, max_travel)
		var point: Vector2 = b_pos + b_dir * travel
		var t_player: float = p_pos.distance_to(point) / safe_speed + reaction_time
		if t_player <= mid:
			hi = mid
		else:
			lo = mid

	var t_final: float = minf(hi, t_actual_stop)
	var final_travel: float = clampf(b_speed * t_final - 0.5 * safe_friction * t_final * t_final, 0.0, max_travel)
	return b_pos + b_dir * final_travel
```

---

## 5. Pass Utility Scoring Functions

Scores candidate receivers on a normalized $[0.0, 1.0]$ utility curve.

### 1. Quadratic Distance Utility Decay
$$U_{\text{dist}}(d, d_{\text{pref}}, d_{\text{max}}) = \begin{cases} 
1.0 - \left(\frac{d_{\text{pref}} - d}{d_{\text{pref}}}\right)^2 & d \le d_{\text{pref}} \\
1.0 - \left(\frac{d - d_{\text{pref}}}{d_{\text{max}} - d_{\text{pref}}}\right)^2 & d > d_{\text{pref}}
\end{cases}$$

### 2. Angular Cosine Alignment
$$U_{\text{angle}}(\hat{\mathbf{f}}_{\text{passer}}, \hat{\mathbf{d}}_{\text{pass}}) = \text{clamp}\left(\frac{\hat{\mathbf{f}}_{\text{passer}} \cdot \hat{\mathbf{d}}_{\text{pass}} + 1.0}{2.0}, 0.0, 1.0\right)$$

### 3. Receiver Openness
$$U_{\text{pressure}}(d_{\text{opponent}}, R_{\text{open}}) = \text{clamp}\left(\frac{d_{\text{opponent}}}{R_{\text{open}}}, 0.0, 1.0\right)$$

### 4. Dynamic Pressure Weight Adaptation
Under high passer pressure $P \in [0.0, 1.0]$, weight shifts away from forward advancement toward safety:
$$w_{\text{press, eff}} = w_{\text{press}} \cdot (1.0 + 0.5 \cdot P)$$
$$w_{\text{adv, eff}} = w_{\text{adv}} \cdot (1.0 - 0.5 \cdot P)$$
$$U_{\text{total}} = \frac{w_d U_d + w_a U_a + w_{\text{press, eff}} U_p + w_{\text{adv, eff}} U_{\text{adv}}}{w_d + w_a + w_{\text{press, eff}} + w_{\text{adv, eff}}}$$

---

## 6. Dynamic Formation Anchor Drift Math

Translates base formation coordinates to match state, ball position, and attacking phase.

### Mathematical Formulation
Let $\mathbf{a}_{\text{base}}$ be the formation anchor, $\mathbf{b}$ the ball position, $\mathbf{c}_{\text{pitch}}$ the pitch centre, and $\mathbf{h} = \frac{1}{2}\mathbf{S}_{\text{pitch}}$ the half-pitch dimensions.
Normalize to $[-1.0, 1.0]$ pitch space:
$$\mathbf{n}_{\text{base}} = \frac{\mathbf{a}_{\text{base}} - \mathbf{c}_{\text{pitch}}}{\mathbf{h}}, \quad \mathbf{n}_{\text{ball}} = \text{clamp}\left(\frac{\mathbf{b} - \mathbf{c}_{\text{pitch}}}{\mathbf{h}}, -1.0, 1.0\right)$$

Compactness lerp:
$$\mathbf{n}_{\text{pulled}} = \text{lerp}(\mathbf{n}_{\text{base}}, \mathbf{n}_{\text{ball}}, w_{\text{ball}})$$

Tactical line push for team phase $\Phi \in \{\text{ATTACK}, \text{DEFENSE}, \text{TRANSITION}\}$ and role sensitivity $S_{\text{role}}$:
$$\Delta x_{\text{push}} = P_{\Phi} \cdot S_{\text{role}} \cdot \text{sign}_{\text{attack}}$$
$$n_{\text{final}, x} = \text{clamp}(n_{\text{pulled}, x} + \Delta x_{\text{push}}, -1.0, 1.0)$$
$$\mathbf{a}_{\text{dynamic}} = \mathbf{c}_{\text{pitch}} + \mathbf{n}_{\text{final}} \odot \mathbf{h}$$
