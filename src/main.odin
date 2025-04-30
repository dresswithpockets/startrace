package startrace

import "base:intrinsics"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:math/rand"
import "core:mem"
import "core:os"
import "core:thread"
import "core:time"
import "vendor:stb/image"

Vector3 :: linalg.Vector3f64
Color :: linalg.Vector3f64

FORWARD :: Vector3{0, 0, 1}

Ray :: struct {
    origin:    Vector3,
    direction: Vector3,
}

Light :: struct {
    origin: Vector3,
    color:  Color,
    radius: f64,
}

Material :: struct {
    reflective: f64,
    hardness:   f64,
    roughness:  f64,
    diffuse:    f64,
    specular:   f64,
    color:      Color,
}

Object :: union {
    Triangle,
    Sphere,
    Plane,
}

Triangle :: struct {
    using material: Material,
    points:         [3]Vector3,
    u, v:           Vector3,
    normal:         Vector3,
}

make_triangle :: proc(material: Material, p0, p1, p2: Vector3) -> Triangle {
    u := p1 - p0
    v := p2 - p0
    return Triangle {
        material = material,
        points = {p0, p1, p2},
        u = u,
        v = v,
        normal = linalg.normalize(linalg.cross(v, u)),
    }
}

Sphere :: struct {
    using material: Material,
    origin:         Vector3,
    radius:         f64,
}

make_sphere :: proc(material: Material, origin: Vector3, radius: f64) -> Sphere {
    return Sphere{material = material, origin = origin, radius = radius}
}

Plane :: struct {
    using material: Material,
}

reflect_direction :: proc(ray_direction, surface_normal: Vector3, roughness: f64) -> Vector3 {
    reflected := linalg.normalize(ray_direction + surface_normal * linalg.dot(surface_normal, -ray_direction) * 2)

    random_roughness := linalg.normalize(Vector3{rand_offset(), rand_offset(), rand_offset()}) * roughness
    reflected = linalg.normalize(ray_direction + random_roughness)

    // the randomly selected ray is going inward - its an impossible reflection, so we reflect it again
    if linalg.dot(surface_normal, reflected) <= 0 {
        reflected = linalg.normalize(reflected + surface_normal * linalg.dot(surface_normal, -reflected) * 2)
    }

    return reflected
}

Trace_Info :: struct {
    material:         Material,
    point:            Vector3,
    normal:           Vector3,
    bounce_direction: Vector3,
    distance:         f64,
}

trace_ray_sphere :: proc(trace_info: ^Trace_Info, ray: Ray, sphere: Sphere) -> bool {
    p := sphere.origin - ray.origin
    p_dot := linalg.dot(p, p)
    threshold := math.sqrt(p_dot - (sphere.radius * sphere.radius))
    b := linalg.dot(p, ray.direction)

    if b <= threshold {
        return false
    }

    s := math.sqrt(p_dot - b * b)
    t := math.sqrt(sphere.radius * sphere.radius - s * s)
    hit_distance := b - t

    if hit_distance < math.F64_EPSILON {
        return false
    }

    normal := linalg.normalize(-p + ray.direction * hit_distance)
    trace_info.distance = hit_distance
    trace_info.point = ray.origin + ray.direction * hit_distance
    trace_info.material = sphere.material
    trace_info.bounce_direction = reflect_direction(ray.direction, normal, sphere.roughness)
    trace_info.normal = linalg.normalize(trace_info.bounce_direction - ray.direction)
    // ray.direction = linalg.normalize(ray.direction + normal * linalg.dot(normal, -ray.direction) * 2)

    return true
}

trace_ray_triangle :: proc(trace_info: ^Trace_Info, ray: Ray, triangle: Triangle) -> bool {
    if linalg.dot(triangle.normal, ray.direction) >= 0 {
        return false
    }

    p0 := triangle.points[0]
    pox := p0.x
    poy := p0.y
    poz := p0.z
    ux := triangle.u.x
    uy := triangle.u.y
    uz := triangle.u.z
    vx := triangle.v.x
    vy := triangle.v.y
    vz := triangle.v.z
    rx := ray.direction.x
    ry := ray.direction.y
    rz := ray.direction.z
    ox := ray.origin.x
    oy := ray.origin.y
    oz := ray.origin.z
    u_factor :=
        (-(ox - pox) * (ry * vz - rz * vy) + (oy - poy) * (rx * vz - rz * vx) - (oz - poz) * (rx * vy - ry * vx)) /
        (rx * uy * vz - rx * uz * vy - ry * ux * vz + ry * uz * vx + rz * ux * vy - rz * uy * vx)
    v_factor :=
        ((ox - pox) * (ry * uz - rz * uy) - (oy - poy) * (rx * uz - rz * ux) + (oz - poz) * (rx * uy - ry * ux)) /
        (rx * uy * vz - rx * uz * vy - ry * ux * vz + ry * uz * vx + rz * ux * vy - rz * uy * vx)
    ray_factor :=
        (-(ox - pox) * (uy * vz - uz * vy) + (oy - poy) * (ux * vz - uz * vx) - (oz - poz) * (ux * vy - uy * vx)) /
        (rx * uy * vz - rx * uz * vy - ry * ux * vz + ry * uz * vx + rz * ux * vy - rz * uy * vx)

    if u_factor < 0 || u_factor > 1 || v_factor < 0 || v_factor > 1 || (u_factor + v_factor) > 1 || ray_factor < 0 {
        return false
    }

    trace_info.distance = ray_factor
    trace_info.point = ray.origin + ray.direction * ray_factor
    trace_info.material = triangle.material
    trace_info.bounce_direction = reflect_direction(ray.direction, triangle.normal, triangle.roughness)
    trace_info.normal = linalg.normalize(trace_info.bounce_direction - ray.direction)
    return ray_factor >= 0.001
}

