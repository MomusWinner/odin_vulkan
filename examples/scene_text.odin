package main

import ve ".."
import "base:runtime"
import "core:fmt"
import "core:log"
import "core:math"
import "core:math/linalg/glsl"
import "core:math/rand"
import "core:strings"

Text_Scene_Data :: struct {
	font:         ve.Font,
	camera:       ve.Camera,
	text:         ve.Text,
	builder:      strings.Builder,
	color_value:  f32,
	elapsed_time: f64,
	time_delta:   f64,
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
		ve.Create_Font_Info {
			path = "assets/buildin/fonts/RobotoMono.ttf",
			size = 128,
			padding = 2,
			atlas_width = 2024,
			atlas_height = 1024,
			regions = {{start = 32, size = 128}, {start = 1024, size = 255}},
			default_char = '?',
		},
	)

	data.text = ve.create_text(
		&data.font,
		"По берегу мы шли. Кипел поток,\nГде выли тени злы, полубиты,\nПоверженны в кровавый кипяток.",
		vec3{-0.5, 0, 0},
		vec4{0, 0.5, 0, 1},
		0.65,
	)

	strings.builder_init_len(&data.builder, len(data.text.text))
	strings.write_string(&data.builder, data.text.text)

	s.data = data
}

text_scene_update :: proc(s: ^Scene) {
	data := cast(^Text_Scene_Data)s.data
	data.color_value += ve.get_delta_time() * 5
	result := (math.sin_f32(data.color_value) + 1) / 2
	ve.text_set_color(&data.text, ve.color{1, result, 1, 1})

	data.elapsed_time += cast(f64)ve.get_delta_time()
	if data.elapsed_time > data.time_delta {
		data.elapsed_time = 0
		strings.write_string(&data.builder, "\n... ")
		str := strings.to_string(data.builder)
		ve.text_set_string(&data.text, str)
	}
}

text_scene_draw :: proc(s: ^Scene) {
	data := cast(^Text_Scene_Data)s.data

	ve.begin_render()
	// Begin ve.
	// --------------------------------------------------------------------------------------------------------------------
	ve.begin_draw()

	ve.set_camera(data.camera)

	ve.draw_text(&data.text, &data.camera)

	ve.end_draw()
	// --------------------------------------------------------------------------------------------------------------------
	// End ve.
	ve.end_render()
}

text_scene_destroy :: proc(s: ^Scene) {
	data := cast(^Text_Scene_Data)s.data

	strings.builder_destroy(&data.builder)
	ve.destroy_text(&data.text)
	ve.unload_font(&data.font)

	free(data)
}
