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

	image_index: u32 = 0
	is_first := true
	for !glfw.WindowShouldClose(window) {
		//log.info("Is first:", is_first)
		free_all(context.temp_allocator)

		glfw.PollEvents()

		// Wait for previous frame.
		render.must(vk.WaitForFences(render_ctx.device, 1, &render_ctx.fence, true, max(u64)))

		images: u32 = cast(u32)len(render_ctx.swapchain.images)
		next_index: u32
		if (is_first) {
			next_index = 0
		} else {
			next_index = (image_index + 1) % images
		}

		index := image_index
		acquire_result := vk.AcquireNextImageKHR(
			device = render_ctx.device,
			swapchain = render_ctx.swapchain.swapchain,
			timeout = max(u64),
			semaphore = render_ctx.image_available_semaphore,
			fence = {},
			pImageIndex = &image_index,
		)
		//log.info("next_index: ", next_index)
		//log.info("image_index: ", image_index)

		#partial switch acquire_result {
		case .ERROR_OUT_OF_DATE_KHR:
			render.recreate_swapchain(&render_ctx)
			continue
		case .SUCCESS, .SUBOPTIMAL_KHR:
		case:
			log.panicf("vulkan: acquire next image failure: %v", acquire_result)
		}

		render.must(vk.ResetFences(render_ctx.device, 1, &render_ctx.fence))

		render.must(vk.ResetCommandBuffer(render_ctx.command_buffer, {}))
		render.record_command_buffer(&render_ctx, render_ctx.command_buffer, image_index)

		// submit_wait_semaphore: vk.Semaphore
		// submit_wait_semaphore_count: u32

		// if is_first {
		// 	submit_wait_semaphore = 0
		// 	submit_wait_semaphore_count = 0
		// } else {
		// 	submit_wait_semaphore = render_ctx.image_available_semaphores[image_index]
		// 	submit_wait_semaphore_count = 1
		// }

		// Submit.
		submit_info := vk.SubmitInfo {
			sType                = .SUBMIT_INFO,
			waitSemaphoreCount   = 1,
			pWaitSemaphores      = &render_ctx.image_available_semaphore, //&submit_wait_semaphore,
			pWaitDstStageMask    = &vk.PipelineStageFlags{.COLOR_ATTACHMENT_OUTPUT},
			commandBufferCount   = 1,
			pCommandBuffers      = &render_ctx.command_buffer,
			signalSemaphoreCount = 1,
			pSignalSemaphores    = &render_ctx.swapchain.render_finished_semaphores[image_index],
		}
		render.must(vk.QueueSubmit(render_ctx.graphics_queue, 1, &submit_info, render_ctx.fence))

		// Present.
		present_info := vk.PresentInfoKHR {
			sType              = .PRESENT_INFO_KHR,
			waitSemaphoreCount = 1,
			pWaitSemaphores    = &render_ctx.swapchain.render_finished_semaphores[image_index],
			swapchainCount     = 1,
			pSwapchains        = &render_ctx.swapchain.swapchain,
			pImageIndices      = &image_index,
		}
		present_result := vk.QueuePresentKHR(render_ctx.present_queue, &present_info)
		switch {
		case present_result == .ERROR_OUT_OF_DATE_KHR ||
		     present_result == .SUBOPTIMAL_KHR ||
		     render_ctx.framebuffer_resized:
			render_ctx.framebuffer_resized = false
			render.recreate_swapchain(&render_ctx)
		case present_result == .SUCCESS:
		case:
			log.panicf("vulkan: present failure: %v", present_result)
		}

		is_first = false
	}
	vk.DeviceWaitIdle(render_ctx.device)
}

glfw_error_callback :: proc "c" (code: i32, description: cstring) {
	context = g_ctx
	log.errorf("glfw: %i: %s", code, description)
}
