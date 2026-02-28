package main

import ve ".."
import "base:runtime"
import "core:log"
import "core:math"
import "core:math/rand"
import "core:time"

@(material)
Postprocessing_Material :: struct {
	texture: ve.Texture_Handle,
	width:   f32,
	height:  f32,
}

Postprocessing_Scene_Data :: struct {
	model:          ve.Model,
	square:         ve.Mesh,
	model_material: ve.Material_Handle,
	texture_h:      ve.Texture_Handle,
	pipeline_h:     ve.Render_Pipeline_Handle,
	transform:      ve.Gfx_Transform,
	camera:         ve.Camera,
	surface_h:      ve.Surface_Handle,
	postproc_mtrl:  ve.Material_Handle,
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
	data.model = ve.load_model("./assets/room.obj")
	data.square = ve.create_primitive_square()
	data.pipeline_h = create_default_pipeline()

	// Setup Material
	data.model_material = ve.create_mtrl_base(data.pipeline_h)
	model_material, _ := ve.get_material(data.model_material)
	ve.mtrl_base_set_texture(model_material, data.texture_h)
	append(&data.model.materials, data.model_material)
	append(&data.model.mesh_material, 0)

	// Setup Transform
	ve.init_trf(&data.transform)
	ve.trf_set_position(&data.transform, {0, -0.5, -1})
	ve.trf_rotate(&data.transform, {0, 1, 0}, -3.14 / 2)
	ve.trf_set_scale(&data.transform, 1)

	postprocessing_pipeline_h := create_postprocessing_pipeline()
	pipe, ok_p_ := ve.get_render_pipeline(postprocessing_pipeline_h)

	// Setup Postprocessing Surface
	data.postproc_mtrl = create_mtrl_postprocessing(postprocessing_pipeline_h)
	postproc_mtrl, _ := ve.get_material(data.postproc_mtrl)

	data.surface_h = ve.create_surface_fit_screen(._4)
	surface, ok := ve.get_surface(data.surface_h)
	assert(ok)
	mtrl_postprocessing_set_texture(
		postproc_mtrl,
		ve.surface_add_color_attachment(surface, clear_value = {.01, .01, .01, 1.0}),
	)
	ve.surface_add_depth_attachment(surface)

	s.data = data
}

postprocessing_scene_update :: proc(s: ^Scene) {
	data := cast(^Postprocessing_Scene_Data)s.data
}

postprocessing_scene_draw :: proc(s: ^Scene) {
	data := cast(^Postprocessing_Scene_Data)s.data

	pipeline, p_ok := ve.get_render_pipeline(data.pipeline_h)
	assert(p_ok)

	frame := ve.begin_render()
	// Begin ve.
	// --------------------------------------------------------------------------------------------------------------------
	postproc_mtrl, _ := ve.get_material(data.postproc_mtrl)

	mtrl_postprocessing_set_width(postproc_mtrl, cast(f32)ve.get_screen_width())
	mtrl_postprocessing_set_height(postproc_mtrl, cast(f32)ve.get_screen_height())

	surface, ok := ve.get_surface(data.surface_h)
	assert(ok)

	surface_frame := ve.begin_surface(surface, frame)
	{
		ve.draw_model(surface_frame, data.model, &data.camera, &data.transform)
	}
	ve.end_surface(surface, surface_frame)

	f := ve.begin_draw(frame)
	{
		ve.draw_mesh(f, &data.square, postproc_mtrl, &data.camera, nil)
	}
	ve.end_draw(f)

	// --------------------------------------------------------------------------------------------------------------------
	// End ve.
	ve.end_render(frame)
}

postprocessing_scene_destroy :: proc(s: ^Scene) {
	data := cast(^Postprocessing_Scene_Data)s.data

	ve.destroy_texture_h(data.texture_h)
	ve.destroy_model(&data.model)
	ve.destroy_surface(data.surface_h)

	free(data)
}
