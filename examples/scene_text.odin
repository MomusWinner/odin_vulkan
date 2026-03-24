package main

import ve ".."
import "base:runtime"
import sm "core:container/small_array"
import "core:fmt"
import "core:log"
import "core:math"
import "core:strings"

Text_Scene_Data :: struct {
	font:         ve.Font,
	camera:       ve.Camera,
	pipeline:     ve.Graphics_Pipeline,
	text:         Text,
	builder:      strings.Builder,
	color_value:  f32,
	elapsed_time: f64,
	time_delta:   f64,
}

@(buffer)
Text_UBO :: struct {
	glyph: ve.Texture,
	color: vec3,
}

Text :: struct {
	font: ^ve.Font,
	size: f32,
	text: string,
	mesh: ve.Mesh,
	trf:  ve.Transform,
	ubo:  ve.Uniform_Buffer,
}

create_text_scene :: proc() -> Scene {
	return Scene {
		init = text_scene_init,
		update = text_scene_update,
		draw = text_scene_draw,
		destroy = text_scene_destroy,
	}
}

text_scene_init :: proc(s: ^Scene) {
	data := new(Text_Scene_Data)

	data.time_delta = 2

	data.camera.position = {0, 0, 2}
	data.camera.target = {0, 0, 0}
	data.camera.up = {0, 1, 0}
	ve.camera_init(&data.camera)

	data.font = ve.load_font(
		"examples/assets/fonts/RobotoMono.ttf",
		ve.Create_Font_Info {
			size = 64,
			padding = 2,
			atlas_width = 2024,
			atlas_height = 1024,
			regions = {{start = 32, size = 128}, {start = 1024, size = 255}},
			default_char = '?',
		},
	)

	data.text = create_text(
		&data.font,
		"По берегу мы шли. Кипел поток,\nГде выли тени злы, полубиты,\nПоверженны в кровавый кипяток.",
		vec3{-1, 0, 0},
		1,
		0.0025,
	)

	strings.builder_init_len(&data.builder, len(data.text.text))
	strings.write_string(&data.builder, data.text.text)

	data.pipeline = create_text_pipeline()

	s.data = data
}

text_scene_update :: proc(s: ^Scene) {
	data := cast(^Text_Scene_Data)s.data
	data.color_value += ve.get_delta_time() * 5
	result := (math.sin_f32(data.color_value) + 1) / 2
	text_set_color(&data.text, vec3{1, result, 1})

	data.elapsed_time += cast(f64)ve.get_delta_time()
	if data.elapsed_time > data.time_delta {
		data.elapsed_time = 0
		strings.write_string(&data.builder, "\n... ")
		str := strings.to_string(data.builder)
		text_set_string(&data.text, str)
	}
}

text_scene_draw :: proc(s: ^Scene) {
	data := cast(^Text_Scene_Data)s.data

	ve.begin_render()
	// Begin ve.
	// --------------------------------------------------------------------------------------------------------------------
	ve.begin_draw()

	ve.set_camera(data.camera)
	text_draw(&data.text, data.pipeline)

	ve.end_draw()
	// --------------------------------------------------------------------------------------------------------------------
	// End ve.
	ve.end_render()
}

text_scene_destroy :: proc(s: ^Scene) {
	data := cast(^Text_Scene_Data)s.data

	strings.builder_destroy(&data.builder)
	ve.unload_font(&data.font)

	free(data)
}

create_text :: proc(
	font: ^ve.Font,
	text: string,
	position: vec3,
	color: vec3,
	size: f32,
	loc := #caller_location,
) -> Text {
	trf := ve.Transform{}
	ve.init_trf(&trf)
	ve.trf_set_position(&trf, position)
	ve.trf_set_scale(&trf, vec3{1, 1, 1})

	ubo := create_ubo_text()
	ubo_text_set_glyph(ubo, font.glyph)
	ubo_text_set_color(ubo, color)

	vertices := ve.create_text_mesh(font, text, size, context.temp_allocator, loc)
	vertices_size := cast(ve.Device_Size)(size_of(ve.FontVertex) * len(vertices))
	vbo := ve.create_buffer({.Vertex}, vertices_size, raw_data(vertices), loc)

	mesh := ve.Mesh {
		vbo          = vbo,
		vertex_count = len(vertices),
	}

	return Text{font = font, trf = trf, size = size, ubo = ubo, text = text, mesh = mesh}
}

