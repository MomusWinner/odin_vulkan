package main

import ve ".."
import "base:runtime"
import sm "core:container/small_array"
import "core:log"
import "core:math"
import "core:math/rand"
import "core:time"

@(buffer)
Outline_UBO :: struct {
	outline_width: f32,
	color:         vec4,
}

Outline_Scene_Data :: struct {
	model:              ve.Mesh,
	outline_ubo:        ve.Uniform_Buffer,
	base_ubo:           ve.Uniform_Buffer,
	pipeline_h:         ve.Graphics_Pipeline,
	outline_pipeline_h: ve.Graphics_Pipeline,
	transform:          ve.Gfx_Transform,
	camera:             ve.Camera,
	model_rotation:     f32,
}

create_outline_scene :: proc() -> Scene {
	return Scene {
		init = outline_scene_init,
		update = outline_scene_update,
		draw = outline_scene_draw,
		destroy = outline_scene_destroy,
	}
}

outline_scene_init :: proc(s: ^Scene) {
	data := new(Outline_Scene_Data)

	// Init Camera
	data.camera = ve.Camera {
		position = {0, 0, 2},
		target   = {0, 0, 0},
		up       = {0, 1, 0},
	}
	ve.camera_init(&data.camera)

	data.model = ve.load_meshes("./examples/assets/Suzanne.obj", context.temp_allocator)[0]

	data.pipeline_h = create_outline_model_pipeline()
	data.outline_pipeline_h = create_outline_pipeline()

	data.outline_ubo = create_ubo_outline()
	ubo_outline_set_color(data.outline_ubo, {1, 0, 0, 1})
	ubo_outline_set_outline_width(data.outline_ubo, 0.025)

	data.base_ubo = ve.create_ubo_base()
	ve.ubo_base_set_color(data.base_ubo, {1, 1, 1, 1})

	// Setup Transform
	ve.init_trf(&data.transform)
	ve.trf_set_position(&data.transform, {0, 0, -1})
	ve.trf_set_scale(&data.transform, 0.5)

	s.data = data
}

outline_scene_update :: proc(s: ^Scene) {
	data := cast(^Outline_Scene_Data)s.data

	width := ubo_outline_get_outline_width(data.outline_ubo)
	speed: f32 = 0.1

	if ve.is_key_down(.W) {
		ubo_outline_set_outline_width(data.outline_ubo, width + speed * cast(f32)ve.get_delta_time())
	}
	if ve.is_key_down(.S) {
		new_width := width - speed * cast(f32)ve.get_delta_time()
		if new_width < 0 do new_width = 0
		ubo_outline_set_outline_width(data.outline_ubo, new_width)
	}
}

outline_scene_draw :: proc(s: ^Scene) {
	data := cast(^Outline_Scene_Data)s.data

	ve.begin_render()
	// Begin ve.
	// --------------------------------------------------------------------------------------------------------------------
	ve.set_camera(data.camera)

	ve.begin_draw()
	{
		ve.draw_mesh(&data.model, data.pipeline_h, &data.transform, {h0 = data.base_ubo})
		ve.draw_mesh(&data.model, data.outline_pipeline_h, &data.transform, {h0 = data.outline_ubo})
	}
	ve.end_draw()

	// --------------------------------------------------------------------------------------------------------------------
	// End ve.
	ve.end_render()
}

outline_scene_destroy :: proc(s: ^Scene) {
	data := cast(^Outline_Scene_Data)s.data

	ve.destroy_mesh(&data.model)

	free(data)
}

create_outline_model_pipeline :: proc() -> ve.Graphics_Pipeline {
	stages := ve.Stage_Infos{}
	sm.push_back_elems(
		&stages,
		ve.Pipeline_Stage_Info{stage = .Vertex, shader_path = "examples/assets/shaders/default.vert"},
		ve.Pipeline_Stage_Info{stage = .Fragment, shader_path = "examples/assets/shaders/default.frag"},
	)

	stencil_state := ve.Stencil_Op_State {
		failOp      = .Replace,
		passOp      = .Replace,
		depthFailOp = .Replace,
		compareOp   = .Always,
		compareMask = 0xff,
		writeMask   = 0xff,
		reference   = 1,
	}

	create_info := get_base_create_pipeline_info()
	create_info.stage_infos = stages
	create_info.stencil = {
		enable = true,
		front  = stencil_state,
		back   = stencil_state,
	}

	return ve.create_graphics_pipeline(create_info)
}

create_outline_pipeline :: proc() -> ve.Graphics_Pipeline {
	stages := ve.Stage_Infos{}
	sm.push_back_elems(
		&stages,
		ve.Pipeline_Stage_Info{stage = .Vertex, shader_path = "examples/assets/shaders/outline.vert"},
		ve.Pipeline_Stage_Info{stage = .Fragment, shader_path = "examples/assets/shaders/outline.frag"},
	)

	stencil_state := ve.Stencil_Op_State {
		failOp      = .Keep,
		passOp      = .Replace,
		depthFailOp = .Keep,
		compareOp   = .Not_Equal,
		compareMask = 0xff,
		writeMask   = 0xff,
		reference   = 1,
	}

	create_info := get_base_create_pipeline_info()
	create_info.stage_infos = stages
	create_info.stencil = {
		enable = true,
		front  = stencil_state,
		back   = stencil_state,
	}

	return ve.create_graphics_pipeline(create_info)
}
