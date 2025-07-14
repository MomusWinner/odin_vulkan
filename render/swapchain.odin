package render

import "base:runtime"

import "core:log"
import "core:slice"
import "core:strings"

import "vendor:glfw"
import vk "vendor:vulkan"

create_swapchain :: proc(ctx: ^RenderContext) {
	indices := find_queue_families(ctx.physical_device, ctx.surface)

	support, result := query_swapchain_support(
		ctx.physical_device,
		ctx.surface,
		context.temp_allocator,
	)
	if result != .SUCCESS {
		log.panicf("vulkan: query swapchain failed: %v", result)
	}

	surface_format := choose_swapchain_surface_format(support.formats)
	present_mode := choose_swapchain_present_mode(support.presentModes)
	extent := choose_swapchain_extent(ctx.window, support.capabilities)

	image_count := support.capabilities.minImageCount + 1
	if support.capabilities.maxImageCount > 0 && image_count > support.capabilities.maxImageCount {
		image_count = support.capabilities.maxImageCount
	}

	create_info := vk.SwapchainCreateInfoKHR {
		sType            = .SWAPCHAIN_CREATE_INFO_KHR,
		surface          = ctx.surface,
		minImageCount    = image_count,
		imageFormat      = surface_format.format,
		imageColorSpace  = surface_format.colorSpace,
		imageExtent      = extent,
		imageArrayLayers = 1,
		imageUsage       = {.COLOR_ATTACHMENT},
		preTransform     = support.capabilities.currentTransform,
		compositeAlpha   = {.OPAQUE},
		presentMode      = present_mode,
		clipped          = true,
	}

	if indices.graphics != indices.present {
		create_info.imageSharingMode = .CONCURRENT
		create_info.queueFamilyIndexCount = 2
		create_info.pQueueFamilyIndices = raw_data([]u32{indices.graphics.?, indices.present.?})
	}

	swapchain: vk.SwapchainKHR
	must(vk.CreateSwapchainKHR(ctx.device, &create_info, nil, &swapchain))

	ctx.swapchain = new(SwapChain)
	ctx.swapchain.swapchain = swapchain
	ctx.swapchain.format = surface_format
	ctx.swapchain.extent = extent
	setup_swapchain_images(ctx.swapchain, ctx.device)

	ctx.swapchain.render_finished_semaphores = make([]vk.Semaphore, len(ctx.swapchain.images))
	sem_info := vk.SemaphoreCreateInfo {
		sType = .SEMAPHORE_CREATE_INFO,
	}
	for _, i in ctx.swapchain.images {
		//must(vk.CreateSemaphore(ctx.device, &sem_info, nil, &ctx.image_available_semaphores[i]))
		must(
			vk.CreateSemaphore(
				ctx.device,
				&sem_info,
				nil,
				&ctx.swapchain.render_finished_semaphores[i],
			),
		)
	}
}

destroy_swapchain :: proc(ctx: ^RenderContext) {
	for sem in ctx.swapchain.render_finished_semaphores {vk.DestroySemaphore(ctx.device, sem, nil)}
	for view in ctx.swapchain.image_views {
		vk.DestroyImageView(ctx.device, view, nil)
	}
	delete(ctx.swapchain.image_views)
	delete(ctx.swapchain.images)
	vk.DestroySwapchainKHR(ctx.device, ctx.swapchain.swapchain, nil)
}

create_framebuffers :: proc(ctx: ^RenderContext) {
	ctx.swapchain.frame_buffers = make([]vk.Framebuffer, len(ctx.swapchain.image_views))
	for view, i in ctx.swapchain.image_views {
		attachments := []vk.ImageView{view}

		frame_buffer := vk.FramebufferCreateInfo {
			sType           = .FRAMEBUFFER_CREATE_INFO,
			renderPass      = ctx.render_pass,
			attachmentCount = 1,
			pAttachments    = raw_data(attachments),
			width           = ctx.swapchain.extent.width,
			height          = ctx.swapchain.extent.height,
			layers          = 1,
		}
		must(vk.CreateFramebuffer(ctx.device, &frame_buffer, nil, &ctx.swapchain.frame_buffers[i]))
	}
}

destroy_framebuffers :: proc(ctx: ^RenderContext) {
	for frame_buffer in ctx.swapchain.frame_buffers {
		vk.DestroyFramebuffer(ctx.device, frame_buffer, nil)
	}
	delete(ctx.swapchain.frame_buffers)
}

setup_swapchain_images :: proc(swapchain: ^SwapChain, device: vk.Device) {
	count: u32
	must(vk.GetSwapchainImagesKHR(device, swapchain.swapchain, &count, nil))

	swapchain.images = make([]vk.Image, count)
	swapchain.image_views = make([]vk.ImageView, count)
	must(vk.GetSwapchainImagesKHR(device, swapchain.swapchain, &count, raw_data(swapchain.images)))

	for image, i in swapchain.images {
		create_info := vk.ImageViewCreateInfo {
			sType = .IMAGE_VIEW_CREATE_INFO,
			image = image,
			viewType = .D2,
			format = swapchain.format.format,
			subresourceRange = {aspectMask = {.COLOR}, levelCount = 1, layerCount = 1},
		}
		must(vk.CreateImageView(device, &create_info, nil, &swapchain.image_views[i]))
	}
}

recreate_swapchain :: proc(ctx: ^RenderContext) {
	// Don't do anything when minimized.
	for w, h := glfw.GetFramebufferSize(ctx.window);
	    w == 0 || h == 0;
	    w, h = glfw.GetFramebufferSize(ctx.window) {
		glfw.WaitEvents()

		// Handle closing while minimized.
		if glfw.WindowShouldClose(ctx.window) {break}
	}

	vk.DeviceWaitIdle(ctx.device)

	destroy_framebuffers(ctx)
	destroy_swapchain(ctx)

	create_swapchain(ctx)
	create_framebuffers(ctx)
}