trace_ray_plane :: proc(trace_info: ^Trace_Info, ray: Ray, plane: Plane) -> bool {
    if ray.direction.y >= 0 {
        return false
    }

    trace_info.distance = -ray.origin.y / ray.direction.y
    x := ray.origin.x + ray.direction.x * trace_info.distance
    z := ray.origin.z + ray.direction.z * trace_info.distance

    trace_info.material = plane.material
    if math.mod(abs(math.floor(x)), 2) == math.mod(abs(math.floor(z)), 2) {
        trace_info.material.color = Color{1, 0, 0}
    } else {
        trace_info.material.color = Color{1, 1, 1}
    }

    normal := Vector3{0, 1, 0}
    trace_info.point = {x, 0, z}
    trace_info.bounce_direction = reflect_direction(ray.direction, normal, plane.roughness)
    trace_info.normal = linalg.normalize(trace_info.bounce_direction - ray.direction)
    return true
}

trace_ray_object :: proc(trace_info: ^Trace_Info, ray: Ray, object: Object) -> bool {
    switch o in object {
    case Triangle:
        return trace_ray_triangle(trace_info, ray, o)
    case Sphere:
        return trace_ray_sphere(trace_info, ray, o)
    case Plane:
        return trace_ray_plane(trace_info, ray, o)
    }
    return false
}

get_ground_hit :: proc(origin, direction: Vector3) -> (color: Color, point: Vector3) {
    distance := -origin.y / direction.y
    x := origin.x + direction.x * distance
    z := origin.z + direction.z * distance

    if math.mod(abs(math.floor(x)), 2) == math.mod(abs(math.floor(z)), 2) {
        color = Color{1, 0, 0}
    } else {
        color = Color{1, 1, 1}
    }

    point = {x, 0, z}
    return
}

get_sky_color :: proc(direction: Vector3) -> Color {
    return Color{0.7, 0.6, 1.0} * math.pow(1 - direction.y, 2)
}

Scene :: struct {
    spheres:   []Sphere,
    triangles: []Triangle,
    ground:    Plane,
    light:     Light,
}

scene_trace_all :: proc(scene: ^Scene, ray: Ray) -> (trace: Trace_Info, object: Object) {
    trace = Trace_Info {
        distance = math.F64_MAX,
    }
    object = nil
    for triangle in scene.triangles {
        trace_info: Trace_Info
        if trace_ray_triangle(&trace_info, ray, triangle) && trace_info.distance < trace.distance {
            trace = trace_info
            object = triangle
        }
    }
    for sphere in scene.spheres {
        trace_info: Trace_Info
        if trace_ray_sphere(&trace_info, ray, sphere) && trace_info.distance < trace.distance {
            trace = trace_info
            object = sphere
        }
    }
    {
        trace_info: Trace_Info
        if trace_ray_plane(&trace_info, ray, scene.ground) && trace_info.distance < trace.distance {
            trace = trace_info
            object = scene.ground
        }
    }

    return
}

scene_trace_any :: proc(scene: ^Scene, ray: Ray) -> bool {
    trace_info: Trace_Info
    for triangle in scene.triangles {
        if trace_ray_triangle(&trace_info, ray, triangle) {
            return true
        }
    }
    for sphere in scene.spheres {
        if trace_ray_sphere(&trace_info, ray, sphere) {
            return true
        }
    }
    return trace_ray_plane(&trace_info, ray, scene.ground)
}

rand_offset :: proc() -> f64 {
    return rand.float64_range(-0.5, 0.5)
}

Render_Pixel_Job :: struct {
    pool:         ^thread.Pool,
    stride:       int,
    size:         int,
    offset:       int,
    bounces:      int,
    samples:      int,
    color_buffer: []Color,
    scene:        ^Scene,
}

