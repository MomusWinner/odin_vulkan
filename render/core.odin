package render

import "base:intrinsics"
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
	// Swap chain 
	swapchain:                 ^SwapChain,
	image_index:               u32,
	render_pass:               vk.RenderPass,
	pipeline_layout:           vk.PipelineLayout,
	pipeline:                  vk.Pipeline,
	// Command pool
	command_pool:              vk.CommandPool,
	command_buffer:            vk.CommandBuffer,
	// Semaphores
	image_available_semaphore: vk.Semaphore,
	fence:                     vk.Fence,
	// Flags
	framebuffer_resized:       bool,
	render_started:            bool,
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

Buffer :: struct {
	buffer: vk.Buffer,
	memory: vk.DeviceMemory,
}

BeginRenderError :: enum {
	None,
	OutOfDate,
	NotEnded,
}


begin_render :: proc(ctx: ^RenderContext) -> BeginRenderError {
	if ctx.render_started {
		log.error("Call end_render() after begin_render()")
		return .NotEnded
	}
	defer ctx.render_started = true

	// Wait for previous frame
	must(vk.WaitForFences(ctx.device, 1, &ctx.fence, true, max(u64)))

	images: u32 = cast(u32)len(ctx.swapchain.images)
	acquire_result := vk.AcquireNextImageKHR(
		device = ctx.device,
		swapchain = ctx.swapchain.swapchain,
		timeout = max(u64),
		semaphore = ctx.image_available_semaphore,
		fence = {},
		pImageIndex = &ctx.image_index,
	)

	#partial switch acquire_result {
	case .ERROR_OUT_OF_DATE_KHR:
		recreate_swapchain(ctx)
		return .OutOfDate

	case .SUCCESS, .SUBOPTIMAL_KHR:
	case:
		log.panicf("vulkan: acquire next image failure: %v", acquire_result)
	}

	must(vk.ResetFences(ctx.device, 1, &ctx.fence))
	must(vk.ResetCommandBuffer(ctx.command_buffer, {}))


	begin_info := vk.CommandBufferBeginInfo {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
	}
	must(vk.BeginCommandBuffer(ctx.command_buffer, &begin_info))

	clear_color := vk.ClearValue{}
	clear_color.color.float32 = {0.0, 0.0, 0.0, 1.0}

	render_pass_info := vk.RenderPassBeginInfo {
		sType = .RENDER_PASS_BEGIN_INFO,
		renderPass = ctx.render_pass,
		framebuffer = ctx.swapchain.frame_buffers[ctx.image_index],
		renderArea = {extent = ctx.swapchain.extent},
		clearValueCount = 1,
		pClearValues = &clear_color,
	}
	vk.CmdBeginRenderPass(ctx.command_buffer, &render_pass_info, .INLINE)

	return .None
}

end_render :: proc(ctx: ^RenderContext) {
	if !ctx.render_started {
		log.error("Call begin_render() before end_render()")
	}

	vk.CmdEndRenderPass(ctx.command_buffer)
	must(vk.EndCommandBuffer(ctx.command_buffer))

	submit_info := vk.SubmitInfo {
		sType                = .SUBMIT_INFO,
		waitSemaphoreCount   = 1,
		pWaitSemaphores      = &ctx.image_available_semaphore, //&submit_wait_semaphore,
		pWaitDstStageMask    = &vk.PipelineStageFlags{.COLOR_ATTACHMENT_OUTPUT},
		commandBufferCount   = 1,
		pCommandBuffers      = &ctx.command_buffer,
		signalSemaphoreCount = 1,
		pSignalSemaphores    = &ctx.swapchain.render_finished_semaphores[ctx.image_index],
	}
	must(vk.QueueSubmit(ctx.graphics_queue, 1, &submit_info, ctx.fence))

	present_info := vk.PresentInfoKHR {
		sType              = .PRESENT_INFO_KHR,
		waitSemaphoreCount = 1,
		pWaitSemaphores    = &ctx.swapchain.render_finished_semaphores[ctx.image_index],
		swapchainCount     = 1,
		pSwapchains        = &ctx.swapchain.swapchain,
		pImageIndices      = &ctx.image_index,
	}
	present_result := vk.QueuePresentKHR(ctx.present_queue, &present_info)

	switch {
	case present_result == .ERROR_OUT_OF_DATE_KHR ||
	     present_result == .SUBOPTIMAL_KHR ||
	     ctx.framebuffer_resized:
		ctx.framebuffer_resized = false
		recreate_swapchain(ctx)
	case present_result == .SUCCESS:
	case:
		log.panicf("vulkan: present failure: %v", present_result)
	}

	defer ctx.render_started = false
}

find_memory_type :: proc(
	physical_device: vk.PhysicalDevice,
	type_filter: u32,
	properties: vk.MemoryPropertyFlags,
) -> (
	memory_type: u32,
	err: bool,
) {
	mem_property: vk.PhysicalDeviceMemoryProperties
	vk.GetPhysicalDeviceMemoryProperties(physical_device, &mem_property)

	for i: u32 = 0; i < mem_property.memoryTypeCount; i += 1 {
		if (type_filter & (1 << i) != 0) &&
		   (mem_property.memoryTypes[i].propertyFlags >= properties) {
			return i, false
		}
	}

	return 0, true
}

create_buffer :: proc(
	ctx: ^RenderContext,
	size: vk.DeviceSize,
	usage: vk.BufferUsageFlags,
	properties: vk.MemoryPropertyFlags,
	//vertices: []Vertex,
) -> Buffer {
	//cast(vk.DeviceSize)(size_of(vertices[0]) * len(vertices))
	// usage {.VERTEX_BUFFER}
	buffer_info := vk.BufferCreateInfo {
		sType       = .BUFFER_CREATE_INFO,
		size        = size,
		usage       = usage,
		sharingMode = .EXCLUSIVE,
	}

	buffer: Buffer
	must(vk.CreateBuffer(ctx.device, &buffer_info, nil, &buffer.buffer))

	mem_requirements: vk.MemoryRequirements
	vk.GetBufferMemoryRequirements(ctx.device, buffer.buffer, &mem_requirements)

	memory_type, err := find_memory_type(
		ctx.physical_device,
		mem_requirements.memoryTypeBits,
		properties,
	)
	if err {
		log.fatal("Failed to find suitable memory type!")
	}

	alloc_info := vk.MemoryAllocateInfo {
		sType           = .MEMORY_ALLOCATE_INFO,
		allocationSize  = mem_requirements.size,
		memoryTypeIndex = memory_type,
	}

	if vk.AllocateMemory(ctx.device, &alloc_info, nil, &buffer.memory) != .SUCCESS {
		log.fatal("Failed to allocate buffer memory")
	}

	vk.BindBufferMemory(ctx.device, buffer.buffer, buffer.memory, 0)

	return buffer
}

fill_buffer :: proc(
	ctx: ^RenderContext,
	buffer: Buffer,
	buffer_size: vk.DeviceSize,
	vertices: rawptr,
) {
	data: rawptr
	vk.MapMemory(ctx.device, buffer.memory, 0, buffer_size, {}, &data)
	intrinsics.mem_copy(data, vertices, buffer_size)
	vk.UnmapMemory(ctx.device, buffer.memory)
}

destroy_buffer :: proc(ctx: ^RenderContext, buffer: ^Buffer) {
	vk.DestroyBuffer(ctx.device, buffer.buffer, nil)
	vk.FreeMemory(ctx.device, buffer.memory, nil)
	buffer.buffer = 0
	buffer.memory = 0
}
