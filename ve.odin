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
get_screen_aspect :: proc() -> f32 {return cast(f32)get_screen_width() / cast(f32)get_screen_height()}
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

init :: proc(
	user_data: rawptr,
	fixed_update_proc: game_event_proc,
	update_proc: game_event_proc,
	draw_proc: game_event_proc,
	destroy_proc: game_event_proc,
	info: Ve_Info,
	loc := #caller_location,
) {
	ctx.user_data = user_data
	ctx.fixed_update_proc = fixed_update_proc
	ctx.update_proc = update_proc
	ctx.draw_proc = draw_proc
	ctx.destroy_proc = destroy_proc

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
	ctx.game_time.target_time = 1.0 / 60.0
	ctx.game_time.fixed_target_time = 1.0 / 38.0
	ctx.info = info

	_init_gfx(info.gfx)
	_init_input()
}

run :: proc() {
	for (!_window_should_close() && !ctx.should_close) {
		start := glfw.GetTime()

		ctx.game_time.delta_time = cast(f32)(start - ctx.game_time.previous_frame)
		if ctx.game_time.delta_time < 0 {
			ctx.game_time.delta_time = 0
		}
		ctx.game_time.previous_frame = start

		ctx.game_time.total_time += cast(f64)ctx.game_time.delta_time

		free_all(context.temp_allocator)

		_update_input()

		fixed_update_dept_time := ctx.game_time.total_time - ctx.game_time.fixed_update_total_time
		fixed_update_dept_count := cast(int)(fixed_update_dept_time / cast(f64)ctx.game_time.fixed_target_time)

		if fixed_update_dept_count > 0 {
			for i in 0 ..< fixed_update_dept_count {
				ctx.fixed_update_proc(ctx.user_data)
				ctx.game_time.fixed_update_total_time += cast(f64)ctx.game_time.fixed_target_time
			}
		}

		ctx.update_proc(ctx.user_data)
		ctx.draw_proc(ctx.user_data)

		end := glfw.GetTime()

		frame_duration := cast(f32)(end - start)

		if frame_duration < ctx.game_time.target_time {
			wait_time: f32 = ctx.game_time.target_time - frame_duration
			wait_duration := cast(time.Duration)(wait_time * 1e9) * time.Nanosecond
			time.accurate_sleep(wait_duration)
		}
	}

	wait_render_completion()

	ctx.destroy_proc(ctx.user_data)

	_destroy()
}

close :: proc() {
	ctx.should_close = true
}

@(private)
_destroy :: proc() {
	_destroy_gfx()
	glfw.DestroyWindow(ctx.window.id)
	glfw.Terminate()
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
