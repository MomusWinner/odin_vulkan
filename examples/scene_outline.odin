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
	camera:           ve.Camera,
	mesh:             ve.Mesh,
	model_ubo:        ve.Uniform_Buffer,
	trf:              ve.Transform,
	pipeline:         ve.Graphics_Pipeline,
	outline_pipeline: ve.Graphics_Pipeline,
	outline_ubo:      ve.Uniform_Buffer,
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
	d := new(Outline_Scene_Data)

	ve.init_camera(&d.camera)
	d.camera.position = {0, 0, 2}

	d.mesh = ve.load_meshes("./examples/assets/Suzanne.obj", context.temp_allocator)[0]

	d.pipeline = create_outline_model_pipeline()
	d.outline_pipeline = create_outline_pipeline()

	d.outline_ubo = create_ubo_outline()
	ubo_outline_set_color(d.outline_ubo, {1, 0, 0, 1})
	ubo_outline_set_outline_width(d.outline_ubo, 0.025)

	d.model_ubo = create_ubo_base()
	ubo_base_set_color(d.model_ubo, {1, 1, 1, 1})

	ve.init_trf(&d.trf)
	ve.trf_set_position(&d.trf, {0, 0, -1})
	ve.trf_set_scale(&d.trf, 0.5)

	s.data = d
}

outline_scene_update :: proc(s: ^Scene) {
	d := cast(^Outline_Scene_Data)s.data

	width := ubo_outline_get_outline_width(d.outline_ubo)
	speed: f32 = 0.1

	if ve.key_is_down(.W) {
		ubo_outline_set_outline_width(d.outline_ubo, width + speed * cast(f32)ve.time_get_delta())
	}
	if ve.key_is_down(.S) {
		new_width := width - speed * cast(f32)ve.time_get_delta()
		if new_width < 0 do new_width = 0
		ubo_outline_set_outline_width(d.outline_ubo, new_width)
	}
}

outline_scene_draw :: proc(s: ^Scene) {
	d := cast(^Outline_Scene_Data)s.data

	ve.begin_pass()

	ve.set_camera(d.camera)

	ve.begin_draw()
	{
		ve.draw_mesh(d.mesh, d.pipeline, ve.trf_get_matrix(d.trf), {h0 = d.model_ubo})
		ve.draw_mesh(d.mesh, d.outline_pipeline, ve.trf_get_matrix(d.trf), {h0 = d.outline_ubo})
	}
	ve.end_draw()

	ve.end_pass()
}

outline_scene_destroy :: proc(s: ^Scene) {
	d := cast(^Outline_Scene_Data)s.data
	ve.destroy_mesh(&d.mesh)
	free(d)
}
