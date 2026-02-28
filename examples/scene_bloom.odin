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

@(material)
Multilight_Material :: struct {
	lights: [4]Light,
	color:  vec3,
}

@(material)
HDR_Material :: struct {
	exposure: f32,
	scene:    ve.Texture_Handle,
	bloom:    ve.Texture_Handle,
}

@(material)
Gaussian_Blur_Material :: struct {
	blur:       ve.Texture_Handle,
	horizontal: b32,
}

@(material)
Light_Box_Material :: struct {
	color: vec3,
}

Light_Box :: struct {
	trans:    ve.Gfx_Transform,
	material: ve.Material_Handle,
}

HDR_Scene_Data :: struct {
	texture_h:           ve.Texture_Handle,
	square:              ve.Mesh,
	cube:                ve.Mesh,
	light_box_mtrl_h:    ve.Material_Handle,
	material_h:          ve.Material_Handle,
	hdr_material_h:      ve.Material_Handle,
	blur_material_h:     ve.Material_Handle,
	blur_hor_pipeline_h: ve.Render_Pipeline_Handle,
	blur_ver_pipeline_h: ve.Render_Pipeline_Handle,
	transform:           ve.Gfx_Transform,
	camera:              ve.Camera,
	hdr_surface_h:       ve.Surface_Handle,
	model_rotation:      f32,
	positions:           [16]ve.Gfx_Transform,
	light_boxes:         [4]Light_Box,
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

	// Setup Material
	data.hdr_material_h = create_mtrl_hdr(create_hdr_pipeline())
	hdr_mtrl, _ := ve.get_material(data.hdr_material_h)
	mtrl_hdr_set_scene(hdr_mtrl, hdr_color_attachmetn)
	mtrl_hdr_set_bloom(hdr_mtrl, bright_color_attachmetn)
	mtrl_hdr_set_exposure(hdr_mtrl, 0.5)

	data.blur_hor_pipeline_h = create_gaussian_blur_pipeline(true)
	data.blur_ver_pipeline_h = create_gaussian_blur_pipeline(false)

	data.blur_material_h = create_mtrl_gaussian_blur(data.blur_hor_pipeline_h)
	blur_hor_mtrl, _ := ve.get_material(data.blur_material_h)
	mtrl_gaussian_blur_set_horizontal(blur_hor_mtrl, true)
	mtrl_gaussian_blur_set_blur(blur_hor_mtrl, bright_color_attachmetn)

	data.material_h = create_mtrl_multilight(create_mulilight_pipeline())
	material, _ := ve.get_material(data.material_h)

	mtrl_multilight_set_color(material, {0.5, 0.5, 0.5})
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
	mtrl_multilight_set_lights(material, lights)

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

	light_box_pipeline_h := create_light_box_pipeline()
	for i in 0 ..< 4 {
		light: Light_Box
		ve.init_trf(&light.trans)
		ve.trf_set_position(&light.trans, lights[i].position)
		ve.trf_set_scale(&light.trans, 0.3)
		light.material = create_mtrl_light_box(light_box_pipeline_h)
		mtrl, _ := ve.get_material(light.material)
		mtrl_light_box_set_color(mtrl, lights[i].color)
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

	m, _ := ve.get_material(data.hdr_material_h)
	exp := mtrl_hdr_get_exposure(m^)
	speed: f32 = 1.0
	if (ve.is_key_down(.Up)) {
		mtrl_hdr_set_exposure(m, exp + speed * ve.get_delta_time())
	}
	if (ve.is_key_down(.Down)) {
		mtrl_hdr_set_exposure(m, exp - speed * ve.get_delta_time())
	}
}

hdr_scene_draw :: proc(s: ^Scene) {
	data := cast(^HDR_Scene_Data)s.data

	mtrl, _ := ve.get_material(data.material_h)
	hdr_mtrl, _ := ve.get_material(data.hdr_material_h)
	blur_mtrl, _ := ve.get_material(data.blur_material_h)
	hdr, _ := ve.get_surface(data.hdr_surface_h)

	frame := ve.begin_render()
	// Begin ve.
	// --------------------------------------------------------------------------------------------------------------------

	hdr_f := ve.begin_surface(hdr, frame)
	for &t in data.positions {
		ve.draw_mesh(hdr_f, &data.cube, mtrl, &data.camera, &t)
	}
	for &l in data.light_boxes {
		mtrl, _ := ve.get_material(l.material)
		ve.draw_mesh(hdr_f, &data.cube, mtrl, &data.camera, &l.trans)
	}
	ve.end_surface(hdr, hdr_f)

	for i in 0 ..< 3 {
		// Horizontal gaussian blur
		bloom_hor_f := ve.begin_surface(hdr, frame, {1})
		ve.mtrl_set_pipeline(blur_mtrl, data.blur_hor_pipeline_h)
		ve.draw_mesh(bloom_hor_f, &data.square, blur_mtrl, &data.camera, nil)
		ve.end_surface(hdr, bloom_hor_f)

		// Vertical gaussian blur
		bloom_f := ve.begin_surface(hdr, frame, {1})
		ve.mtrl_set_pipeline(blur_mtrl, data.blur_ver_pipeline_h)
		ve.draw_mesh(bloom_f, &data.square, blur_mtrl, nil, nil)
		ve.end_surface(hdr, bloom_f)
	}

	f := ve.begin_draw(frame)
	{
		ve.draw_mesh(f, &data.square, hdr_mtrl, nil, nil)
	}
	ve.end_draw(f)

	// --------------------------------------------------------------------------------------------------------------------
	// End ve.
	ve.end_render(frame)
}

hdr_scene_destroy :: proc(s: ^Scene) {
	data := cast(^HDR_Scene_Data)s.data

	ve.destroy_texture_h(data.texture_h)
	ve.destroy_mesh(&data.cube)
	ve.destroy_mesh(&data.square)

	free(data)
}
