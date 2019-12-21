out vec4 fragColor;

uniform float time;
uniform vec2 resolution;

const int MAX_STEPS = 255;
const float MIN_DIST = 0.0;
const float MAX_DIST = 100.0;
const float EPSILON = 0.001;

float op_union(float distA, float distB) {
    return min(distA, distB);
}

float sdf_sphere(vec3 p, float r) {
  return length(p) - r;
}

float sdf_plane(vec3 p, vec4 n)
{
  // n.xyz is the normal to the plane (e.g. up from the ground)
  // n.w is the distance along the normal the plane sits
  return dot(p, normalize(n.xyz)) + n.w;
}

float sdf_scene(vec3 p) {
  float sphere = sdf_sphere(p, 1.0);
  float plane = sdf_plane(p, vec4(0.0, 1.0, 0.0, 1.5));

  return op_union(sphere, plane);
}

// Check for shadow: 1.0 is a hit, 0.0 is no hit
float ray_cast_shadow(vec3 origin, vec3 dir) {
  float depth = MIN_DIST;

  for (int i = 0; i < MAX_STEPS; i++) {
    float dist = sdf_scene(origin + dir * depth);
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

float ray_march(vec3 origin, vec3 dir) {
  float depth = MIN_DIST;
  for (int i = 0; i < MAX_STEPS; i++) {
    float dist = sdf_scene(origin + dir * depth);
    if (dist < EPSILON) {
      return depth;
    }
    depth += dist;
    if (depth > MAX_DIST) {
      return MAX_DIST;
    }
  }
  return MAX_DIST;
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
  float pp = sdf_scene(p);

  return normalize(vec3(
    sdf_scene(p + vec3(EPSILON, 0.0, 0.0)),
    sdf_scene(p + vec3(0.0, EPSILON, 0.0)),
    sdf_scene(p + vec3(0.0, 0.0, EPSILON))
  ) - pp);  
}

vec3 phong_light(vec3 light_pos, vec3 cam_pos, vec3 p, vec3 intensity, vec3 kd, vec3 ks, float alpha) {
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
  vec3 shadow_origin = p + N * EPSILON;

  float shadow = ray_cast_shadow(shadow_origin, L);

  col = mix(col, col*0.2, shadow);

  return col;
}

vec3 render(vec3 cam_pos, vec3 ray_dir) {
  float dist = ray_march(cam_pos, ray_dir);

  // Didn't hit anything
  if (dist > MAX_DIST - EPSILON) {
    // return background_color(ray_dir);
    return vec3(0.0);
  }

  vec3 hit_p = cam_pos + ray_dir * dist;

  vec3 col = vec3(0.0, 0.0, 0.0);

  // Object Material
  vec3 k_a = vec3(0.2, 0.2, 0.2); // Ambient
  vec3 k_d = vec3(0.7, 0.2, 0.2); // Diffuse
  vec3 k_s = vec3(1.0, 0.8, 0.4); // Specular
  float shininess = 10.0; // Specular Power

  // Ambient light
  vec3 ambient = vec3(0.2, 0.2, 0.2);
  col += ambient * k_a;

  // Light Setup
  vec3 light_pos = vec3(0.0, 4.0, 0.0);
  vec3 light_intensity = vec3(0.8, 0.8, 0.8);

  col += phong_light(light_pos, cam_pos, hit_p, light_intensity, k_d, k_s, shininess);

  // vec3 col = ambient * obj_color;
  // vec3 col = get_normal(cam_pos + ray_dir * dist) * 0.5 + vec3(0.5);
  return col;
}

void main() {
  vec3 cam_pos = vec3(0.0, 0.5, -3.0);
  vec3 look_at = vec3(0.0, 0.0, 0.0);

  vec2 uv = get_coords(gl_FragCoord.xy);
  vec3 ray_dir = get_camera_ray(uv, cam_pos, look_at);

  vec3 col = render(cam_pos, ray_dir);
  
  fragColor = vec4(col, 1.0);
}
