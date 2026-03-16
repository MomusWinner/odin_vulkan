package main

import ve ".."
import "base:runtime"
import "core:log"
import "core:math"
import "core:math/rand"
import "core:time"

Skybox_Scene_Data :: struct {
	cubemap_h:        ve.Texture_Handle,
	skybox_material:  ve.Material_Handle,
	reflect_material: ve.Material_Handle,
	cube:             ve.Mesh,
	transform:        ve.Gfx_Transform,
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
	data := new(Skybox_Scene_Data)

	// Init Camera
	data.camera = ve.Camera {
		position = {0, 0, 2},
		target   = {0, 0, 0},
		up       = {0, 1, 0},
	}
	ve.camera_init(&data.camera)
	ve.cursor_disable()

	// Load Model
	data.cube = ve.create_primitive_cube()
	data.cubemap_h = ve.load_cubemap_texture(
		{
			"assets/skybox/posx.jpg",
			"assets/skybox/negx.jpg",
			"assets/skybox/negy.jpg",
			"assets/skybox/posy.jpg",
			"assets/skybox/posz.jpg",
			"assets/skybox/negz.jpg",
		},
	)

	pipeline_h := create_skybox_pipeline()

	// Setup Material
	data.skybox_material = ve.create_mtrl_base(pipeline_h)
	skybox_material, _ := ve.get_material(data.skybox_material)
	ve.mtrl_base_set_texture(skybox_material, data.cubemap_h)

	reflect_pipeline_h := create_reflect_pipeline()
	data.reflect_material = ve.create_mtrl_base(reflect_pipeline_h)
	reflect_material, _ := ve.get_material(data.reflect_material)
	ve.mtrl_base_set_texture(reflect_material, data.cubemap_h)

	// Setup Transform
	ve.init_trf(&data.transform)
	ve.trf_set_position(&data.transform, {0, -0.5, -1})
	ve.trf_set_scale(&data.transform, {0.5, 0.5, 0.5})

	s.data = data
}

skybox_scene_update :: proc(s: ^Scene) {
	data := cast(^Skybox_Scene_Data)s.data

	ve.camera_update_simple_controller(&data.camera)
}

skybox_scene_draw :: proc(s: ^Scene) {
	data := cast(^Skybox_Scene_Data)s.data

	skybox_mtrl, _ := ve.get_material(data.skybox_material)
	reflect_mtrl, _ := ve.get_material(data.reflect_material)

	ve.begin_render()
	// Begin ve.
	// --------------------------------------------------------------------------------------------------------------------

	ve.begin_draw()
	{
		// Skybox
		ve.draw_mesh(&data.cube, skybox_mtrl, &data.camera, nil)

		// Diamond
		ve.draw_mesh(&data.cube, reflect_mtrl, &data.camera, &data.transform)
	}
	ve.end_draw()

	// --------------------------------------------------------------------------------------------------------------------
	// End ve.
	ve.end_render()
}

skybox_scene_destroy :: proc(s: ^Scene) {
	data := cast(^Skybox_Scene_Data)s.data

	ve.destroy_mesh(&data.cube)
	ve.destroy_texture_h(data.cubemap_h)

	free(data)
}
