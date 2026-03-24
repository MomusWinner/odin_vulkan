package main

import ve ".."
import "base:runtime"
import sm "core:container/small_array"
import "core:log"
import "core:math"
import "core:math/linalg/glsl"
import "core:math/rand"
import "core:slice"
import "core:time"

PARTICLE_COUNT :: 100_000
INVOCATION_SIZE :: 256
GROUP_COUNT :: 1 + PARTICLE_COUNT / INVOCATION_SIZE

Particle :: struct {
	position: vec2,
	velocity: vec2,
}

@(buffer = "storage")
Particle_SBO :: struct {
	particles: [PARTICLE_COUNT]Particle,
}

@(buffer)
Delta_Time_UBO :: struct {
	delta_time: f32,
}

Compute_Scene_Data :: struct {
	mesh:             ve.Mesh,
	time_ubo:         ve.Uniform_Buffer,
	sbo:              ve.Storage_Buffer,
	pipeline:         ve.Graphics_Pipeline,
	compute_pipeline: ve.Compute_Pipeline,
}

create_compute_scene :: proc() -> Scene {
	return Scene {
		init = compute_scene_init,
		update = compute_scene_update,
		draw = compute_scene_draw,
		destroy = compute_scene_destroy,
	}
}

compute_scene_init :: proc(s: ^Scene) {
	d := new(Compute_Scene_Data)

	d.pipeline = create_particle_pipeline()

	particles := generate_particles(context.temp_allocator)

	d.sbo = create_sbo_particle({.Storage, .Vertex, .Host_Read, .Host_Write})
	sbo_particle_set_particles(d.sbo, particles[:])
	vbo := ve.sbo_get_buffer(d.sbo)

	d.mesh = ve.Mesh {
		vbo          = vbo,
		vertex_count = PARTICLE_COUNT,
	}

	d.time_ubo = create_ubo_delta_time()
	d.compute_pipeline = create_compute_pipeline(INVOCATION_SIZE)

	s.data = d
}

compute_scene_update :: proc(s: ^Scene) {
	d := cast(^Compute_Scene_Data)s.data
	ubo_delta_time_set_delta_time(d.time_ubo, ve.get_delta_time())
}

compute_scene_draw :: proc(s: ^Scene) {
	d := cast(^Compute_Scene_Data)s.data

	b := ve.sbo_get_buffer(d.sbo)

	ve.begin_pass()

	ve.cmd_dispatch(d.compute_pipeline, b, {GROUP_COUNT, 1, 1}, handles = {h0 = d.sbo, h1 = d.time_ubo})

	ve.begin_draw()
	{
		ve.draw_mesh(&d.mesh, d.pipeline, {})
	}
	ve.end_draw()

	ve.end_pass()
}

compute_scene_destroy :: proc(s: ^Scene) {
	d := cast(^Compute_Scene_Data)s.data
	free(d)
}

generate_particles :: proc(allocator := context.allocator) -> []Particle {
	particles := make([]Particle, PARTICLE_COUNT, allocator)

	for &particle in particles {
		r: f32 = rand.float32_range(0.0, 0.02)
		theta := cast(f32)rand.float32() * 2 * math.PI
		x := r * math.cos(theta)
		y := r * math.sin(theta)
		particle.position = vec2{x, y}
		particle.velocity = glsl.normalize(particle.position) * rand.float32_range(0.3, 1.3)
	}

	return particles
}
