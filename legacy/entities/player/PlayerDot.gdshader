shader_type canvas_item;
render_mode blend_mix;

// Team & Kit Colors
uniform vec4 team_color : source_color = vec4(0.25, 0.55, 1.0, 1.0);
uniform vec4 secondary_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform bool is_goalkeeper = false;
uniform vec4 gk_color : source_color = vec4(0.12, 0.78, 0.42, 1.0);
uniform bool is_captain = false;

// Orientation & State
uniform float facing_angle = 0.0;
uniform bool is_user_controlled = false;
uniform bool is_possessor = false;

// Lighting Parameters
uniform vec3 light_direction = vec3(-0.35, -0.60, 0.72);
uniform float ambient_light : hint_range(0.0, 1.0) = 0.72;
uniform float diffuse_intensity : hint_range(0.0, 1.0) = 0.42;
uniform float specular_power : hint_range(1.0, 64.0) = 18.0;
uniform float specular_intensity : hint_range(0.0, 1.0) = 0.36;
uniform float rim_shadow_strength : hint_range(0.0, 1.0) = 0.42;

const float PI_VAL = 3.14159265359;

void fragment() {
	// Centered UV in [-1.0, 1.0]
	vec2 p = (UV - vec2(0.5)) * 2.0;
	float r2 = dot(p, p);

	if (r2 > 1.0) {
		COLOR = vec4(0.0);
		discard;
	}

	float r = sqrt(r2);
	// Smooth anti-aliased perimeter edge
	float alpha_edge = smoothstep(1.0, 0.92, r);

	// 3D Surface normal on hemisphere (camera space)
	float z = sqrt(max(0.0, 1.0 - r2));
	vec3 normal = vec3(p.x, p.y, z);

	// Normalize light direction
	vec3 l_dir = normalize(light_direction);

	// Diffuse lighting (Lambertian)
	float n_dot_l = max(0.0, dot(normal, l_dir));
	float lighting = ambient_light + n_dot_l * diffuse_intensity;

	// Specular highlight (Blinn-Phong)
	vec3 view_dir = vec3(0.0, 0.0, 1.0);
	vec3 half_vector = normalize(l_dir + view_dir);
	float spec = pow(max(0.0, dot(normal, half_vector)), specular_power) * specular_intensity;

	// Spherical ambient occlusion / rim darkening
	float rim = 1.0 - pow(1.0 - z, 3.0) * rim_shadow_strength;

	// Base Kit Palette selection
	vec3 base_kit = is_goalkeeper ? gk_color.rgb : team_color.rgb;
	vec3 sec_kit = secondary_color.rgb;

	// Angle around the center of the token
	float angle = atan(p.y, p.x);
	float angle_diff = abs(mod(angle - facing_angle + PI_VAL, 2.0 * PI_VAL) - PI_VAL);

	// Surface layering:
	// Inner body (r < 0.78), Outer Rim Bezel (0.78 <= r <= 1.0)
	vec3 surface_rgb = base_kit;

	// 1. Outer Bezel / Rim styling
	if (r >= 0.78) {
		float rim_t = (r - 0.78) / 0.22;
		if (is_captain) {
			// Golden captain rim accent
			vec3 gold = vec3(1.0, 0.82, 0.15);
			surface_rgb = mix(gold, sec_kit, 0.35);
		} else if (is_goalkeeper) {
			// Crisp dark-contrast padded goalkeeper bezel
			surface_rgb = mix(base_kit * 0.45, vec3(0.12, 0.14, 0.16), 0.65);
		} else {
			// Secondary color or sleek dark contrast kit trim
			surface_rgb = mix(base_kit * 0.40, sec_kit, 0.70);
		}
		// Rim bevel gradient
		surface_rgb *= (1.0 - rim_t * 0.25);
	} else {
		// Subtle inner kit pattern: slight center lightening for tactile depth
		surface_rgb = mix(surface_rgb, surface_rgb * 1.15, (1.0 - r / 0.78) * 0.40);
	}

	// 2. Goalkeeper Glove Grip Accents on left/right flanks (at 90 deg from facing direction)
	if (is_goalkeeper) {
		float side_diff_left = abs(mod(angle - (facing_angle + PI_VAL * 0.5) + PI_VAL, 2.0 * PI_VAL) - PI_VAL);
		float side_diff_right = abs(mod(angle - (facing_angle - PI_VAL * 0.5) + PI_VAL, 2.0 * PI_VAL) - PI_VAL);
		if ((side_diff_left < 0.42 || side_diff_right < 0.42) && r >= 0.64 && r <= 0.92) {
			// Glove grip padding (high-contrast white/black grip pad)
			vec3 glove_pad = vec3(0.96, 0.96, 0.98);
			surface_rgb = mix(surface_rgb, glove_pad, 0.85);
		}
	}

	// 3. Directional Visor Notch on front rim
	if (angle_diff < 0.38 && r >= 0.68 && r <= 0.94) {
		float notch_factor = 1.0 - (angle_diff / 0.38);
		vec3 visor_col = mix(sec_kit, vec3(1.0, 1.0, 1.0), 0.5);
		surface_rgb = mix(surface_rgb, visor_col, notch_factor * 0.85);
	}

	// 4. Composite 3D Lighting
	vec3 final_rgb = (surface_rgb * lighting + vec3(spec)) * rim;

	// 5. Active User Selection Aura Pulse
	if (is_user_controlled && r >= 0.82) {
		float pulse = 0.5 + 0.5 * sin(TIME * 5.0);
		vec3 aura_col = vec3(0.90, 0.95, 1.0) * (pulse * 0.35);
		final_rgb += aura_col;
	}

	// 6. Ball Possession Flare
	if (is_possessor && r >= 0.76) {
		float glow = 0.5 + 0.5 * sin(TIME * 8.0);
		vec3 poss_col = mix(vec3(1.0, 0.85, 0.20), sec_kit, 0.3) * (glow * 0.30);
		final_rgb += poss_col;
	}

	COLOR = vec4(final_rgb, alpha_edge);
}
