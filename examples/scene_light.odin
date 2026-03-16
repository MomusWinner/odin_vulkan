package main

import ve ".."
import vemath "../math"
import "base:runtime"
import "core:log"
import "core:math"
import lin "core:math/linalg/glsl"
import "core:math/noise"
import "core:time"
import "vendor:microui"

@(buffer)
Light_Ubo :: struct {
	camera:    ve.Buffer_Handle,
	direction: vec3,
	color:     vec3,
	shadow:    ve.Texture_Handle,
}

@(material)
Light_Material :: struct {
	diffuse:  vec3,
	ambient:  vec3,
	specular: vec3,
}

Lighting_Scene_Data :: struct {
	model:                ve.Model,
	ground:               ve.Model,
	transform:            ve.Gfx_Transform,
	ground_transform:     ve.Gfx_Transform,
	camera:               ve.Camera,
	l_camera:             ve.Camera,
	shadow_map_surf:      ve.Surface_Handle,
	shadow_map_view_mesh: ve.Mesh,
	shadow_map_texture:   ve.Texture_Handle,
	surf_draw_mat:        ve.Material_Handle,
	depth_only_mtrl:      ve.Material_Handle,
	square_trf:           ve.Gfx_Transform,
	light_data:           ve.Uniform_Buffer_Handle,
}

DEPTH_SIZE :: 1024 * 2

create_light_scene :: proc() -> Scene {
	return Scene {
		init = light_scene_init,
		update = light_scene_update,
		draw = light_scene_draw,
		destroy = light_scene_destroy,
	}
}

light_scene_init :: proc(s: ^Scene) {
	log.info(ve.get_limits())
	data := new(Lighting_Scene_Data)

	// Init Camera
	data.camera = ve.Camera{}
	ve.camera_init(&data.camera)
	data.camera.position = {0, 2, 8}
	data.camera.target = {0, 0, 0}
	data.camera.up = {0, 1, 0}

	data.l_camera = ve.Camera{}
	ve.camera_init(&data.l_camera, .Orthographic)
	data.l_camera.position = {0.0001, 7, 0.0}
	data.l_camera.target = {0, 0, 0}
	data.l_camera.up = {0, 1, 0}
	data.l_camera.near = 1.0
	data.l_camera.far = 40.5
	data.l_camera.fov = 10

	// Setup Shadow Map
	data.shadow_map_surf = ve.create_surface_with_size(DEPTH_SIZE, DEPTH_SIZE, ._1)
	surface, _ := ve.get_surface(data.shadow_map_surf)

	data.shadow_map_texture = ve.surface_add_readable_depth_attachment(
		surface,
		sampler_info = ve.Sampler_Info {
			mag_filter = .Linear,
			min_filter = .Linear,
			address_mode_u = .Clamp_To_Border,
			address_mode_v = .Clamp_To_Border,
			border_color = .Opaque_White,
		},
	)

	data.light_data = create_ubo_light()
	light_data, _ := ve.get_uniform_buffer(data.light_data)

	// Setup Material
	pipeline_h := create_light_pipeline()
	light_material_h := create_mtrl_light(pipeline_h)
	light_material, _ := ve.get_material(light_material_h)

	mtrl_light_set_diffuse(light_material, {0.29, 0.478, 0.588})
	mtrl_light_set_ambient(light_material, 0.1)

	ubo_light_set_camera(light_data, data.l_camera.buffer_h)
	ubo_light_set_direction(light_data, {0, -1, 0})
	ubo_light_set_shadow(light_data, data.shadow_map_texture)
	ubo_light_set_color(light_data, 1)
	assert(ve.g_resource_set_slot(0, light_data.buffer_h))

	data.depth_only_mtrl = ve.create_mtrl_empty(create_depth_only_pipeline())

	// Load Model
	data.model = ve.load_model("./assets/Suzanne.obj")
	ve.model_set_material(&data.model, light_material_h)

	data.ground = ve.create_model(make([]ve.Mesh, 1), make([dynamic]ve.Material_Handle), make([dynamic]int))
	data.ground.meshes[0] = ve.create_primitive_square()
	append(&data.ground.mesh_material, 0)
	append(&data.ground.materials, light_material_h)

	// Setup Transform
	ve.init_trf(&data.transform)
	ve.trf_set_position(&data.transform, {0, 1, 0})

	ve.init_trf(&data.ground_transform)
	ve.trf_set_position(&data.ground_transform, {0, 0, 0})
	ve.trf_set_scale(&data.ground_transform, 100)
	ve.trf_rotate(&data.ground_transform, {1, 0, 0}, 3.14 / 2)

	ve.init_trf(&data.square_trf)
	ve.trf_set_position(&data.square_trf, {-0.7, -0.7, 0})
	ve.trf_set_scale(&data.square_trf, 0.3)

	data.shadow_map_view_mesh = ve.create_primitive_square(0.5)

	postprocessing_pipeline_h := create_depth_pipeline()
	pipe, ok_p_ := ve.get_render_pipeline(postprocessing_pipeline_h)

	// Setup Postprocessing Surface
	data.surf_draw_mat = create_mtrl_postprocessing(postprocessing_pipeline_h)
	surf_draw_mat, _ := ve.get_material(data.surf_draw_mat)
	mtrl_postprocessing_set_texture(surf_draw_mat, data.shadow_map_texture)

	s.data = data
}

light_scene_update :: proc(s: ^Scene) {
	data := cast(^Lighting_Scene_Data)s.data

	speed: f32 = 2.0
	camera: ^ve.Camera
	camera = &data.l_camera

	if ve.is_key_down(.Up) {
		camera.position.z += ve.get_delta_time() * speed
	}
	if ve.is_key_down(.Down) {
		camera.position.z -= ve.get_delta_time() * speed
	}
	if ve.is_key_down(.Left) {
		camera.position.x += ve.get_delta_time() * speed
	}
	if ve.is_key_down(.Right) {
		camera.position.x -= ve.get_delta_time() * speed
	}
	camera.dirty = true

	ve.cursor_disable()
	ve.camera_update_simple_controller(&data.camera)
}

light_scene_draw :: proc(s: ^Scene) {
	data := cast(^Lighting_Scene_Data)s.data

	ve.begin_render()
	surf, _ := ve.get_surface(data.shadow_map_surf)
	surf_draw_mat, _ := ve.get_material(data.surf_draw_mat)
	depth_only_mtrl, m_ok := ve.get_material(data.depth_only_mtrl)
	assert(m_ok)

	// Begin ve.
	// --------------------------------------------------------------------------------------------------------------------

	ve.begin_surface(surf)
	{
		ve.draw_model_solid(data.model, &data.l_camera, &data.transform, depth_only_mtrl)
		ve.draw_model_solid(data.ground, &data.l_camera, &data.ground_transform, depth_only_mtrl)
	}
	ve.end_surface(surf)

	ve.begin_draw({0.933, 0.525, 0.899, 1})
	{
		ve.draw_model(data.model, &data.camera, &data.transform)
		ve.draw_model(data.ground, &data.camera, &data.ground_transform)
		// ve.draw_square(&data.square_trf, &data.camera, surf_draw_mat) // FIXME:
	}
	ve.end_draw()

	// --------------------------------------------------------------------------------------------------------------------
	// End ve.
	ve.end_render()
}

light_scene_destroy :: proc(s: ^Scene) {
	data := cast(^Lighting_Scene_Data)s.data

	ve.destroy_model(&data.model)
	ve.destroy_mesh(&data.shadow_map_view_mesh)
	ve.destroy_model(&data.ground)

	free(data)
}