text_set_color :: proc(text: ^Text, color: vec3, loc := #caller_location) {
	ubo_text_set_color(text.ubo, color)
}

text_set_string :: proc(text: ^Text, text_str: string, loc := #caller_location) {
	text.text = text_str
	ve.destroy_mesh(&text.mesh, loc)

	vertices := ve.create_text_mesh(text.font, text_str, text.size, context.temp_allocator, loc)
	vertices_size := cast(ve.Device_Size)(size_of(ve.FontVertex) * len(vertices))
	vbo := ve.create_buffer({.Vertex}, vertices_size, raw_data(vertices), loc)

	mesh := ve.Mesh {
		vbo          = vbo,
		vertex_count = len(vertices),
	}
	text.mesh = mesh
}

text_draw :: proc(text: ^Text, pipeline: ve.Graphics_Pipeline) {
	ve.draw_mesh(&text.mesh, pipeline, ve.trf_get_matrix(text.trf), ve.Handles{h0 = text.ubo})
}

text_shader_attribute :: proc() -> ve.Vertex_Input_Description {
	attribute_descriptions := ve.Vertex_Input_Attribute_Descriptions{}
	sm.push_back_elems(
		&attribute_descriptions,
		ve.Vertex_Input_Attribute_Description {
			location = 0,
			format = .RGB_f32,
			offset = cast(u32)offset_of(ve.FontVertex, position),
		},
		ve.Vertex_Input_Attribute_Description {
			location = 1,
			format = .RG_f32,
			offset = cast(u32)offset_of(ve.FontVertex, tex_coords),
		},
	)

	return ve.Vertex_Input_Description {
		binding = 0,
		stride = size_of(ve.FontVertex),
		input_rate = .Vertex,
		attributes = attribute_descriptions,
	}
}

create_text_pipeline :: proc() -> ve.Graphics_Pipeline {
	vert_descriptions: ve.Vertex_Input_Descriptions
	sm.append(&vert_descriptions, text_shader_attribute())

	stages := ve.Stage_Infos{}
	sm.push_back_elems(
		&stages,
		ve.Pipeline_Stage_Info{stage = .Vertex, shader_path = "examples/assets/shaders/text.vert"},
		ve.Pipeline_Stage_Info{stage = .Fragment, shader_path = "examples/assets/shaders/text.frag"},
	)

	bleding := ve.Blending_Infos{}
	sm.append(
		&bleding,
		ve.Blending_Info {
			src_color_blend_factor = .Src_Alpha,
			dst_color_blend_factor = .One_Minus_Src_Alpha,
			color_blend_op = .Add,
			src_alpha_blend_factor = .One,
			dst_alpha_blend_factor = .Zero,
			alpha_blend_op = .Add,
			color_write_mask = {.R, .G, .B, .A},
		},
	)

	create_info := ve.Create_Pipeline_Info {
		bindless = true,
		vertex_input_descriptions = vert_descriptions,
		blending_info = {attachment_infos = bleding},
		stage_infos = stages,
		topology = .Triangle_List,
		rasterizer = {polygon_mode = .Fill, line_width = 1, cull_mode = {}, front_face = .Clockwise},
		depth = {
			enable = true,
			write_enable = true,
			compare_op = .Less,
			bounds_test_enable = false,
			min_bounds = 0,
			max_bounds = 0,
		},
		stencil = {enable = false},
	}

	return ve.create_graphics_pipeline(create_info)
}
