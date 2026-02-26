package ve

import "math"
import "vendor:glfw"

vec2 :: math.vec2
ivec2 :: math.ivec2
vec3 :: math.vec3
ivec3 :: math.ivec3
vec4 :: math.vec4
color :: math.vec4
ivec4 :: math.ivec4
mat4 :: math.mat4
quat :: math.quat

Vertex :: struct {
	position:  vec3,
	tex_coord: vec2,
	normal:    vec3,
	color:     vec4,
}

game_event_proc :: proc(user_data: rawptr)

Game_Time :: struct {
	total_game_time:         f64,
	delta_time:              f32,
	target_time:             f32,
	fixed_target_time:       f32,
	previous_frame:          f64,
	fixed_update_total_time: f64,
}

Ve :: struct {
	window:            glfw.WindowHandle,
	info:              Ve_Info,
	should_close:      bool,
	gfx:               Graphics,
	game_time:         Game_Time,
	user_data:         rawptr,
	fixed_update_proc: game_event_proc,
	update_proc:       game_event_proc,
	draw_proc:         game_event_proc,
	destroy_proc:      game_event_proc,
}

Ve_Info :: struct {
	gfx:    Graphics_Init_Info,
	window: struct {
		title:  string,
		width:  i32,
		height: i32,
	},
}
