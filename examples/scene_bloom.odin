package main

import ve ".."
import "core:log"
import "core:math"
import "core:math/rand"

CUBE_COUNT :: 16
LIGHT_COUNT :: 4

Light :: struct {
	color:    vec3,
	position: vec3,
}

@(buffer)
Multilight_UBO :: struct {
	lights: [LIGHT_COUNT]Light,
	color:  vec3,
}

@(buffer)
HDR_UBO :: struct {
	exposure: f32,
	scene:    ve.Texture,
	bloom:    ve.Texture,
}

@(buffer)
Gaussian_Blur_UBO :: struct {
	blur: ve.Texture,
}

@(buffer)
Light_Source_UBO :: struct {
	color: vec3,
}

Light_Source :: struct {
	trf:     ve.Transform,
	box_ubo: ve.Uniform_Buffer,
}

Bloom_Scene_Data :: struct {
	camera:                ve.Camera,
	square:                ve.Mesh,
	cube:                  ve.Mesh,
	cube_trfs:             [CUBE_COUNT]ve.Transform,
	light_sources:         [LIGHT_COUNT]Light_Source,
	rt:                    ve.Render_Target,
	// Buffers
	light_box_ubo:         ve.Uniform_Buffer,
	multilight_ubo:        ve.Uniform_Buffer,
	hdr_ubo:               ve.Uniform_Buffer,
	blur_ubo:              ve.Uniform_Buffer,
	// Pipelines
	blur_hor_pipeline:     ve.Graphics_Pipeline,
	blur_ver_pipeline:     ve.Graphics_Pipeline,
	multilight_pipeline:   ve.Graphics_Pipeline,
	hdr_pipeline:          ve.Graphics_Pipeline,
	light_source_pipeline: ve.Graphics_Pipeline,
}

create_bloom_scene :: proc() -> Scene {
	return Scene {
		init = bloom_scene_init,
		update = bloom_scene_update,
		draw = bloom_scene_draw,
		destroy = bloom_scene_destroy,
	}
}

bloom_scene_init :: proc(s: ^Scene) {
	d := new(Bloom_Scene_Data)

	ve.cursor_set_mode(.Disabled)

	ve.init_camera(&d.camera)
	d.camera.position = {0, 0, 2}

	ve.init_render_target(&d.rt, ve.screen_get_width(), ve.screen_get_height(), ._4)
	hdr_color_attachment := ve.render_target_add_color_attachment(&d.rt, format = .RGBA_norm_u16)
	bright_color_attachment := ve.render_target_add_color_attachment(&d.rt, format = .RGBA_norm_u16)
	ve.render_target_add_depth_attachment(&d.rt)

	d.square = ve.create_primitive_square()
	d.cube = ve.create_primitive_cube()


	d.hdr_pipeline = create_hdr_pipeline()
	d.hdr_ubo = create_ubo_hdr()
	ubo_hdr_set_scene(d.hdr_ubo, hdr_color_attachment)
	ubo_hdr_set_bloom(d.hdr_ubo, bright_color_attachment)
	ubo_hdr_set_exposure(d.hdr_ubo, 0.5)

	d.blur_hor_pipeline = create_gaussian_blur_pipeline(true)
	d.blur_ver_pipeline = create_gaussian_blur_pipeline(false)

	d.blur_ubo = create_ubo_gaussian_blur()
	ubo_gaussian_blur_set_blur(d.blur_ubo, bright_color_attachment)

	d.multilight_pipeline = create_multilight_pipeline()
	d.multilight_ubo = create_ubo_multilight()
	ubo_multilight_set_color(d.multilight_ubo, {0.5, 0.5, 0.5})

	Z :: -10
	lights: [LIGHT_COUNT]Light = {
		Light{position = {4.8, 0, Z}, color = ({1, 0, 0} * 5)},
		Light{position = {1.6, 0, Z}, color = ({0, 1, 0} * 5)},
		Light{position = {-1.6, 0, Z}, color = ({0, 0.2, 1} * 5)},
		Light{position = {-4.8, 0, Z}, color = ({1, 1, 0} * 5)},
	}
	ubo_multilight_set_lights(d.multilight_ubo, lights[:])

	for i in 0 ..< CUBE_COUNT {
		ve.init_trf(&d.cube_trfs[i])
		x: f32 = cast(f32)i - CUBE_COUNT / 2
		y := rand.float32_range(-1.5, 1.5)
		z := rand.float32_range(-1.5, 1.5) + Z
		ve.trf_set_position(&d.cube_trfs[i], {x, y, z})
		ve.trf_set_scale(&d.cube_trfs[i], rand.float32_range(0.3, 0.5))
		axis: vec3 = {rand.float32(), rand.float32(), rand.float32()}
		ve.trf_rotate(&d.cube_trfs[i], axis, rand.float32_range(-math.PI, math.PI))
	}

	d.light_source_pipeline = create_light_source_pipeline()
	for i in 0 ..< LIGHT_COUNT {
		light: Light_Source
		ve.init_trf(&light.trf)
		ve.trf_set_position(&light.trf, lights[i].position)
		ve.trf_set_scale(&light.trf, 0.3)
		light.box_ubo = create_ubo_light_source()
		ubo_light_source_set_color(light.box_ubo, lights[i].color)
		d.light_sources[i] = light
	}

	s.data = d
}

