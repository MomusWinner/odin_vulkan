package main

import ve ".."
import "base:runtime"
import "core:log"
import "core:math"
import "core:math/rand"
import "core:time"

Skybox_Scene_Data :: struct {
	cubemap:          ve.Texture,
	skybox_pipeline:  ve.Graphics_Pipeline,
	reflect_pipeline: ve.Graphics_Pipeline,
	cube:             ve.Mesh,
	trf:              ve.Transform,
	camera:           ve.Camera,
}

create_skybox_scene :: proc() -> Scene {
	return Scene {
		init = skybox_scene_init,
		update = skybox_scene_update,
		draw = skybox_scene_draw,
		destroy = skybox_scene_destroy,
	}
}

skybox_scene_init :: proc(s: ^Scene) {
	d := new(Skybox_Scene_Data)

	ve.set_cursor_mode(.Disabled)

	ve.camera_init(&d.camera)
	d.camera.position = {0, 0, 2}

	d.cube = ve.create_primitive_cube()
	d.cubemap = ve.load_cubemap_texture(
		{
			"examples/assets/skybox/posx.jpg",
			"examples/assets/skybox/negx.jpg",
			"examples/assets/skybox/negy.jpg",
			"examples/assets/skybox/posy.jpg",
			"examples/assets/skybox/posz.jpg",
			"examples/assets/skybox/negz.jpg",
		},
	)

	d.skybox_pipeline = create_skybox_pipeline()
	d.reflect_pipeline = create_reflect_pipeline()

	ve.init_trf(&d.trf)
	ve.trf_set_position(&d.trf, {0, -0.5, -1})
	ve.trf_set_scale(&d.trf, {0.5, 0.5, 0.5})

	s.data = d
}

skybox_scene_update :: proc(s: ^Scene) {
	d := cast(^Skybox_Scene_Data)s.data
	ve.camera_update_simple_controller(&d.camera)
}

skybox_scene_draw :: proc(s: ^Scene) {
	d := cast(^Skybox_Scene_Data)s.data

	ve.begin_pass()

	ve.begin_draw()
	{
		ve.set_camera(d.camera)
		// Skybox
		ve.draw_mesh(&d.cube, d.skybox_pipeline, handles = {h0 = d.cubemap})
		// Diamond
		ve.draw_mesh(&d.cube, d.reflect_pipeline, ve.trf_get_matrix(d.trf), {h0 = d.cubemap})
	}
	ve.end_draw()

	ve.end_pass()
}

skybox_scene_destroy :: proc(s: ^Scene) {
	d := cast(^Skybox_Scene_Data)s.data
	ve.destroy_mesh(&d.cube)
	free(d)
}
