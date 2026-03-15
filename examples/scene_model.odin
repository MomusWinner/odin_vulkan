package main

import ve ".."
import "base:runtime"
import "core:log"
import "core:math"
import "core:math/rand"
import "core:time"

Model_Scene_Data :: struct {
	texture_h:      ve.Texture_Handle,
	model:          ve.Model,
	material:       ve.Material_Handle,
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
	data.model = ve.load_model("./assets/room.obj")
	pipeline_h := create_default_pipeline()

	// Setup Material
	data.material = ve.create_mtrl_base(pipeline_h)
	material, _ := ve.get_material(data.material)
	ve.mtrl_base_set_texture(material, data.texture_h)
	append(&data.model.materials, data.material)
	append(&data.model.mesh_material, 0)

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

	frame := ve.begin_render()
	// Begin ve.
	// --------------------------------------------------------------------------------------------------------------------

	base_frame := ve.begin_draw(frame)
	{
		ve.draw_model(base_frame, data.model, &data.camera, &data.transform)
	}
	ve.end_draw(frame)

	// --------------------------------------------------------------------------------------------------------------------
	// End ve.
	ve.end_render(frame)
}

model_scene_destroy :: proc(s: ^Scene) {
	data := cast(^Model_Scene_Data)s.data

	ve.destroy_texture_h(data.texture_h)
	ve.destroy_model(&data.model)

	free(data)
}