render_pixel_color :: proc(step_size: f64, x, y: int, bounces: int, samples: int, scene: ^Scene) -> Color {
    average_color: Color
    for _ in 0 ..< samples {
        ray := Ray {
            origin    = Vector3{0, 1, -4},
            direction = linalg.normalize(
                Vector3{step_size * (f64(x) - 0.5 + rand_offset()), step_size * (f64(y) - 0.5 + rand_offset()), 1},
            ),
        }

        final_color: Color
        ray_energy: f64 = 1.0

        for _ in 0 ..< bounces {
            nearest_trace, nearest_object := scene_trace_all(scene, ray)

            random_light_offset := Vector3{rand_offset(), rand_offset(), rand_offset()} * scene.light.radius
            light_origin := scene.light.origin + random_light_offset

            // before we shade, determine if the point has line of sight of the scene light 
            point_is_lit := !scene_trace_any(
                scene,
                Ray{origin = nearest_trace.point, direction = linalg.normalize(light_origin - nearest_trace.point)},
            )

            color: Color
            reflective := 0.0
            if nearest_object == nil {
                color = get_sky_color(ray.direction)
            } else {
                reflective = nearest_trace.material.reflective
                ray.origin = nearest_trace.point
                ray.direction = nearest_trace.bounce_direction

                // compute phong lighting objects
                ambient_light := 0.3
                color = nearest_trace.material.color * ambient_light

                if point_is_lit {
                    diffuse_light := max(
                        0.0,
                        linalg.dot(nearest_trace.normal, linalg.normalize(light_origin - nearest_trace.point)),
                    )
                    specular_light := max(
                        0,
                        linalg.dot(linalg.normalize(light_origin - nearest_trace.point), ray.direction),
                    )
                    color += nearest_trace.material.color * diffuse_light * nearest_trace.material.diffuse
                    color +=
                        scene.light.color *
                        math.pow(specular_light, nearest_trace.material.hardness) *
                        nearest_trace.material.specular
                }
            }

            final_color += color * ray_energy * (1.0 - reflective)
            ray_energy *= reflective
            if ray_energy <= math.F64_EPSILON {
                break
            }
        }

        average_color += final_color
    }

    return average_color / f64(samples)
}

render_pixel_task :: proc(task: thread.Task) {
    job := transmute(^Render_Pixel_Job)task.data
    idx := task.user_index
    for idx < len(job.color_buffer) {
        view_x := job.offset - (idx % job.size)
        view_y := (idx / job.size) - job.offset
        job.color_buffer[len(job.color_buffer) - idx - 1] = render_pixel_color(
            0.002,
            view_x,
            view_y,
            job.bounces,
            job.samples,
            job.scene,
        )
        idx += job.stride
    }
}

main :: proc() {
    scene := Scene {
        spheres = []Sphere {
            Sphere{reflective = 0.95, roughness = 0.75, origin = {1, 2, -2}, radius = 0.5},
            Sphere {
                reflective = 0.05,
                diffuse = 0.9,
                specular = 1,
                hardness = 99,
                color = {1, 0.65, 0},
                origin = {-1.25, 0.8, -2},
                radius = 0.25,
            },
        },
        triangles = []Triangle {
            make_triangle(Material{reflective = 0.8, color = {0, 0, 1}}, {-2, 0, -1}, {2, 0, -1}, {0, 3, -1.1}),
            make_triangle(Material{reflective = 0.8, color = {0, 1, 0}}, {2, 0, -5}, {-2, 0, -5}, {0, 3, -4.9}),
        },
        ground = Plane{diffuse = 0.8},
        light = Light{origin = {0, 100, -3}, color = {0.5, 0.5, 0.5}, radius = 10},
    }

    AA_SAMPLES :: 512
    BOUNCES :: 30
    SIZE :: 1440

    BUFFER_SIZE :: SIZE * SIZE
    color_buffer := make([]Color, BUFFER_SIZE)

    // 24 threads across 24 logical processors
    JOB_COUNT :: 24
    render_pixel_job := Render_Pixel_Job {
        stride       = JOB_COUNT,
        size         = SIZE,
        offset       = SIZE / 2,
        bounces      = BOUNCES,
        samples      = AA_SAMPLES,
        color_buffer = color_buffer,
        scene        = &scene,
    }

    thread_pool: thread.Pool
    thread.pool_init(&thread_pool, context.allocator, JOB_COUNT)
    for job_idx in 0 ..< JOB_COUNT {
        thread.pool_add_task(&thread_pool, context.allocator, render_pixel_task, &render_pixel_job, job_idx)
    }

    thread.pool_start(&thread_pool)
    thread.pool_finish(&thread_pool)

    sdr_buffer := make([][3]u8, BUFFER_SIZE)
    hdr_buffer := make([][3]f32, BUFFER_SIZE)
    for color, idx in color_buffer {
        // TODO: hdr-sdr tonemapping
        pixel_idx := BUFFER_SIZE - idx - 1
        sdr_buffer[idx] = [3]u8 {
            u8(math.round(math.remap_clamped(color.r, 0, 1, 0, 255))),
            u8(math.round(math.remap_clamped(color.g, 0, 1, 0, 255))),
            u8(math.round(math.remap_clamped(color.b, 0, 1, 0, 255))),
        }
        hdr_buffer[idx] = [3]f32{f32(color.r), f32(color.g), f32(color.b)}
    }

    image.write_png("test.png", SIZE, SIZE, 3, &sdr_buffer[0][0], SIZE * size_of([3]u8))
    image.write_hdr("test.hdr", SIZE, SIZE, 3, &hdr_buffer[0][0])
}
