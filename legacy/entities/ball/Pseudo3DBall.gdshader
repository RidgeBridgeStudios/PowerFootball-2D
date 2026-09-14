shader_type canvas_item;
render_mode blend_mix;

// 3D rotation matrix passed from Pseudo3DBall.gd
uniform mat3 ball_rotation = mat3(
	vec3(1.0, 0.0, 0.0),
	vec3(0.0, 1.0, 0.0),
	vec3(0.0, 0.0, 1.0)
);

// Texture containing the equirectangular projection of the classic Telstar soccer ball
uniform sampler2D ball_texture : filter_linear_mipmap;

// Lighting parameters
uniform vec3 light_direction = vec3(-0.35, -0.60, 0.72);
uniform float ambient_light : hint_range(0.0, 1.0) = 0.72;
uniform float diffuse_intensity : hint_range(0.0, 1.0) = 0.38;
uniform float specular_power : hint_range(1.0, 64.0) = 20.0;
uniform float specular_intensity : hint_range(0.0, 1.0) = 0.35;
uniform float rim_shadow_strength : hint_range(0.0, 1.0) = 0.40;

void fragment() {
	// Map UV coordinates (0.0 to 1.0) to centered coordinates (-1.0 to 1.0)
	vec2 p = (UV - vec2(0.5)) * 2.0;
	float r2 = dot(p, p);
	
	// Circle silhouette mask with smooth antialiasing
	if (r2 > 1.0) {
		COLOR = vec4(0.0);
		discard;
	}
	
	float r = sqrt(r2);
	// Smooth anti-aliased edge
	float alpha_edge = smoothstep(1.0, 0.94, r);
	
	// Calculate surface normal on the hemisphere (camera space)
	float z = sqrt(max(0.0, 1.0 - r2));
	vec3 normal = vec3(p.x, p.y, z);
	
	// Transform normal by ball's 3D rotation to get position in local sphere space
	vec3 local_p = ball_rotation * normal;
	
	// Convert 3D point on sphere to equirectangular spherical coordinates (longitude / latitude)
	float lon = atan(local_p.x, local_p.z);
	float lat = asin(clamp(local_p.y, -1.0, 1.0));
	
	vec2 sphere_uv = vec2(
		fract(lon / (2.0 * PI) + 0.5),
		clamp(0.5 - lat / PI, 0.001, 0.999)
	);
	
	// Sample classic soccer ball texture
	vec4 tex_color = texture(ball_texture, sphere_uv);
	
	// Normalize light direction
	vec3 l_dir = normalize(light_direction);
	
	// Diffuse lighting (Lambertian)
	float n_dot_l = max(0.0, dot(normal, l_dir));
	float lighting = ambient_light + n_dot_l * diffuse_intensity;
	
	// Specular highlight (Blinn-Phong)
	vec3 view_dir = vec3(0.0, 0.0, 1.0);
	vec3 half_vector = normalize(l_dir + view_dir);
	float spec = pow(max(0.0, dot(normal, half_vector)), specular_power) * specular_intensity;
	
	// Spherical rim darkening / ambient occlusion towards perimeter
	float rim = 1.0 - pow(1.0 - z, 3.0) * rim_shadow_strength;
	
	// Final composite color
	vec3 final_rgb = (tex_color.rgb * lighting + vec3(spec)) * rim;
	
	COLOR = vec4(final_rgb, tex_color.a * alpha_edge);
}
