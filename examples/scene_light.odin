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
	camera:    ve.Buffer,
	direction: vec3,
	color:     vec3,
	shadow:    ve.Texture,
}

@(buffer)
Light_UBO :: struct {
	diffuse:  vec3,
	ambient:  vec3,
	specular: vec3,
}

Lighting_Scene_Data :: struct {
	suzanne_mesh:        ve.Mesh,
	suzanne_trf:         ve.Transform,
	ground_mesh:         ve.Mesh,
	ground_trf:          ve.Transform,
	camera:              ve.Camera,
	light_camera:        ve.Camera,
	rt:                  ve.Render_Target,
	shadow_map_texture:  ve.Texture,
	light_pipeline:      ve.Graphics_Pipeline,
	light_ubo:           ve.Uniform_Buffer,
	light_data_ubo:      ve.Uniform_Buffer,
	surf_draw_ubo:       ve.Uniform_Buffer,
	depth_only_pipeline: ve.Graphics_Pipeline,
}

DEPTH_SIZE :: 2048

create_light_scene :: proc() -> Scene {
	return Scene {
		init = light_scene_init,
		update = light_scene_update,
		draw = light_scene_draw,
		destroy = light_scene_destroy,
	}
}

light_scene_init :: proc(s: ^Scene) {
	d := new(Lighting_Scene_Data)

	ve.cursor_set_mode(.Disabled)

	ve.init_camera(&d.camera)
	d.camera.position = {0, 2, 8}

	ve.init_camera(&d.light_camera, .Orthographic)
	d.light_camera.position = {0.0001, 7, 0.0}
	d.light_camera.near = 1.0
	d.light_camera.far = 40.5
	d.light_camera.fov = 10

	d.depth_only_pipeline = create_depth_only_pipeline()

	ve.init_render_target(&d.rt, DEPTH_SIZE, DEPTH_SIZE, ._1)

	d.shadow_map_texture = ve.render_target_add_readable_depth_attachment(
		&d.rt,
		sampler_info = ve.Sampler_Info {
			mag_filter = .Linear,
			min_filter = .Linear,
			address_mode_u = .Clamp_To_Border,
			address_mode_v = .Clamp_To_Border,
			border_color = .Opaque_White,
		},
	)

	d.light_pipeline = create_light_pipeline()
	d.light_ubo = create_ubo_light()
	ubo_light_set_diffuse(d.light_ubo, {0.29, 0.478, 0.588})
	ubo_light_set_ambient(d.light_ubo, 0.1)

	d.light_data_ubo = create_ubo_light_data()
	ubo_light_data_set_camera(d.light_data_ubo, d.light_camera.buffer)
	ubo_light_data_set_direction(d.light_data_ubo, {0, -1, 0})
	ubo_light_data_set_shadow(d.light_data_ubo, d.shadow_map_texture)
	ubo_light_data_set_color(d.light_data_ubo, 1)

	d.suzanne_mesh = ve.load_meshes("examples/assets/Suzanne.obj", context.temp_allocator)[0]
	d.ground_mesh = ve.create_primitive_square()

	ve.init_trf(&d.suzanne_trf)
	ve.trf_set_position(&d.suzanne_trf, {0, 1, 0})

	ve.init_trf(&d.ground_trf)
	ve.trf_set_position(&d.ground_trf, {0, 0, 0})
	ve.trf_set_scale(&d.ground_trf, 100)
	ve.trf_rotate(&d.ground_trf, {1, 0, 0}, math.PI / 2)

	s.data = d
}

light_scene_update :: proc(s: ^Scene) {
	d := cast(^Lighting_Scene_Data)s.data

	speed: f32 = 2.0
	camera: ^ve.Camera
	camera = &d.light_camera

	if ve.key_is_down(.Up) {
		camera.position.z += ve.time_get_delta() * speed
	}
	if ve.key_is_down(.Down) {
		camera.position.z -= ve.time_get_delta() * speed
	}
	if ve.key_is_down(.Left) {
		camera.position.x += ve.time_get_delta() * speed
	}
	if ve.key_is_down(.Right) {
		camera.position.x -= ve.time_get_delta() * speed
	}

	ve.camera_update_simple_controller(&d.camera)

	if ve.key_is_pressed(.T) {
		ve.wait_render_completion()
		ve.texture_set_sampler(
			d.shadow_map_texture,
			ve.Sampler_Info {
				mag_filter = .Linear,
				min_filter = .Linear,
				address_mode_u = .Repeat,
				address_mode_v = .Repeat,
			},
		)
	}
}

light_scene_draw :: proc(s: ^Scene) {
	d := cast(^Lighting_Scene_Data)s.data

	ve.begin_pass()

	ve.begin_render_target(&d.rt)
	{
		ve.set_camera(d.light_camera)
		ve.draw_mesh(d.suzanne_mesh, d.depth_only_pipeline, ve.trf_get_matrix(d.suzanne_trf))
		ve.draw_mesh(d.ground_mesh, d.depth_only_pipeline, ve.trf_get_matrix(d.ground_trf))
	}
	ve.end_render_target(&d.rt)

	ve.begin_draw({0.933, 0.525, 0.899, 1})
	{
		ve.set_camera(d.camera)
		handles := ve.Handles {
			h0 = d.light_ubo,
			h1 = d.light_data_ubo,
		}
		ve.draw_mesh(d.suzanne_mesh, d.light_pipeline, ve.trf_get_matrix(d.suzanne_trf), handles)
		ve.draw_mesh(d.ground_mesh, d.light_pipeline, ve.trf_get_matrix(d.ground_trf), handles)
	}
	ve.end_draw()

	ve.end_pass()
}

light_scene_destroy :: proc(s: ^Scene) {
	d := cast(^Lighting_Scene_Data)s.data

	ve.destroy_render_target(&d.rt)
	ve.destroy_mesh(&d.suzanne_mesh)
	ve.destroy_mesh(&d.ground_mesh)

	free(d)
}
