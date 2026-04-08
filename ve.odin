package ve

import "base:runtime"
import "core:c"
import "core:log"
import "core:strings"
import "core:time"
import "math"
import "vendor:glfw"
import vk "vendor:vulkan"

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

game_event_proc :: proc(user_data: rawptr)

Ve :: struct {
	window: struct {
		id:         glfw.WindowHandle,
		focused:    bool,
		fullscreen: bool,
		prev:       struct {
			width, height: int,
			x, y:          int,
		},
	},
	info:   Ve_Info,
	gfx:    Graphics,
	time:   struct {
		start_time:     time.Time,
		previous_frame: time.Time,
		delta_time:     f32,
		total_time:     f64,
	},
	input:  Input_State,
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

@(private)
ctx: Ve

@(private = "file")
glfw_callback_ctx: runtime.Context

@(require_results)
swapchain_get_size :: proc() -> (int, int) {return swapchain_get_width(), swapchain_get_height()}
@(require_results)
swapchain_get_width :: proc() -> int {return ctx.gfx.swapchain.width}
@(require_results)
swapchain_get_height :: proc() -> int {return ctx.gfx.swapchain.height}
@(require_results)
swapchain_resized :: proc() -> bool {return ctx.gfx.frame.swapchain_resized}

screen_get_size :: swapchain_get_size
screen_get_width :: swapchain_get_width
screen_get_height :: swapchain_get_height
screen_resized :: swapchain_resized

@(require_results)
framebuffer_get_size :: proc() -> (int, int) {
	w, h := glfw.GetFramebufferSize(ctx.window.id)
	return cast(int)w, cast(int)h
}

@(require_results)
window_get_size :: proc() -> (int, int) {
	w, h := glfw.GetWindowSize(ctx.window.id)
	return cast(int)w, cast(int)h
}
@(require_results)
window_get_position :: proc() -> (int, int) {
	xpos, ypos := glfw.GetWindowPos(ctx.window.id)
	return cast(int)xpos, cast(int)ypos
}
window_set_position :: proc(x, y: int) {
	glfw.SetWindowPos(ctx.window.id, cast(i32)x, cast(i32)y)
}
@(require_results)
window_is_focused :: proc() -> bool {
	return ctx.window.focused
}
window_set_fullscreen :: proc(enable: bool) {
	if enable == ctx.window.fullscreen do return

	if enable {
		ctx.window.prev.width, ctx.window.prev.height = screen_get_width(), screen_get_height()
		ctx.window.prev.x, ctx.window.prev.y = window_get_position()
		monitor := glfw.GetPrimaryMonitor()
		video := glfw.GetVideoMode(monitor)
		glfw.SetWindowMonitor(ctx.window.id, monitor, 0, 0, video.width, video.height, video.refresh_rate)
	} else {
		glfw.SetWindowMonitor(
			ctx.window.id,
			nil,
			cast(i32)ctx.window.prev.x,
			cast(i32)ctx.window.prev.y,
			cast(i32)ctx.window.prev.width,
			cast(i32)ctx.window.prev.height,
			0,
		)
	}

	ctx.window.fullscreen = enable
}

get_delta_time :: proc() -> f32 {
	return ctx.time.delta_time
}

get_total_time :: proc() -> f64 {
	return ctx.time.total_time
}

init :: proc(info: Ve_Info, loc := #caller_location) {
	// TODO: set custom allocator.
	// glfw.InitAllocator()

	if !glfw.Init() {
		log.panic("glfw: could not be initialized")
	} else {
		log.info("glfw: initialized")
	}

	glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)
	glfw.WindowHint(glfw.RESIZABLE, cast(b32)info.window.resizable)
	glfw.WindowHint(glfw.FLOATING, cast(b32)info.window.floating)

	window: glfw.WindowHandle
	if info.window.fullscreen {
		ctx.window.prev.width, ctx.window.prev.height = info.window.width, info.window.height
		ctx.window.fullscreen = true
		monitor := glfw.GetPrimaryMonitor()
		video := glfw.GetVideoMode(monitor)

		ctx.window.prev.x = (cast(int)video.width - info.window.width) / 2
		ctx.window.prev.y = (cast(int)video.height - info.window.height) / 2
		if ctx.window.prev.x < 0 do ctx.window.prev.x = 0
		if ctx.window.prev.y < 0 do ctx.window.prev.y = 0

		window = glfw.CreateWindow(
			video.width,
			video.height,
			strings.clone_to_cstring(info.window.title, context.temp_allocator),
			monitor,
			nil,
		)
	} else {
		window = glfw.CreateWindow(
			cast(i32)info.window.width,
			cast(i32)info.window.height,
			strings.clone_to_cstring(info.window.title, context.temp_allocator),
			nil,
			nil,
		)
	}
	assert(window != nil, "Couldn't create window. Please check window settings", loc)

	glfw_callback_ctx = context
	glfw.SetErrorCallback(_glfw_error_callback)
	glfw.SetWindowFocusCallback(window, _glfw_window_focus_callback)

	ctx.window.id = window
	ctx.info = info

	_init_gfx(info.gfx)
	_init_input()
}

close :: proc() {
	_destroy_gfx()
	glfw.DestroyWindow(ctx.window.id)
	glfw.Terminate()
}

should_close :: proc() -> bool {
	now := time.now()
	if ctx.time.previous_frame != {} {
		ctx.time.delta_time = cast(f32)time.duration_seconds(time.diff(ctx.time.previous_frame, now))
	}
	ctx.time.previous_frame = now

	if ctx.time.start_time == {} {
		ctx.time.start_time = time.now()
	}
	ctx.time.total_time = time.duration_seconds(time.since(ctx.time.start_time))

	_input_late_update()

	glfw.PollEvents()

	_input_update()

	return cast(bool)_window_should_close()
}

@(require_results)
load_meshes :: proc(path: string, allocator := context.allocator) -> []Mesh {
	imp_meshes, ok := import_obj(path)
	defer {
		for m in imp_meshes {
			delete(m.vertices)
			delete(m.indices)
		}
		delete(imp_meshes)
	}
	if !ok {
		log.error("Couldn't import obj", path)
	}
	meshes := make([]Mesh, len(imp_meshes), allocator)

	for imp_mesh, i in imp_meshes {
		meshes[i] = create_mesh(imp_mesh.vertices, imp_mesh.indices)
	}

	return meshes
}

@(private = "file")
_glfw_error_callback :: proc "c" (code: i32, description: cstring) {
	context = glfw_callback_ctx
	log.errorf("glfw: %i: %s", code, description)
}

@(private = "file")
_glfw_window_focus_callback :: proc "c" (window: glfw.WindowHandle, focused: c.int) {
	ctx.window.focused = true if focused == 1 else false
}

@(private)
_window_should_close :: proc() -> b32 {
	return glfw.WindowShouldClose(ctx.window.id)
}
