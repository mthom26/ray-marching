out vec4 fragColor;

uniform float time;
uniform vec2 resolution;

const int MAX_STEPS = 255;
const float MIN_DIST = 0.0;
const float MAX_DIST = 100.0;
const float EPSILON = 0.001;

const float SHADOW_FALLOFF = 0.05;

float op_union(float distA, float distB) {
    return min(distA, distB);
}

float op_intersect(float distA, float distB) {
    return max(distA, distB);
}

// Inside distA and outside distB
float op_difference(float distA, float distB) {
    return max(distA, -distB);
}

float sdf_sphere(vec3 p, float r) {
  return length(p) - r;
}

float sdf_box(vec3 p, vec3 b) {
  vec3 q = abs(p) - b;
  return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0);
}

float sdf_plane(vec3 p, vec4 n) {
  // n.xyz is the normal to the plane (e.g. up from the ground)
  // n.w is the distance along the normal the plane sits
  return dot(p, normalize(n.xyz)) + n.w;
}

float sdf_ground(vec3 p, float r) {
  // Just a simple plane along the `xz` axes
  return dot(p, vec3(0.0, 1.0, 0.0)) + r;
}

// Utility function to compare the previously set closest hit point and material,
// this should be called after a new object is added to the scene
vec2 check_mat(vec2 closest, float next, float next_mat) {
  if (next < closest.x) {
    return vec2(next, next_mat);
  }
  return closest;
}

vec2 sdf_scene(vec3 p) {
  vec2 closest_mat = vec2(MAX_DIST, 0.0);

  float sphere = sdf_sphere(p, 1.2);
  float sphere_mat = 1.0;
  closest_mat = check_mat(closest_mat, sphere, sphere_mat);

  vec3 cube_transform = vec3(0.0, 0.0, 0.0);
  float cube = sdf_box(p - cube_transform, vec3(1.0));
  float cube_mat = 2.0;
  closest_mat = check_mat(closest_mat, cube, cube_mat);

  float ground = sdf_ground(p, 2.0);
  float ground_mat = 3.0;
  closest_mat = check_mat(closest_mat, ground, ground_mat);

  float res = op_union(cube, sphere);
  res = op_union(res, ground);
  return vec2(res, closest_mat.y);
}

// Check for shadow: 1.0 is a hit, 0.0 is no hit
float ray_cast_shadow(vec3 origin, vec3 dir) {
  float depth = MIN_DIST;

  for (int i = 0; i < MAX_STEPS; i++) {
    float dist = sdf_scene(origin + dir * depth).x;
    if (dist < EPSILON) {
      // Hit something there must be a shadow
      return 1.0;
    }
    depth += dist;
    if (depth > MAX_DIST) {
      return 0.0;
    }
  }
  return 0.0;
}

// Returns a vec2 containing the closest hit point and its material
vec2 ray_march(vec3 origin, vec3 dir) {
  float depth = MIN_DIST;
  for (int i = 0; i < MAX_STEPS; i++) {
    vec2 dist = sdf_scene(origin + dir * depth);
    if (dist.x < EPSILON) {
      return vec2(depth, dist.y);
    }
    depth += dist.x;
    if (depth > MAX_DIST) {
      return vec2(MAX_DIST, 0.0);
    }
  }
  return vec2(MAX_DIST, 0.0);
}

vec2 get_coords(vec2 coords) {
  vec2 result = 2.0 * (coords / resolution - 0.5);
  result.x *= resolution.x / resolution.y;
  return result;
}

vec3 get_camera_ray(vec2 uv, vec3 cam_pos, vec3 look_at) {
  vec3 forward = normalize(look_at - cam_pos);
  vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), forward));
  vec3 up = normalize(cross(forward, right));

  float zoom = 1.0;

  vec3 dir = normalize(uv.x * right + uv.y * up + forward * zoom);

  return dir;
}

vec3 background_color(vec3 ray_dir) {
  float t = (ray_dir.y + 1.0) * 0.5;
  vec3 a = (1.0 - t) * vec3(1.0, 1.0, 1.0);
  vec3 b = t * vec3(0.5, 0.7, 0.9);
  return a + b; 
}

vec3 get_normal(vec3 p) {
  float pp = sdf_scene(p).x;

  return normalize(vec3(
    sdf_scene(p + vec3(EPSILON, 0.0, 0.0)).x,
    sdf_scene(p + vec3(0.0, EPSILON, 0.0)).x,
    sdf_scene(p + vec3(0.0, 0.0, EPSILON)).x
  ) - pp);  
}

// Basic sharp edge shadow
vec3 shadow(vec3 col, vec3 p, vec3 N, vec3 L) {
  vec3 shadow_origin = p + N * EPSILON;

  float shadow = ray_cast_shadow(shadow_origin, L);

  return mix(col, col*0.2, shadow);
}

