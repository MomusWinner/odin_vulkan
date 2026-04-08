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
	d := new(Text_Scene_Data)

	d.time_delta = 2

	d.camera.position = {0, 0, 2}
	d.camera.target = {0, 0, 0}
	d.camera.up = {0, 1, 0}
	ve.init_camera(&d.camera)

	d.font = ve.load_font(
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

	d.text = create_text(
		&d.font,
		"По берегу мы шли. Кипел поток,\nГде выли тени злы, полубиты,\nПоверженны в кровавый кипяток.",
		vec3{-1, 0, 0},
		1,
		0.0025,
	)

	strings.builder_init_len(&d.builder, len(d.text.text))
	strings.write_string(&d.builder, d.text.text)

	d.pipeline = create_text_pipeline()

	s.data = d
}

text_scene_update :: proc(s: ^Scene) {
	d := cast(^Text_Scene_Data)s.data
	d.color_value += ve.time_get_delta() * 5
	green := (math.sin_f32(cast(f32)ve.time_get_total() * 5) + 1) / 2
	text_set_color(&d.text, vec3{1, green, 1})

	d.elapsed_time += cast(f64)ve.time_get_delta()
	if d.elapsed_time > d.time_delta {
		d.elapsed_time = 0
		strings.write_string(&d.builder, "\n... ")
		str := strings.to_string(d.builder)
		text_set_string(&d.text, str)
	}
}

text_scene_draw :: proc(s: ^Scene) {
	d := cast(^Text_Scene_Data)s.data

	ve.begin_pass()

	ve.set_camera(d.camera)

	ve.begin_draw()
	{
		text_draw(&d.text, d.pipeline)
	}
	ve.end_draw()

	ve.end_pass()
}

text_scene_destroy :: proc(s: ^Scene) {
	d := cast(^Text_Scene_Data)s.data

	strings.builder_destroy(&d.builder)
	ve.unload_font(&d.font)

	free(d)
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
	ubo_text_set_glyph(ubo, font.glyph_map)
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
	ve.draw_mesh(text.mesh, pipeline, ve.trf_get_matrix(text.trf), ve.Handles{h0 = text.ubo})
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
