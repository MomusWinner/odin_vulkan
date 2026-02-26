package main

import ve ".."
import "base:runtime"
import "core:log"
import "core:math"
import "core:math/rand"
import "core:time"

@(material)
Outline_Material :: struct {
	outline_width: f32,
	color:         vec4,
}

Outline_Scene_Data :: struct {
	texture_h:        ve.Texture_Handle,
	model:            ve.Model,
	material:         ve.Material_Handle,
	outline_material: ve.Material_Handle,
	transform:        ve.Gfx_Transform,
	camera:           ve.Camera,
	model_rotation:   f32,
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

	// Load Model
	data.texture_h = ve.load_texture("./assets/room.png")
	data.model = ve.load_model("./assets/Suzanne.obj")

	// Setup Material
	data.material = ve.create_mtrl_base(create_outline_model_pipeline())
	data.outline_material = create_mtrl_outline(create_outline_pipeline())

	material, _ := ve.get_material(data.material)
	outline_mtrl, _ := ve.get_material(data.outline_material)

	ve.mtrl_base_set_color(material, {0.8, 0.8, 0.8, 1})
	append(&data.model.materials, data.material)
	append(&data.model.mesh_material, 0)

	mtrl_outline_set_color(outline_mtrl, {1, 0, 0, 1})
	mtrl_outline_set_outline_width(outline_mtrl, 0.025)

	// Setup Transform
	ve.init_trf(&data.transform)
	ve.trf_set_position(&data.transform, {0, 0, -1})
	ve.trf_set_scale(&data.transform, 0.5)

	s.data = data
}

outline_scene_update :: proc(s: ^Scene) {
	data := cast(^Outline_Scene_Data)s.data

	outline_mtrl, _ := ve.get_material(data.outline_material)
	width := mtrl_outline_get_outline_width(outline_mtrl^)
	speed: f32 = 0.001

	if ve.is_key_down(.W) {
		mtrl_outline_set_outline_width(outline_mtrl, width + speed * cast(f32)ve.get_total_game_time())
	}
	if ve.is_key_down(.S) {
		new_width := width - speed * cast(f32)ve.get_total_game_time()
		if new_width < 0 do new_width = 0
		mtrl_outline_set_outline_width(outline_mtrl, new_width)
	}
}

outline_scene_draw :: proc(s: ^Scene) {
	data := cast(^Outline_Scene_Data)s.data

	outline_mtrl, _ := ve.get_material(data.outline_material)

	frame := ve.begin_render()
	// Begin ve.
	// --------------------------------------------------------------------------------------------------------------------

	f := ve.begin_draw(frame)
	{
		ve.draw_model(f, data.model, &data.camera, &data.transform)
		ve.draw_model_solid(f, data.model, &data.camera, &data.transform, outline_mtrl)
	}
	ve.end_draw(frame)

	// --------------------------------------------------------------------------------------------------------------------
	// End ve.
	ve.end_render(frame)
}

outline_scene_destroy :: proc(s: ^Scene) {
	data := cast(^Outline_Scene_Data)s.data

	ve.destroy_texture_h(data.texture_h)
	ve.destroy_model(&data.model)

	free(data)
}
