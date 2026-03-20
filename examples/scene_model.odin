package main

import ve ".."
import "base:runtime"
import "core:log"
import "core:math"
import "core:math/rand"
import "core:time"

Model_Scene_Data :: struct {
	texture_h:      ve.Texture,
	model:          ve.Mesh,
	ubo:            ve.Uniform_Buffer,
	pipeline_h:     ve.Graphics_Pipeline,
	transform:      ve.Gfx_Transform,
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
	data := new(Model_Scene_Data)

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

	data.pipeline_h = create_default_pipeline()

	// Setup Material
	data.ubo = ve.create_ubo_base()
	ve.ubo_base_set_texture(data.ubo, data.texture_h)

	// Setup Transform
	ve.init_trf(&data.transform)
	ve.trf_set_position(&data.transform, {0, -0.5, -1})
	ve.trf_set_scale(&data.transform, 0.8)

	s.data = data
}

model_scene_update :: proc(s: ^Scene) {
	data := cast(^Model_Scene_Data)s.data
	data.model_rotation += ve.get_delta_time()
	ve.trf_rotate(&data.transform, {0, 1, 0}, data.model_rotation)
}

model_scene_draw :: proc(s: ^Scene) {
	data := cast(^Model_Scene_Data)s.data

	ve.begin_render()
	// Begin ve.
	// --------------------------------------------------------------------------------------------------------------------

	ve.begin_draw()
	{
		ve.draw_mesh(&data.model, data.pipeline_h, {trf = &data.transform, camera = &data.camera, h0 = data.ubo})
	}
	ve.end_draw()

	// --------------------------------------------------------------------------------------------------------------------
	// End ve.
	ve.end_render()
}

model_scene_destroy :: proc(s: ^Scene) {
	data := cast(^Model_Scene_Data)s.data

	ve.destroy_mesh(&data.model)

	free(data)
}
