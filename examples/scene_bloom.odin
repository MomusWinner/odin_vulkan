package main

import ve ".."
import "base:runtime"
import "core:log"
import "core:math"
import "core:math/rand"
import "core:time"

// This example implment tone mapping.
// Record color to HDR(hight dynamic range) and convewret it in LDR(low dynamic range).
// floating point framebuffer
// Additional information: https://learnopengl.com/Advanced-Lighting/HDR

Light :: struct {
	color:    vec3,
	position: vec3,
}

@(buffer)
Multilight_UBO :: struct {
	lights: [4]Light,
	color:  vec3,
}

@(buffer)
HDR_UBO :: struct {
	exposure: f32,
	scene:    ve.Texture_Handle,
	bloom:    ve.Texture_Handle,
}

@(buffer)
Gaussian_Blur_UBO :: struct {
	blur: ve.Texture_Handle,
}

@(buffer)
Light_Box_UBO :: struct {
	color: vec3,
}

Light_Box :: struct {
	trans:   ve.Gfx_Transform,
	box_ubo: ve.Uniform_Buffer_Handle,
}

HDR_Scene_Data :: struct {
	texture_h:             ve.Texture_Handle,
	square:                ve.Mesh,
	cube:                  ve.Mesh,
	// Buffers
	light_box_ubo_h:       ve.Uniform_Buffer_Handle,
	multilight_ubo_h:      ve.Uniform_Buffer_Handle,
	hdr_ubo_h:             ve.Uniform_Buffer_Handle,
	blur_ubo_h:            ve.Uniform_Buffer_Handle,
	// Pipelines
	blur_hor_pipeline_h:   ve.Render_Pipeline_Handle,
	blur_ver_pipeline_h:   ve.Render_Pipeline_Handle,
	multilight_pipeline_h: ve.Render_Pipeline_Handle,
	hdr_pipeline_h:        ve.Render_Pipeline_Handle,
	light_box_pipeline_h:  ve.Render_Pipeline_Handle,
	//
	transform:             ve.Gfx_Transform,
	camera:                ve.Camera,
	hdr_surface_h:         ve.Surface_Handle,
	model_rotation:        f32,
	positions:             [16]ve.Gfx_Transform,
	light_boxes:           [4]Light_Box,
}

create_hdr_scene :: proc() -> Scene {
	return Scene{init = hdr_scene_init, update = hdr_scene_update, draw = hdr_scene_draw, destroy = hdr_scene_destroy}
}

hdr_scene_init :: proc(s: ^Scene) {
	data := new(HDR_Scene_Data)

	// Init Camera
	data.camera = ve.Camera {
		position = {0, 0, 2},
		target   = {0, 0, 0},
		up       = {0, 1, 0},
	}
	ve.camera_init(&data.camera)

	data.hdr_surface_h = ve.create_surface_fit_screen(._4)
	hdr, _ := ve.get_surface(data.hdr_surface_h)
	hdr_color_attachmetn := ve.surface_add_color_attachment(hdr, format = ve.Pixel_Format.RGBA_norm_u16)
	bright_color_attachmetn := ve.surface_add_color_attachment(hdr, format = ve.Pixel_Format.RGBA_norm_u16)
	ve.surface_add_depth_attachment(hdr)

	// Load Model
	data.square = ve.create_primitive_square()
	data.cube = ve.create_primitive_cube()

	data.hdr_pipeline_h = create_hdr_pipeline()

	// Setup Material
	data.hdr_ubo_h = create_ubo_hdr()
	hdr_ubo, _ := ve.get_uniform_buffer(data.hdr_ubo_h)
	ubo_hdr_set_scene(hdr_ubo, hdr_color_attachmetn)
	ubo_hdr_set_bloom(hdr_ubo, bright_color_attachmetn)
	ubo_hdr_set_exposure(hdr_ubo, 0.5)

	data.blur_hor_pipeline_h = create_gaussian_blur_pipeline(true)
	data.blur_ver_pipeline_h = create_gaussian_blur_pipeline(false)

	data.blur_ubo_h = create_ubo_gaussian_blur()
	blur_hor_mtrl, _ := ve.get_uniform_buffer(data.blur_ubo_h)
	ubo_gaussian_blur_set_blur(blur_hor_mtrl, bright_color_attachmetn)

	data.multilight_pipeline_h = create_multilight_pipeline()
	data.multilight_ubo_h = create_ubo_multilight()
	multilight_ubo, _ := ve.get_uniform_buffer(data.multilight_ubo_h)

	ubo_multilight_set_color(multilight_ubo, {0.5, 0.5, 0.5})
	lights: [4]Light = {}
	lights[0] = Light {
		position = {0, 0, -3},
		color    = ({1, 0, 0} * 5),
	}
	lights[1] = Light {
		position = {0, 0, -6},
		color    = ({0, 1, 0} * 2),
	}
	lights[2] = Light {
		position = {0, 0, -9},
		color    = ({0, 0.2, 1} * 5),
	}
	lights[3] = Light {
		position = {0, 0, -12},
		color    = ({1, 1, 0} * 5),
	}
	ubo_multilight_set_lights(multilight_ubo, lights[:])

	// Setup Transform
	ve.init_trf(&data.transform)
	ve.trf_set_position(&data.transform, {0, -0.5, -1})
	ve.trf_set_scale(&data.transform, {0.5, 0.5, 0.5})

	for i in 0 ..< 16 {
		ve.init_trf(&data.positions[i])
		x := rand.float32_range(-1.5, 1.5)
		y := rand.float32_range(-1.5, 1.5)
		ve.trf_set_position(&data.positions[i], {x, y, -cast(f32)i})
		ve.trf_set_scale(&data.positions[i], rand.float32_range(0.3, 0.5))
		axis: vec3 = {rand.float32(), rand.float32(), rand.float32()}
		ve.trf_rotate(&data.positions[i], axis, rand.float32_range(-math.PI, math.PI))
	}

	data.light_box_pipeline_h = create_light_box_pipeline()
	for i in 0 ..< 4 {
		light: Light_Box
		ve.init_trf(&light.trans)
		ve.trf_set_position(&light.trans, lights[i].position)
		ve.trf_set_scale(&light.trans, 0.3)
		light.box_ubo = create_ubo_light_box()
		ubo, _ := ve.get_uniform_buffer(light.box_ubo)
		ubo_light_box_set_color(ubo, lights[i].color)
		data.light_boxes[i] = light
	}

	s.data = data
}

