package ve

import "base:runtime"
import "core:c"
import "core:log"
import "core:strings"
import "core:time"
import "vendor:glfw"
import vk "vendor:vulkan"

@(private)
ctx: Ve

@(private)
g_err_ctx: runtime.Context // FIXME:

@(require_results)
get_screen_width :: proc() -> int {return ctx.gfx.swapchain.width}
@(require_results)
get_screen_height :: proc() -> int {return ctx.gfx.swapchain.height}
@(require_results)
screen_resized :: proc() -> bool {return ctx.gfx.frame.swapchain_resized}

@(require_results)
get_window_pos :: proc() -> (int, int) {
	xpos, ypos := glfw.GetWindowPos(ctx.window.id)
	return cast(int)xpos, cast(int)ypos
}
set_window_pos :: proc(x, y: int) {
	glfw.SetWindowPos(ctx.window.id, cast(i32)x, cast(i32)y)
}

set_window_fullscreen :: proc(enable: bool) {
	if enable == ctx.window.fullscreen do return

	if enable {
		ctx.window.prev.width, ctx.window.prev.height = get_screen_width(), get_screen_height()
		ctx.window.prev.x, ctx.window.prev.y = get_window_pos()
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

	g_err_ctx = context
	glfw.SetErrorCallback(_glfw_error_callback)

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

	_update_input()

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
	context = g_err_ctx
	log.errorf("glfw: %i: %s", code, description)
}

@(private)
_window_should_close :: proc() -> b32 {
	return glfw.WindowShouldClose(ctx.window.id)
}
