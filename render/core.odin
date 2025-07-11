package render

import "base:runtime"

import "core:log"
import "core:slice"
import "core:strings"


import "vendor:glfw"
import vk "vendor:vulkan"

// Enables Vulkan debug logging and validation layers.
ENABLE_VALIDATION_LAYERS :: #config(ENABLE_VALIDATION_LAYERS, ODIN_DEBUG)

MAX_FRAMES_IN_FLIGHT :: 1

DEVICE_EXTENSIONS := []cstring {
	vk.KHR_SWAPCHAIN_EXTENSION_NAME,
	// KHR_PORTABILITY_SUBSET_EXTENSION_NAME,
}

RenderContext :: struct {
	window:                    glfw.WindowHandle,
	frame_in_flight:           u16,
	framebuffer_resized:       bool,
	instance_info:             vk.InstanceCreateInfo,
	instance:                  vk.Instance,
	dbg_messenger:             vk.DebugUtilsMessengerEXT, // Null on release
	// Device
	physical_device:           vk.PhysicalDevice,
	device:                    vk.Device,
	// Surface
	surface:                   vk.SurfaceKHR,
	// Queue
	graphics_queue:            vk.Queue,
	present_queue:             vk.Queue,
	swapchain:                 ^SwapChain,
	render_pass:               vk.RenderPass,
	pipeline_layout:           vk.PipelineLayout,
	pipeline:                  vk.Pipeline,
	// Command pool
	command_pool:              vk.CommandPool,
	command_buffer:            vk.CommandBuffer,
	// Semaphores
	image_available_semaphore: vk.Semaphore,
	//render_finished_semaphores: []vk.Semaphore,
	fence:                     vk.Fence,
}

SwapChain :: struct {
	swapchain:                  vk.SwapchainKHR,
	format:                     vk.SurfaceFormatKHR,
	extent:                     vk.Extent2D,
	images:                     []vk.Image,
	image_views:                []vk.ImageView,
	frame_buffers:              []vk.Framebuffer,
	render_finished_semaphores: []vk.Semaphore,
}

// FrameContext :: struct {
// 	command_buffer:            vk.CommandBuffer,
//
// 	// Sync
// 	in_flight_fence:           vk.Fence,
// 	image_semaphore:           vk.Semaphore,
// 	render_finished_semaphore: vk.Semaphore,
// }
//
// KHR_PORTABILITY_SUBSET_EXTENSION_NAME :: "VK_KHR_portability_subset"
//
// DEVICE_EXTENSIONS := []cstring {
// 	vk.KHR_SWAPCHAIN_EXTENSION_NAME,
// 	// KHR_PORTABILITY_SUBSET_EXTENSION_NAME,
// }
//
//
// begin_frame::proc(ctx:^RenderContext) -> FrameContext{
// 	fr_ctx := FrameContext{
// 		command_buffer = ctx.command_buffers[ctx.frame_in_flight],
// 		in_flight_fence = ctx.in_flight_fences[ctx.frame_in_flight],
// 		image_semaphore = ctx.image_available_semaphores[ctx.frame_in_flight],
// 		render_finished_semaphore = ctx.render_finished_semaphores[ctx.frame_in_flight]
// 	}
// 	return fr_ctx
// }
//
// end_frame :: proc(render_ctx:^RenderContext, frame_ctx: ^FrameContext) {
// 	render_ctx.frame_in_flight = (render_ctx.frame_in_flight + 1) % MAX_FRAMES_IN_FLIGHT
// }
