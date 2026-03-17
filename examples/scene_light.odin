package main

import ve ".."
import vemath "../math"
import "base:runtime"
import sm "core:container/small_array"
import "core:log"
import "core:math"
import lin "core:math/linalg/glsl"
import "core:math/noise"
import "core:time"
import "vendor:microui"

@(buffer)
Light_Data_Ubo :: struct {
	camera:    ve.Buffer_Handle,
	direction: vec3,
	color:     vec3,
	shadow:    ve.Texture_Handle,
}

@(buffer)
Light_UBO :: struct {
	diffuse:  vec3,
	ambient:  vec3,
	specular: vec3,
}

Lighting_Scene_Data :: struct {
	model:                ve.Mesh,
	ground:               ve.Mesh,
	transform:            ve.Gfx_Transform,
	ground_transform:     ve.Gfx_Transform,
	camera:               ve.Camera,
	l_camera:             ve.Camera,
	shadow_map_rt:        ve.Render_Target,
	shadow_map_view_mesh: ve.Mesh,
	shadow_map_texture:   ve.Texture_Handle,
	square_trf:           ve.Gfx_Transform,
	light_pipeline_h:     ve.Render_Pipeline_Handle,
	light_ubo:            ve.Uniform_Buffer_Handle,
	surf_draw_ubo:        ve.Uniform_Buffer_Handle,
	depth_only_pipeline:  ve.Render_Pipeline_Handle,
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

	data.depth_only_pipeline = create_depth_only_pipeline()

	// Setup Shadow Map
	ve.init_render_target(&data.shadow_map_rt, DEPTH_SIZE, DEPTH_SIZE, ._1)

	data.shadow_map_texture = ve.render_target_add_readable_depth_attachment(
		&data.shadow_map_rt,
		sampler_info = ve.Sampler_Info {
			mag_filter = .Linear,
			min_filter = .Linear,
			address_mode_u = .Clamp_To_Border,
			address_mode_v = .Clamp_To_Border,
			border_color = .Opaque_White,
		},
	)

	// Setup Material
	data.light_pipeline_h = create_light_pipeline()
	data.light_ubo = create_ubo_light()
	light_ubo, _ := ve.get_uniform_buffer(data.light_ubo)

	ubo_light_set_diffuse(light_ubo, {0.29, 0.478, 0.588})
	ubo_light_set_ambient(light_ubo, 0.1)

	data.light_data = create_ubo_light_data()
	light_data, _ := ve.get_uniform_buffer(data.light_data)

	ubo_light_data_set_camera(light_data, data.l_camera.buffer_h)
	ubo_light_data_set_direction(light_data, {0, -1, 0})
	ubo_light_data_set_shadow(light_data, data.shadow_map_texture)
	ubo_light_data_set_color(light_data, 1)

	// Load Model
	data.model = ve.load_meshes("./assets/Suzanne.obj")[0]
	data.ground = ve.create_primitive_square()

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

	depth_only_pipeline, _ := ve.get_render_pipeline(data.depth_only_pipeline)
	light_pipeline, _ := ve.get_render_pipeline(data.light_pipeline_h)

	// Begin ve.
	// --------------------------------------------------------------------------------------------------------------------

	ve.begin_render_target(&data.shadow_map_rt)
	{
		ve.draw_mesh(&data.model, depth_only_pipeline, {camera = &data.l_camera, trf = &data.transform})
		ve.draw_mesh(&data.ground, depth_only_pipeline, {camera = &data.l_camera, trf = &data.ground_transform})
	}
	ve.end_render_target(&data.shadow_map_rt)

	ve.begin_draw({0.933, 0.525, 0.899, 1})
	{
		consts := ve.Push_Constants {
			camera = &data.camera,
			trf    = &data.transform,
			h0     = data.light_ubo,
			h1     = data.light_data,
		}
		ve.draw_mesh(&data.model, light_pipeline, consts)
		consts.trf = &data.ground_transform
		ve.draw_mesh(&data.ground, light_pipeline, consts)
	}
	ve.end_draw()

	// --------------------------------------------------------------------------------------------------------------------
	// End ve.
	ve.end_render()
}

light_scene_destroy :: proc(s: ^Scene) {
	data := cast(^Lighting_Scene_Data)s.data

	ve.destroy_render_target(&data.shadow_map_rt)
	ve.destroy_mesh(&data.model)
	ve.destroy_mesh(&data.shadow_map_view_mesh)
	ve.destroy_mesh(&data.ground)

	free(data)
}

create_light_pipeline :: proc() -> ve.Render_Pipeline_Handle {
	stages := ve.Stage_Infos{}
	sm.push_back_elems(
		&stages,
		ve.Pipeline_Stage_Info{stage = .Vertex, shader_path = "assets/shaders/light.vert"},
		ve.Pipeline_Stage_Info{stage = .Fragment, shader_path = "assets/shaders/light.frag"},
	)

	create_info := get_base_create_pipeline_info()
	create_info.stage_infos = stages

	return ve.create_render_pipeline(create_info)
}

create_depth_only_pipeline :: proc() -> ve.Render_Pipeline_Handle {
	vert_descriptions: ve.Vertex_Input_Descriptions
	sm.append(&vert_descriptions, create_default_vertex_description())

	set_infos := ve.Pipeline_Set_Layout_Infos{}
	sm.push_back(&set_infos, ve.get_bindless_pipeline_set_info())

	stages := ve.Stage_Infos{}
	sm.push_back_elems(&stages, ve.Pipeline_Stage_Info{stage = .Vertex, shader_path = "assets/shaders/light.vert"})

	create_info := get_base_create_pipeline_info()
	create_info.stage_infos = stages
	create_info.depth.bias = {
		enable          = true,
		constant_factor = 1.25,
		clamp           = 0,
		slope_factor    = 4.75,
	}

	return ve.create_render_pipeline(create_info)
}
