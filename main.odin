package main

import "base:runtime"

import "core:log"
import "core:slice"
import "core:strings"
import "core:time"

import "render"
import "vendor:glfw"
import vk "vendor:vulkan"

g_ctx: runtime.Context

main :: proc() {
	context.logger = log.create_console_logger()
	g_ctx = context

	// TODO: update vendor bindings to glfw 3.4 and use this to set a custom allocator.
	// glfw.InitAllocator()

	// TODO: set up Vulkan allocator.

	glfw.SetErrorCallback(glfw_error_callback)

	if !glfw.Init() {log.panic("glfw: could not be initialized")}
	defer glfw.Terminate()

	glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)
	glfw.WindowHint(glfw.RESIZABLE, glfw.TRUE)

	window := glfw.CreateWindow(800, 600, "Vulkan", nil, nil)
	defer glfw.DestroyWindow(window) // TODO: move to render

	render_ctx: render.RenderContext
	render.set_logger(context.logger)

	render.init_context(&render_ctx, window)
	render.create_instance(&render_ctx)
	defer render.destroy_instance(&render_ctx)
	render.create_surface(&render_ctx)
	defer render.destroy_surface(&render_ctx)
	render.pick_suitable_physical_device(&render_ctx)
	render.create_logical_device(&render_ctx)
	defer render.destroy_logical_device(&render_ctx)
	render.create_swapchain(&render_ctx)
	defer render.destroy_swapchain(&render_ctx)
	render.create_render_pass(&render_ctx)
	defer render.destroy_render_pass(&render_ctx)
	render.create_framebuffers(&render_ctx)
	defer render.destroy_framebuffers(&render_ctx)
	render.create_graphic_pipeline(&render_ctx)
	defer render.destroy_graphic_pipline(&render_ctx)
	render.create_command_pool(&render_ctx)
	defer render.destroy_command_pool(&render_ctx)
	render.create_command_buffers(&render_ctx)
	render.create_sync_obj(&render_ctx)
	defer render.destroy_sync_obj(&render_ctx)

	for !glfw.WindowShouldClose(window) {
		free_all(context.temp_allocator)

		glfw.PollEvents()

		render.begin_render(&render_ctx)
		render.record_command_buffer(&render_ctx)
		render.end_render(&render_ctx)
	}
	vk.DeviceWaitIdle(render_ctx.device)
}

glfw_error_callback :: proc "c" (code: i32, description: cstring) {
	context = g_ctx
	log.errorf("glfw: %i: %s", code, description)
}