// Smooth shadow
// Increasing the `shadow_ray_count` increases shadow smoothness but is very inefficient
vec3 shadow_smooth(vec3 col, vec3 p, vec3 N, vec3 L) {
  vec3 shadow_origin = p + N * EPSILON;
  float shadow_ray_count = 20.0;
  float shadow = 0.0;

  for (float i = 0.0; i < shadow_ray_count; i++) {
    float rand = fract(sin(dot(L.xy + i / 100.0, vec2(12.9898, 78.233))) * 43758.5453) * 2.0 - 1.0;
    vec3 dir = L + vec3(rand * SHADOW_FALLOFF);
    shadow += ray_cast_shadow(shadow_origin, dir);
  }

  // Check that we don't divide 0.0 by something
  if (shadow == 0.0) {
    return mix(col, col * 0.2, shadow);
  } 
  return mix(col, col * 0.2, shadow / shadow_ray_count);
}

// Soft shadow using `http://iquilezles.org/www/articles/rmshadows/rmshadows.htm`
// A lower `w` value gives a sharper shadow
vec3 soft_shadow(vec3 col, vec3 p, vec3 N, vec3 L) {
  vec3 shadow_origin = p + N * EPSILON;
  float s = 1.0;
  float w = 0.075;
  float depth = MIN_DIST;
  
  for (int i = 0; i < MAX_STEPS; i++) {
    float dist = sdf_scene(shadow_origin + L * depth).x;
    s = min(s, 0.5 + 0.5 * dist / (w * depth));
    if (s < 0.0) break;
    depth += dist;
    if (depth > MAX_DIST) break;
  }

  s = max(s, 0.0);
  float shadow = 1.0 - (s * s * (3.0 - 2.0 * s));

  return mix(col, col * 0.2, shadow);
}

vec3 phong_light(vec3 light_pos, vec3 cam_pos, vec3 p, vec3 intensity, vec3 kd, vec3 ks, float alpha, vec3 random) {
  vec3 col = vec3(0.0, 0.0, 0.0);

  vec3 L = normalize(light_pos - p);
  vec3 N = get_normal(p);
  vec3 V = normalize(cam_pos - p);
  vec3 R = normalize(reflect(-L, N));

  float dotLN = dot(L, N);
  float dotRV = dot(R, V);

  if (dotLN < 0.0) {
    return vec3(0.0, 0.0, 0.0);
  }

  if (dotRV < 0.0) {
    col = kd * dotLN * intensity; 
  } else {
    col = (kd * dotLN + ks * pow(dotRV, alpha)) * intensity;
  }

  // Shadow
  col = soft_shadow(col, p, N, L);

  return col;
}

vec3 render(vec3 cam_pos, vec3 ray_dir) {
  vec2 dist = ray_march(cam_pos, ray_dir);

  // Didn't hit anything
  if (dist.x > MAX_DIST - EPSILON) {
    // return background_color(ray_dir);
    return vec3(0.0);
  }

  vec3 hit_p = cam_pos + ray_dir * dist.x;

  vec3 col = vec3(0.0, 0.0, 0.0);

  // Ground Material - 3.0
  vec3 k_a = vec3(0.2, 0.2, 0.2); // Ambient
  vec3 k_d = vec3(0.4, 0.4, 0.5); // Diffuse
  vec3 k_s = vec3(0.8, 0.8, 0.8); // Specular
  float shininess = 5.0; // Specular Power

  // Check Material hit
  if (dist.y == 2.0) { // Cube Material - 2.0
    k_a = vec3(0.2, 0.2, 0.2);
    k_d = vec3(0.7, 0.2, 0.2);
    k_s = vec3(1.0, 0.8, 0.4);
    shininess = 10.0;
  } else if (dist.y == 1.0) { // Sphere Material - 1.0
    k_a = vec3(0.2, 0.2, 0.2);
    k_d = vec3(0.25, 0.7, 0.2);
    k_s = vec3(0.8, 0.9, 0.4);
    shininess = 10.0;
  }

  // Ambient light
  vec3 ambient = vec3(0.2, 0.2, 0.2);
  col += ambient * k_a;

  // Light Setup
  vec3 light_pos = vec3(2.4, 3.7, -3.0);
  vec3 light_intensity = vec3(0.8, 0.8, 0.8);

  col += phong_light(light_pos, cam_pos, hit_p, light_intensity, k_d, k_s, shininess, ray_dir);

  // vec3 col = ambient * obj_color;
  // vec3 col = get_normal(cam_pos + ray_dir * dist) * 0.5 + vec3(0.5);
  return col;
}

void main() {
  vec3 cam_pos = vec3(2.1, 1.9, -3.8);
  vec3 look_at = vec3(0.0, 0.0, 0.0);

  vec2 uv = get_coords(gl_FragCoord.xy);
  vec3 ray_dir = get_camera_ray(uv, cam_pos, look_at);

  vec3 col = render(cam_pos, ray_dir);
  
  fragColor = vec4(col, 1.0);
}
