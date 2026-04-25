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
	texture: ve.Texture,
	width:   f32,
	height:  f32,
}

Postprocessing_Scene_Data :: struct {
	camera:             ve.Camera,
	model:              ve.Mesh,
	texture:            ve.Texture,
	ubo:                ve.Uniform_Buffer,
	trf:                ve.Transform,
	pipeline:           ve.Graphics_Pipeline,
	square:             ve.Mesh,
	rt:                 ve.Render_Target,
	postprocessing_ubo: ve.Uniform_Buffer,
	postproc_pipeline:  ve.Graphics_Pipeline,
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
	d := new(Postprocessing_Scene_Data)

	ve.init_camera(&d.camera)
	d.camera.position = {0, 0, 2}

	d.texture = ve.load_texture("examples/assets/room.png")
	d.model = ve.load_obj("examples/assets/room.obj", context.temp_allocator)[0]
	d.square = ve.create_primitive_square()
	d.pipeline = create_default_pipeline()

	d.ubo = create_ubo_base()
	ubo_base_set_texture(d.ubo, d.texture)

	ve.init_trf(&d.trf)
	ve.trf_set_position(&d.trf, {0, -0.5, -1})
	ve.trf_rotate(&d.trf, {0, 1, 0}, -3.14 / 2)
	ve.trf_set_scale(&d.trf, 1)

	ve.init_render_target(&d.rt, ve.screen_get_width(), ve.screen_get_height(), ._4)
	color_attachment := ve.render_target_add_color_attachment(&d.rt, clear_value = {.01, .01, .01, 1.0})
	ve.render_target_add_depth_attachment(&d.rt)

	d.postproc_pipeline = create_postprocessing_pipeline()
	d.postprocessing_ubo = create_ubo_postprocessing()
	ubo_postprocessing_set_texture(d.postprocessing_ubo, color_attachment)

	s.data = d
}

postprocessing_scene_update :: proc(s: ^Scene) {}

postprocessing_scene_draw :: proc(s: ^Scene) {
	d := cast(^Postprocessing_Scene_Data)s.data

	ubo_postprocessing_set_width(d.postprocessing_ubo, cast(f32)ve.screen_get_width())
	ubo_postprocessing_set_height(d.postprocessing_ubo, cast(f32)ve.screen_get_height())

	if (ve.screen_resized()) {
		ve.render_target_resize(&d.rt, ve.screen_get_width(), ve.screen_get_height())
	}

	ve.begin_pass()

	ve.set_camera(d.camera)

	ve.begin_render_target(&d.rt)
	{
		ve.draw_mesh(d.model, d.pipeline, ve.trf_get_matrix(d.trf), {h0 = d.ubo})
	}
	ve.end_render_target(&d.rt)

	ve.begin_draw()
	{
		ve.draw_mesh(d.square, d.postproc_pipeline, handles = {h0 = d.postprocessing_ubo})
	}
	ve.end_draw()

	ve.end_pass()
}

postprocessing_scene_destroy :: proc(s: ^Scene) {
	d := cast(^Postprocessing_Scene_Data)s.data

	ve.destroy_mesh(&d.model)
	ve.destroy_mesh(&d.square)
	ve.destroy_render_target(&d.rt)

	free(d)
}
