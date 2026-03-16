package main

import ve ".."
import "base:runtime"
import "core:log"
import "core:math"
import "core:math/linalg/glsl"
import "core:math/rand"
import "vendor:glfw"
import vk "vendor:vulkan"

create_empty_scene :: proc() -> Scene {
	return Scene {
		init = empty_scene_init,
		update = empty_scene_update,
		draw = empty_scene_draw,
		destroy = empty_scene_destroy,
	}
}

empty_scene_init :: proc(s: ^Scene) {}

empty_scene_update :: proc(s: ^Scene) {}

empty_scene_draw :: proc(s: ^Scene) {
	ve.begin_render()
	// Begin gfx. ------------------------------

	ve.begin_draw()

	ve.end_draw()

	// End gfx. ------------------------------
	ve.end_render()
}

empty_scene_destroy :: proc(s: ^Scene) {}