bloom_scene_update :: proc(s: ^Scene) {
	d := cast(^Bloom_Scene_Data)s.data
	ve.camera_update_simple_controller(&d.camera)

	exp := ubo_hdr_get_exposure(d.hdr_ubo)
	speed: f32 = 1.0
	if (ve.key_is_down(.Up)) {
		ubo_hdr_set_exposure(d.hdr_ubo, exp + speed * ve.time_get_delta())
	}
	if (ve.key_is_down(.Down)) {
		ubo_hdr_set_exposure(d.hdr_ubo, exp - speed * ve.time_get_delta())
	}
}

bloom_scene_draw :: proc(s: ^Scene) {
	d := cast(^Bloom_Scene_Data)s.data

	if (ve.screen_resized()) {
		ve.render_target_resize(&d.rt, ve.screen_get_width(), ve.screen_get_height())
	}

	ve.begin_pass()

	ve.set_camera(d.camera)

	ve.begin_render_target(&d.rt)
	for &t in d.cube_trfs {
		ve.draw_mesh(d.cube, d.multilight_pipeline, ve.trf_get_matrix(t), {h0 = d.multilight_ubo})
	}
	for &l in d.light_sources {
		ve.draw_mesh(d.cube, d.light_source_pipeline, ve.trf_get_matrix(l.trf), {h0 = l.box_ubo})
	}
	ve.end_render_target(&d.rt)

	for i in 0 ..< 3 {
		brightness_color_attachment := []ve.Color_Attachment_Action{{index = 1, load_op = .Load, store_op = .Store}}

		// Horizontal gaussian blur
		ve.begin_render_target(&d.rt, brightness_color_attachment)
		ve.draw_mesh(d.square, d.blur_hor_pipeline, handles = {h0 = d.blur_ubo})
		ve.end_render_target(&d.rt)

		// Vertical gaussian blur
		ve.begin_render_target(&d.rt, brightness_color_attachment)
		ve.draw_mesh(d.square, d.blur_ver_pipeline, handles = {h0 = d.blur_ubo})
		ve.end_render_target(&d.rt)
	}

	ve.begin_draw()
	{
		ve.draw_mesh(d.square, d.hdr_pipeline, handles = {h0 = d.hdr_ubo})
	}
	ve.end_draw()

	ve.end_pass()
}

bloom_scene_destroy :: proc(s: ^Scene) {
	d := cast(^Bloom_Scene_Data)s.data

	ve.destroy_render_target(&d.rt)
	ve.destroy_mesh(&d.cube)
	ve.destroy_mesh(&d.square)
	ve.destroy_camera(&d.camera)

	for l in d.light_sources {
		ve.destroy_ubo(l.box_ubo)
	}

	ve.destroy_ubo(d.light_box_ubo)
	ve.destroy_ubo(d.multilight_ubo)
	ve.destroy_ubo(d.hdr_ubo)
	ve.destroy_ubo(d.blur_ubo)

	ve.destroy_graphics_pipeline(d.blur_hor_pipeline)
	ve.destroy_graphics_pipeline(d.blur_ver_pipeline)
	ve.destroy_graphics_pipeline(d.multilight_pipeline)
	ve.destroy_graphics_pipeline(d.hdr_pipeline)
	ve.destroy_graphics_pipeline(d.light_source_pipeline)

	free(d)
}
