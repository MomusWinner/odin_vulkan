package main

import ve ".."
import "base:runtime"
import sm "core:container/small_array"
import "core:log"
import "core:math"
import "core:math/rand"
import "core:time"

INSTANCE_COUNT :: 500_000

Rock_Instance :: struct {
	position: vec3,
	color:    vec3,
	scale:    f32,
}

Instancing_Scene_Data :: struct {
	cube:                   ve.Mesh,
	pipeline_h:             ve.Graphics_Pipeline,
	transform:              ve.Gfx_Transform,
	instance_vertex_buffer: ve.Buffer,
	camera:                 ve.Camera,
	model_rotation:         f32,
}

create_instancing_scene :: proc() -> Scene {
	return Scene {
		init = instancing_scene_init,
		update = instancing_scene_update,
		draw = instancing_scene_draw,
		destroy = instancing_scene_destroy,
	}
}

instancing_scene_init :: proc(s: ^Scene) {
	data := new(Instancing_Scene_Data)

	// Init Camera
	data.camera = ve.Camera {
		position = {0, 0, 2},
		target   = {0, 0, 0},
		up       = {0, 1, 0},
	}
	ve.camera_init(&data.camera)

	data.cube = ve.create_primitive_cube()
	data.pipeline_h = create_instancing_pipeline()

	// Setup Transform
	ve.init_trf(&data.transform)
	ve.trf_set_position(&data.transform, {0, -5, -5})
	ve.trf_set_scale(&data.transform, {0.2, 0.2, 0.2})

	rocks := make([]Rock_Instance, INSTANCE_COUNT)
	defer delete(rocks)
	for i in 0 ..< INSTANCE_COUNT {
		rho := rand.float32_range(30, 200)
		theta := 2 * math.PI * rand.float32()
		trf: ve.Transform
		ve.init_trf(&trf)
		ve.trf_set_position(&trf, vec3{rho * math.cos_f32(theta), rand.float32_range(-4, 4), rho * math.sin_f32(theta)})
		rocks[i] = Rock_Instance {
			position = trf.position,
			color    = {rand.float32_range(0, 1), rand.float32_range(0, 1), rand.float32_range(0, 1)},
			scale    = rand.float32_range(0.1, 0.3),
		}
	}

	data.instance_vertex_buffer = ve.create_buffer({.Vertex}, size_of(Rock_Instance) * INSTANCE_COUNT, raw_data(rocks))

	ve.cursor_disable()

	s.data = data
}

instancing_scene_update :: proc(s: ^Scene) {
	data := cast(^Instancing_Scene_Data)s.data
	data.model_rotation += ve.get_delta_time() * 0.1
	ve.trf_rotate(&data.transform, {0, 1, 0}, data.model_rotation)
	ve.camera_update_simple_controller(&data.camera)
}

instancing_scene_draw :: proc(s: ^Scene) {
	data := cast(^Instancing_Scene_Data)s.data

	ve.begin_render()
	// Begin ve.
	// --------------------------------------------------------------------------------------------------------------------

	ve.begin_draw(clear_color = {.1, .1, .1, 1})
	{
		ve.cmd_bind_vertex_buffer(data.instance_vertex_buffer, 1)
		ve.set_camera(data.camera)
		ve.draw_mesh(&data.cube, data.pipeline_h, &data.transform, instance_count = INSTANCE_COUNT)
	}
	ve.end_draw()

	// --------------------------------------------------------------------------------------------------------------------
	// End ve.
	ve.end_render()
}

instancing_scene_destroy :: proc(s: ^Scene) {
	data := cast(^Instancing_Scene_Data)s.data

	ve.destroy_buffer(data.instance_vertex_buffer)
	ve.destroy_mesh(&data.cube)

	free(data)
}

create_instancing_pipeline :: proc() -> ve.Graphics_Pipeline {
	vert_descriptions: ve.Vertex_Input_Descriptions
	sm.append(&vert_descriptions, create_default_vertex_description())
	sm.append(&vert_descriptions, _create_instance_vertex_description())

	stages := ve.Stage_Infos{}
	sm.push_back_elems(
		&stages,
		ve.Pipeline_Stage_Info{stage = .Vertex, shader_path = "assets/shaders/instancing.vert"},
		ve.Pipeline_Stage_Info{stage = .Fragment, shader_path = "assets/shaders/instancing.frag"},
	)

	create_info := ve.Create_Pipeline_Info {
		bindless = true,
		vertex_input_descriptions = vert_descriptions,
		stage_infos = stages,
		topology = .Triangle_List,
		rasterizer = {polygon_mode = .Fill, line_width = 1, cull_mode = {.Back}, front_face = .Counter_Clockwise},
		depth = {enable = true, write_enable = true, compare_op = .Less},
	}

	return ve.create_render_pipeline(create_info)
}

@(private = "file")
_create_instance_vertex_description :: proc() -> ve.Vertex_Input_Description {
	attribute_descriptions := ve.Vertex_Input_Attribute_Descriptions{}
	sm.push_back_elems(
		&attribute_descriptions,
		ve.Vertex_Input_Attribute_Description {
			location = 4,
			format = .RGB_f32,
			offset = cast(u32)offset_of(Rock_Instance, position),
		},
		ve.Vertex_Input_Attribute_Description {
			location = 5,
			format = .RGB_f32,
			offset = cast(u32)offset_of(Rock_Instance, color),
		},
		ve.Vertex_Input_Attribute_Description {
			location = 6,
			format = .R_f32,
			offset = cast(u32)offset_of(Rock_Instance, scale),
		},
	)

	return ve.Vertex_Input_Description {
		binding = 1,
		stride = size_of(Rock_Instance),
		input_rate = .Instance,
		attributes = attribute_descriptions,
	}
}
