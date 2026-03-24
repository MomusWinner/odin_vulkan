package ve

import "core:time"
import "math"
import "vendor:glfw"

vec2 :: math.vec2
ivec2 :: math.ivec2
uvec2 :: math.uvec2
vec3 :: math.vec3
ivec3 :: math.ivec3
uvec3 :: math.uvec3
vec4 :: math.vec4
uvec4 :: math.uvec4
color :: math.vec4
ivec4 :: math.ivec4
mat4 :: math.mat4
quat :: math.quat

Vertex :: struct {
	position:  vec3,
	tex_coord: vec2,
	normal:    vec3,
}

game_event_proc :: proc(user_data: rawptr)

Ve :: struct {
	window:       struct {
		id:         glfw.WindowHandle,
		fullscreen: bool,
		prev:       struct {
			width, height: int,
			x, y:          int,
		},
	},
	info:         Ve_Info,
	should_close: bool,
	gfx:          Graphics,
	time:         struct {
		start_time:     time.Time,
		previous_frame: time.Time,
		delta_time:     f32,
		total_time:     f64,
	},
	input:        struct {
		keyboard: struct {
			states:          [KEYBOARD_MAX_KEY]i32,
			previous_states: [KEYBOARD_MAX_KEY]i32,
		},
		mouse:    struct {
			states:             [glfw.MOUSE_BUTTON_LAST]i32,
			previous_states:    [glfw.MOUSE_BUTTON_LAST]i32,
			position:           vec2,
			previouse_position: vec2,
			scroll:             vec2,
		},
	},
}

Ve_Info :: struct {
	gfx:    Graphics_Init_Info,
	window: struct {
		title:      string,
		fullscreen: bool,
		resizable:  bool,
		floating:   bool,
		width:      int,
		height:     int,
	},
}
