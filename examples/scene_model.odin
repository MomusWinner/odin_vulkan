package main

import ve ".."
import "base:runtime"
import "core:log"
import "core:math"
import "core:math/rand"
import "core:time"

Model_Scene_Data :: struct {
	texture:        ve.Texture,
	mesh:           ve.Mesh,
	ubo:            ve.Uniform_Buffer,
	pipeline:       ve.Graphics_Pipeline,
	trf:            ve.Transform,
	camera:         ve.Camera,
	model_rotation: f32,
}

create_model_scene :: proc() -> Scene {
	return Scene {
		init = model_scene_init,
		update = model_scene_update,
		draw = model_scene_draw,
		destroy = model_scene_destroy,
	}
}

model_scene_init :: proc(s: ^Scene) {
	d := new(Model_Scene_Data)

	ve.camera_init(&d.camera)
	d.camera.position = {0, 0, 2}

	d.texture = ve.load_texture("./examples/assets/room.png")
	d.mesh = ve.load_meshes("./examples/assets/room.obj", context.temp_allocator)[0]

	d.pipeline = create_default_pipeline()

	d.ubo = create_ubo_base()
	ubo_base_set_texture(d.ubo, d.texture)

	ve.init_trf(&d.trf)
	ve.trf_set_position(&d.trf, {0, -0.5, -1})
	ve.trf_set_scale(&d.trf, 0.8)

	s.data = d
}

model_scene_update :: proc(s: ^Scene) {
	d := cast(^Model_Scene_Data)s.data
	d.model_rotation += ve.get_delta_time()
	ve.trf_rotate(&d.trf, {0, 1, 0}, d.model_rotation)
}

model_scene_draw :: proc(s: ^Scene) {
	d := cast(^Model_Scene_Data)s.data

	ve.begin_render()

	ve.begin_draw()
	{
		ve.set_camera(d.camera)
		ve.draw_mesh(&d.mesh, d.pipeline, ve.trf_get_matrix(d.trf), {h0 = d.ubo})
	}
	ve.end_draw()

	ve.end_render()
}

model_scene_destroy :: proc(s: ^Scene) {
	d := cast(^Model_Scene_Data)s.data
	ve.destroy_mesh(&d.mesh)
	free(d)
}