hdr_scene_update :: proc(s: ^Scene) {
	data := cast(^HDR_Scene_Data)s.data
	data.model_rotation += ve.get_delta_time()
	ve.trf_rotate(&data.transform, {0, 1, 0}, data.model_rotation)
	ve.cursor_disable()
	ve.camera_update_simple_controller(&data.camera)

	ubo, _ := ve.get_uniform_buffer(data.hdr_ubo_h)
	exp := ubo_hdr_get_exposure(ubo^)
	speed: f32 = 1.0
	if (ve.is_key_down(.Up)) {
		ubo_hdr_set_exposure(ubo, exp + speed * ve.get_delta_time())
	}
	if (ve.is_key_down(.Down)) {
		ubo_hdr_set_exposure(ubo, exp - speed * ve.get_delta_time())
	}
}

hdr_scene_draw :: proc(s: ^Scene) {
	data := cast(^HDR_Scene_Data)s.data

	multilight_pipeline, _ := ve.get_render_pipeline(data.multilight_pipeline_h)
	light_box_pipeline, _ := ve.get_render_pipeline(data.light_box_pipeline_h)
	hdr_pipeline, _ := ve.get_render_pipeline(data.hdr_pipeline_h)
	blur_hor_pipeline, _ := ve.get_render_pipeline(data.blur_hor_pipeline_h)
	blur_ver_pipeline, _ := ve.get_render_pipeline(data.blur_ver_pipeline_h)

	hdr_surface, _ := ve.get_surface(data.hdr_surface_h)

	ve.begin_render()
	// Begin ve.
	// --------------------------------------------------------------------------------------------------------------------

	ve.begin_surface(hdr_surface)
	for &t in data.positions {
		ve.draw_mesh(&data.cube, multilight_pipeline, {camera = &data.camera, trf = &t, h0 = data.multilight_ubo_h})
	}
	for &l in data.light_boxes {
		ve.draw_mesh(&data.cube, light_box_pipeline, {camera = &data.camera, trf = &l.trans, h0 = l.box_ubo})
	}
	ve.end_surface(hdr_surface)

	for i in 0 ..< 3 {
		// Horizontal gaussian blur
		ve.begin_surface(hdr_surface, {1})
		ve.draw_mesh(&data.square, blur_hor_pipeline, {camera = &data.camera, h0 = data.blur_ubo_h})
		ve.end_surface(hdr_surface)

		// Vertical gaussian blur
		ve.begin_surface(hdr_surface, {1})
		ve.draw_mesh(&data.square, blur_ver_pipeline, {camera = &data.camera, h0 = data.blur_ubo_h})
		ve.end_surface(hdr_surface)
	}

	ve.begin_draw()
	{
		ve.draw_mesh(&data.square, hdr_pipeline, {h0 = data.hdr_ubo_h})
	}
	ve.end_draw()

	// --------------------------------------------------------------------------------------------------------------------
	// End ve.
	ve.end_render()
}

hdr_scene_destroy :: proc(s: ^Scene) {
	data := cast(^HDR_Scene_Data)s.data

	ve.destroy_texture_h(data.texture_h)
	ve.destroy_mesh(&data.cube)
	ve.destroy_mesh(&data.square)

	free(data)
}
