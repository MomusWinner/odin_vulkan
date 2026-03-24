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
	mesh:            ve.Mesh,
	time_ubo_h:      ve.Uniform_Buffer,
	transform:       ve.Transform,
	pipeline_h:      ve.Graphics_Pipeline,
	sbo_h:           ve.Storage_Buffer,
	comp_pipeline_h: ve.Compute_Pipeline,
	model_rotation:  f32,
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
	data := new(Compute_Scene_Data)

	data.pipeline_h = create_particle_pipeline()

	ve.init_trf(&data.transform)
	ve.trf_set_position(&data.transform, {0, -0.5, -1})
	ve.trf_set_scale(&data.transform, {0.5, 0.5, 0.5})

	particles := generate_particlls(context.temp_allocator)

	data.sbo_h = create_sbo_particle({.Storage, .Vertex, .Host_Read, .Host_Write})
	sbo_particle_set_particles(data.sbo_h, particles[:])
	vbo := ve.sbo_get_buffer(data.sbo_h)

	data.mesh = ve.Mesh {
		vbo          = vbo,
		vertex_count = PARTICLE_COUNT,
	}

	// Setup Compute
	data.time_ubo_h = create_ubo_delta_time()
	data.comp_pipeline_h = create_compute_pipeline(INVOCATION_SIZE)

	s.data = data
}

compute_scene_update :: proc(s: ^Scene) {
	data := cast(^Compute_Scene_Data)s.data

	ubo_delta_time_set_delta_time(data.time_ubo_h, ve.get_delta_time())
}

compute_scene_draw :: proc(s: ^Scene) {
	data := cast(^Compute_Scene_Data)s.data

	b := ve.sbo_get_buffer(data.sbo_h)

	ve.begin_render()
	// Begin ve.
	// --------------------------------------------------------------------------------------------------------------------

	ve.cmd_dispatch(data.comp_pipeline_h, b, {GROUP_COUNT, 1, 1}, handles = {h0 = data.sbo_h, h1 = data.time_ubo_h})

	ve.begin_draw()
	{
		ve.draw_mesh(&data.mesh, data.pipeline_h, {})
	}
	ve.end_draw()

	// --------------------------------------------------------------------------------------------------------------------
	// End ve.
	ve.end_render()
}

compute_scene_destroy :: proc(s: ^Scene) {
	data := cast(^Compute_Scene_Data)s.data

	free(data)
}

generate_particlls :: proc(allocator := context.allocator) -> []Particle {
	rand.reset(30)
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

create_particle_vertex_description :: proc() -> ve.Vertex_Input_Description {
	attribute_descriptions := ve.Vertex_Input_Attribute_Descriptions{}
	sm.push_back_elems(
		&attribute_descriptions,
		ve.Vertex_Input_Attribute_Description {
			location = 0,
			format = .RG_f32,
			offset = cast(u32)offset_of(std430_Particle, position),
		},
		ve.Vertex_Input_Attribute_Description {
			location = 1,
			format = .RG_f32,
			offset = cast(u32)offset_of(std430_Particle, velocity),
		},
	)

	return ve.Vertex_Input_Description {
		binding = 0,
		stride = size_of(std430_Particle),
		input_rate = .Vertex,
		attributes = attribute_descriptions,
	}
}

create_particle_pipeline :: proc() -> ve.Graphics_Pipeline {
	stages := ve.Stage_Infos{}
	sm.push_back_elems(
		&stages,
		ve.Pipeline_Stage_Info{stage = .Vertex, shader_path = "examples/assets/shaders/particle.vert"},
		ve.Pipeline_Stage_Info{stage = .Fragment, shader_path = "examples/assets/shaders/particle.frag"},
	)

	vert_descriptions: ve.Vertex_Input_Descriptions
	sm.append(&vert_descriptions, create_particle_vertex_description())

	create_info := get_base_create_pipeline_info()
	create_info.stage_infos = stages
	create_info.vertex_input_descriptions = vert_descriptions
	create_info.topology = .Point_List
	create_info.rasterizer.cull_mode = {}
	create_info.depth.enable = false

	return ve.create_graphics_pipeline(create_info)
}

create_compute_pipeline :: proc(x_invocations: i32) -> ve.Compute_Pipeline {
	consts := ve.Shader_Constants{}
	sm.append(&consts, ve.Shader_Constant{id = 0, value = {int = x_invocations}})

	info := ve.Create_Compute_Pipeline_Info {
		bindless    = true,
		shader_path = "examples/assets/shaders/particle.comp",
		consts      = consts,
	}
	handle := ve.create_compute_pipeline(info)
	return handle
}
