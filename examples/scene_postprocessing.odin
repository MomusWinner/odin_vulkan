package main

import ve ".."
import "base:runtime"
import sm "core:container/small_array"
import "core:log"
import "core:math"
import "core:math/rand"
import "core:time"

@(buffer)
Postprocessing :: struct {
	texture: ve.Texture_Handle,
	width:   f32,
	height:  f32,
}

Postprocessing_Scene_Data :: struct {
	model:               ve.Mesh,
	square:              ve.Mesh,
	base_ubo:            ve.Uniform_Buffer_Handle,
	texture_h:           ve.Texture_Handle,
	pipeline_h:          ve.Render_Pipeline_Handle,
	transform:           ve.Gfx_Transform,
	camera:              ve.Camera,
	rt:                  ve.Render_Target,
	postproc_ubo_h:      ve.Uniform_Buffer_Handle,
	postproc_pipeline_h: ve.Render_Pipeline_Handle,
}

create_postprocessing_scene :: proc() -> Scene {
	return Scene {
		init = postprocessing_scene_init,
		update = postprocessing_scene_update,
		draw = postprocessing_scene_draw,
		destroy = postprocessing_scene_destroy,
	}
}

postprocessing_scene_init :: proc(s: ^Scene) {
	data := new(Postprocessing_Scene_Data)

	// Init Camera
	data.camera = ve.Camera {
		position = {0, 0, 2},
		target   = {0, 0, 0},
		up       = {0, 1, 0},
	}
	ve.camera_init(&data.camera)

	// Load Model
	data.texture_h = ve.load_texture("./assets/room.png")
	data.model = ve.load_meshes("./assets/room.obj", context.temp_allocator)[0]
	data.square = ve.create_primitive_square()
	data.pipeline_h = create_default_pipeline()

	// Setup Material
	data.base_ubo = ve.create_ubo_base()
	model_material, _ := ve.get_uniform_buffer(data.base_ubo)
	ve.ubo_base_set_texture(model_material, data.texture_h)

	// Setup Transform
	ve.init_trf(&data.transform)
	ve.trf_set_position(&data.transform, {0, -0.5, -1})
	ve.trf_rotate(&data.transform, {0, 1, 0}, -3.14 / 2)
	ve.trf_set_scale(&data.transform, 1)

	ve.init_render_target(&data.rt, ve.get_screen_width(), ve.get_screen_height(), ._4)
	color_attachment := ve.render_target_add_color_attachment(&data.rt, clear_value = {.01, .01, .01, 1.0})
	ve.render_target_add_depth_attachment(&data.rt)

	data.postproc_pipeline_h = create_postprocessing_pipeline()
	data.postproc_ubo_h = create_ubo_postprocessing()
	postproc_ubo, _ := ve.get_uniform_buffer(data.postproc_ubo_h)
	ubo_postprocessing_set_texture(postproc_ubo, color_attachment)

	s.data = data
}

postprocessing_scene_update :: proc(s: ^Scene) {
	data := cast(^Postprocessing_Scene_Data)s.data
}

postprocessing_scene_draw :: proc(s: ^Scene) {
	data := cast(^Postprocessing_Scene_Data)s.data

	postproc_pipeline, _ := ve.get_render_pipeline(data.postproc_pipeline_h)
	pipeline, _ := ve.get_render_pipeline(data.pipeline_h)

	ubo, _ := ve.get_uniform_buffer(data.postproc_ubo_h)
	ubo_postprocessing_set_width(ubo, cast(f32)ve.get_screen_width())
	ubo_postprocessing_set_height(ubo, cast(f32)ve.get_screen_height())

	if (ve.screen_resized()) {
		ve.render_target_resize(&data.rt, ve.get_screen_width(), ve.get_screen_height())
	}

	ve.begin_render()
	// Begin ve.
	// --------------------------------------------------------------------------------------------------------------------

	ve.begin_render_target(&data.rt)
	{
		ve.draw_mesh(&data.model, pipeline, {camera = &data.camera, trf = &data.transform, h0 = data.base_ubo})
	}
	ve.end_render_target(&data.rt)

	ve.begin_draw()
	{
		ve.draw_mesh(&data.square, postproc_pipeline, {camera = &data.camera, h0 = data.postproc_ubo_h})
	}
	ve.end_draw()

	// --------------------------------------------------------------------------------------------------------------------
	// End ve.
	ve.end_render()
}

postprocessing_scene_destroy :: proc(s: ^Scene) {
	data := cast(^Postprocessing_Scene_Data)s.data

	ve.destroy_mesh(&data.model)
	ve.destroy_mesh(&data.square)
	ve.destroy_render_target(&data.rt)

	free(data)
}

create_postprocessing_pipeline :: proc() -> ve.Render_Pipeline_Handle {
	stages := ve.Stage_Infos{}
	sm.push_back_elems(
		&stages,
		ve.Pipeline_Stage_Info{stage = .Vertex, shader_path = "assets/shaders/postprocessing.vert"},
		ve.Pipeline_Stage_Info{stage = .Fragment, shader_path = "assets/shaders/postprocessing.frag"},
	)

	create_info := get_base_create_pipeline_info()
	create_info.stage_infos = stages

	return ve.create_render_pipeline(create_info)
}
