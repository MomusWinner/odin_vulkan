package render

import "base:runtime"

import "core:log"
import "core:slice"
import "core:strings"


import "vendor:glfw"
import vk "vendor:vulkan"

when ODIN_OS == .Darwin {
	// NOTE: just a bogus import of the system library,
	// needed so we can add a linker flag to point to /usr/local/lib (where vulkan is installed by default)
	// when trying to load vulkan.
	@(require, extra_linker_flags = "-rpath /usr/local/lib")
	foreign import __ "system:System.framework"
}

SHADER_VERT :: #load("../vert.spv")
SHADER_FRAG :: #load("../frag.spv")

g_logger_context: runtime.Context

set_logger :: proc(logger: log.Logger) {
	g_logger_context = context
	g_logger_context.logger = logger
}

init_context :: proc(ctx: ^RenderContext, window: glfw.WindowHandle) {
	ctx.window = window
}

create_instance :: proc(ctx: ^RenderContext) {
	vk.load_proc_addresses_global(rawptr(glfw.GetInstanceProcAddress))
	assert(vk.CreateInstance != nil, "vulkan function pointers not loaded")

	create_info := vk.InstanceCreateInfo {
		sType            = .INSTANCE_CREATE_INFO,
		pApplicationInfo = &vk.ApplicationInfo {
			sType = .APPLICATION_INFO,
			pApplicationName = "Hello Triangle",
			applicationVersion = vk.MAKE_VERSION(1, 0, 0),
			pEngineName = "No Engine",
			engineVersion = vk.MAKE_VERSION(1, 0, 0),
			apiVersion = vk.API_VERSION_1_0,
		},
	}
	ctx.instance_info = create_info

	extensions := slice.clone_to_dynamic(
		glfw.GetRequiredInstanceExtensions(),
		context.temp_allocator,
	)

	// MacOS is a special snowflake ;)
	when ODIN_OS == .Darwin {
		create_info.flags |= {.ENUMERATE_PORTABILITY_KHR}
		append(&extensions, vk.KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME)
	}

	when ENABLE_VALIDATION_LAYERS {
		create_info.ppEnabledLayerNames = raw_data([]cstring{"VK_LAYER_KHRONOS_validation"})
		create_info.enabledLayerCount = 1

		append(&extensions, vk.EXT_DEBUG_UTILS_EXTENSION_NAME)

		// Severity based on logger level.
		severity: vk.DebugUtilsMessageSeverityFlagsEXT
		if context.logger.lowest_level <= .Error {
			severity |= {.ERROR}
		}
		if context.logger.lowest_level <= .Warning {
			severity |= {.WARNING}
		}
		if context.logger.lowest_level <= .Info {
			severity |= {.INFO}
		}
		if context.logger.lowest_level <= .Debug {
			severity |= {.VERBOSE}
		}

		dbg_create_info := vk.DebugUtilsMessengerCreateInfoEXT {
			sType           = .DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
			messageSeverity = severity,
			messageType     = {.GENERAL, .VALIDATION, .PERFORMANCE}, // all of them.
			pfnUserCallback = vk_messenger_callback,
		}
		create_info.pNext = &dbg_create_info
	}

	create_info.enabledExtensionCount = u32(len(extensions))
	create_info.ppEnabledExtensionNames = raw_data(extensions)

	must(vk.CreateInstance(&create_info, nil, &ctx.instance))

	vk.load_proc_addresses_instance(ctx.instance)

	when ENABLE_VALIDATION_LAYERS {
		must(
			vk.CreateDebugUtilsMessengerEXT(
				ctx.instance,
				&dbg_create_info,
				nil,
				&ctx.dbg_messenger,
			),
		)
	}
}

destroy_instance :: proc(ctx: ^RenderContext) {
	when ENABLE_VALIDATION_LAYERS {
		vk.DestroyDebugUtilsMessengerEXT(ctx.instance, ctx.dbg_messenger, nil)
	}
	vk.DestroyInstance(ctx.instance, nil)
}

create_surface :: proc(ctx: ^RenderContext) {
	must(glfw.CreateWindowSurface(ctx.instance, ctx.window, nil, &ctx.surface))
}

destroy_surface :: proc(ctx: ^RenderContext) {
	vk.DestroySurfaceKHR(ctx.instance, ctx.surface, nil)
}

pick_suitable_physical_device :: proc(ctx: ^RenderContext) {
	must(pick_physical_device(ctx))
}

create_logical_device :: proc(ctx: ^RenderContext) {
	// Setup logical device, 
	indices := find_queue_families(ctx.physical_device, ctx.surface)
	{
		// TODO: this is kinda messy.
		indices_set := make(map[u32]struct {
			}, allocator = context.temp_allocator)
		indices_set[indices.graphics.?] = {}
		indices_set[indices.present.?] = {}

		queue_create_infos := make(
			[dynamic]vk.DeviceQueueCreateInfo,
			0,
			len(indices_set),
			context.temp_allocator,
		)
		for _ in indices_set {
			append(
				&queue_create_infos,
				vk.DeviceQueueCreateInfo {
					sType = .DEVICE_QUEUE_CREATE_INFO,
					queueFamilyIndex = indices.graphics.?,
					queueCount = 1,
					pQueuePriorities = raw_data([]f32{1}),
				}, // Scheduling priority between 0 and 1.
			)
		}

		device_create_info := vk.DeviceCreateInfo {
			sType                   = .DEVICE_CREATE_INFO,
			pQueueCreateInfos       = raw_data(queue_create_infos),
			queueCreateInfoCount    = u32(len(queue_create_infos)),
			enabledLayerCount       = ctx.instance_info.enabledLayerCount,
			ppEnabledLayerNames     = ctx.instance_info.ppEnabledLayerNames,
			ppEnabledExtensionNames = raw_data(DEVICE_EXTENSIONS),
			enabledExtensionCount   = u32(len(DEVICE_EXTENSIONS)),
		}

		must(vk.CreateDevice(ctx.physical_device, &device_create_info, nil, &ctx.device))

		vk.GetDeviceQueue(ctx.device, indices.graphics.?, 0, &ctx.graphics_queue)
		vk.GetDeviceQueue(ctx.device, indices.present.?, 0, &ctx.present_queue)
	}
}

destroy_logical_device :: proc(ctx: ^RenderContext) {
	vk.DestroyDevice(ctx.device, nil)
}

create_swapchain :: proc(ctx: ^RenderContext) {
	indices := find_queue_families(ctx.physical_device, ctx.surface)

	// Setup swapchain.
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


create_render_pass :: proc(ctx: ^RenderContext) {
	color_attachment := vk.AttachmentDescription {
		format         = ctx.swapchain.format.format,
		samples        = {._1},
		loadOp         = .CLEAR,
		storeOp        = .STORE,
		stencilLoadOp  = .DONT_CARE,
		stencilStoreOp = .DONT_CARE,
		initialLayout  = .UNDEFINED,
		finalLayout    = .PRESENT_SRC_KHR,
	}

	color_attachment_ref := vk.AttachmentReference {
		attachment = 0,
		layout     = .COLOR_ATTACHMENT_OPTIMAL,
	}

	subpass := vk.SubpassDescription {
		pipelineBindPoint    = .GRAPHICS,
		colorAttachmentCount = 1,
		pColorAttachments    = &color_attachment_ref,
	}

	dependency := vk.SubpassDependency {
		srcSubpass    = vk.SUBPASS_EXTERNAL,
		dstSubpass    = 0,
		srcStageMask  = {.COLOR_ATTACHMENT_OUTPUT},
		srcAccessMask = {},
		dstStageMask  = {.COLOR_ATTACHMENT_OUTPUT},
		dstAccessMask = {.COLOR_ATTACHMENT_WRITE},
	}

	render_pass := vk.RenderPassCreateInfo {
		sType           = .RENDER_PASS_CREATE_INFO,
		attachmentCount = 1,
		pAttachments    = &color_attachment,
		subpassCount    = 1,
		pSubpasses      = &subpass,
		dependencyCount = 1,
		pDependencies   = &dependency,
	}

	must(vk.CreateRenderPass(ctx.device, &render_pass, nil, &ctx.render_pass))
}

destroy_render_pass :: proc(ctx: ^RenderContext) {
	vk.DestroyRenderPass(ctx.device, ctx.render_pass, nil)
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

create_graphic_pipeline :: proc(ctx: ^RenderContext) {
	shader_stages := [2]vk.PipelineShaderStageCreateInfo{}

	vert_shader_module := create_shader_module(ctx.device, SHADER_VERT)
	shader_stages[0] = vk.PipelineShaderStageCreateInfo {
		sType  = .PIPELINE_SHADER_STAGE_CREATE_INFO,
		stage  = {.VERTEX},
		module = vert_shader_module,
		pName  = "main",
	}

	frag_shader_module := create_shader_module(ctx.device, SHADER_FRAG)
	shader_stages[1] = vk.PipelineShaderStageCreateInfo {
		sType  = .PIPELINE_SHADER_STAGE_CREATE_INFO,
		stage  = {.FRAGMENT},
		module = frag_shader_module,
		pName  = "main",
	}

	defer vk.DestroyShaderModule(ctx.device, vert_shader_module, nil)
	defer vk.DestroyShaderModule(ctx.device, frag_shader_module, nil)

	dynamic_states := []vk.DynamicState{.VIEWPORT, .SCISSOR}
	dynamic_state := vk.PipelineDynamicStateCreateInfo {
		sType             = .PIPELINE_DYNAMIC_STATE_CREATE_INFO,
		dynamicStateCount = 2,
		pDynamicStates    = raw_data(dynamic_states),
	}

	vertex_input_info := vk.PipelineVertexInputStateCreateInfo {
		sType = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
	}

	input_assembly := vk.PipelineInputAssemblyStateCreateInfo {
		sType    = .PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
		topology = .TRIANGLE_LIST,
	}

	viewport_state := vk.PipelineViewportStateCreateInfo {
		sType         = .PIPELINE_VIEWPORT_STATE_CREATE_INFO,
		viewportCount = 1,
		scissorCount  = 1,
	}

	rasterizer := vk.PipelineRasterizationStateCreateInfo {
		sType       = .PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
		polygonMode = .FILL,
		lineWidth   = 1,
		cullMode    = {.BACK},
		frontFace   = .CLOCKWISE,
	}

	multisampling := vk.PipelineMultisampleStateCreateInfo {
		sType                = .PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
		rasterizationSamples = {._1},
		minSampleShading     = 1,
	}

	color_blend_attachment := vk.PipelineColorBlendAttachmentState {
		colorWriteMask = {.R, .G, .B, .A},
	}

	color_blending := vk.PipelineColorBlendStateCreateInfo {
		sType           = .PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
		attachmentCount = 1,
		pAttachments    = &color_blend_attachment,
	}

	pipeline_layout := vk.PipelineLayoutCreateInfo {
		sType = .PIPELINE_LAYOUT_CREATE_INFO,
	}
	must(vk.CreatePipelineLayout(ctx.device, &pipeline_layout, nil, &ctx.pipeline_layout))

	pipeline := vk.GraphicsPipelineCreateInfo {
		sType               = .GRAPHICS_PIPELINE_CREATE_INFO,
		stageCount          = 2,
		pStages             = &shader_stages[0],
		pVertexInputState   = &vertex_input_info,
		pInputAssemblyState = &input_assembly,
		pViewportState      = &viewport_state,
		pRasterizationState = &rasterizer,
		pMultisampleState   = &multisampling,
		pColorBlendState    = &color_blending,
		pDynamicState       = &dynamic_state,
		layout              = ctx.pipeline_layout,
		renderPass          = ctx.render_pass,
		subpass             = 0,
		basePipelineIndex   = -1,
	}
	must(vk.CreateGraphicsPipelines(ctx.device, 0, 1, &pipeline, nil, &ctx.pipeline))
}

destroy_graphic_pipline :: proc(ctx: ^RenderContext) {
	vk.DestroyPipelineLayout(ctx.device, ctx.pipeline_layout, nil)
	vk.DestroyPipeline(ctx.device, ctx.pipeline, nil)
}

create_command_pool :: proc(ctx: ^RenderContext) {
	indices := find_queue_families(ctx.physical_device, ctx.surface)
	pool_info := vk.CommandPoolCreateInfo {
		sType            = .COMMAND_POOL_CREATE_INFO,
		flags            = {.RESET_COMMAND_BUFFER},
		queueFamilyIndex = indices.graphics.?,
	}
	must(vk.CreateCommandPool(ctx.device, &pool_info, nil, &ctx.command_pool))
}

destroy_command_pool :: proc(ctx: ^RenderContext) {
	vk.DestroyCommandPool(ctx.device, ctx.command_pool, nil)
}

create_command_buffers :: proc(ctx: ^RenderContext) {
	alloc_info := vk.CommandBufferAllocateInfo {
		sType              = .COMMAND_BUFFER_ALLOCATE_INFO,
		commandPool        = ctx.command_pool,
		level              = .PRIMARY,
		commandBufferCount = 1,
	}
	must(vk.AllocateCommandBuffers(ctx.device, &alloc_info, &ctx.command_buffer))
}

create_sync_obj :: proc(ctx: ^RenderContext) {
	// ctx.image_available_semaphores = make([]vk.Semaphore, length)

	sem_info := vk.SemaphoreCreateInfo {
		sType = .SEMAPHORE_CREATE_INFO,
	}
	fence_info := vk.FenceCreateInfo {
		sType = .FENCE_CREATE_INFO,
		flags = {.SIGNALED},
	}
	must(vk.CreateFence(ctx.device, &fence_info, nil, &ctx.fence))
	must(vk.CreateSemaphore(ctx.device, &sem_info, nil, &ctx.image_available_semaphore))
	// must(vk.CreateSemaphore(ctx.device, &sem_info, nil, &ctx.render_finished_semaphore))
}

destroy_sync_obj :: proc(ctx: ^RenderContext) {
	// for sem in ctx.image_available_semaphores {vk.DestroySemaphore(ctx.device, sem, nil)}
	vk.DestroySemaphore(ctx.device, ctx.image_available_semaphore, nil)
	// vk.DestroySemaphore(ctx.device, ctx.render_finished_semaphore, nil)
	vk.DestroyFence(ctx.device, ctx.fence, nil)
}

@(private)
@(require_results)
pick_physical_device :: proc(ctx: ^RenderContext) -> vk.Result {

	score_physical_device :: proc(ctx: ^RenderContext, device: vk.PhysicalDevice) -> (score: int) {
		props: vk.PhysicalDeviceProperties
		vk.GetPhysicalDeviceProperties(device, &props)

		name := byte_arr_str(&props.deviceName)
		log.infof("vulkan: evaluating device %q", name)
		defer log.infof("vulkan: device %q scored %v", name, score)

		features: vk.PhysicalDeviceFeatures
		vk.GetPhysicalDeviceFeatures(device, &features)

		// // App can't function without geometry shaders.
		// if !features.geometryShader {
		// 	log.info("vulkan: device does not support geometry shaders")
		// 	return 0
		// }

		// Need certain extensions supported.
		{
			extensions, result := physical_device_extensions(device, context.temp_allocator)
			if result != .SUCCESS {
				log.infof("vulkan: enumerate device extension properties failed: %v", result)
				return 0
			}

			required_loop: for required in DEVICE_EXTENSIONS {
				for &extension in extensions {
					extension_name := byte_arr_str(&extension.extensionName)
					if extension_name == string(required) {
						continue required_loop
					}
				}

				log.infof("vulkan: device does not support required extension %q", required)
				return 0
			}
		}

		// Check if swapchain is adequately supported.
		{
			support, result := query_swapchain_support(device, ctx.surface, context.temp_allocator)
			if result != .SUCCESS {
				log.infof("vulkan: query swapchain support failure: %v", result)
				return 0
			}

			// Need at least a format and present mode.
			if len(support.formats) == 0 || len(support.presentModes) == 0 {
				log.info("vulkan: device does not support swapchain")
				return 0
			}
		}

		families := find_queue_families(device, ctx.surface)
		if _, has_graphics := families.graphics.?; !has_graphics {
			log.info("vulkan: device does not have a graphics queue")
			return 0
		}
		if _, has_present := families.present.?; !has_present {
			log.info("vulkan: device does not have a presentation queue")
			return 0
		}

		// Favor GPUs.
		switch props.deviceType {
		case .DISCRETE_GPU:
			score += 300_000
		case .INTEGRATED_GPU:
			score += 200_000
		case .VIRTUAL_GPU:
			score += 100_000
		case .CPU, .OTHER:
		}
		log.infof("vulkan: scored %i based on device type %v", score, props.deviceType)

		// Maximum texture size.
		score += int(props.limits.maxImageDimension2D)
		log.infof(
			"vulkan: added the max 2D image dimensions (texture size) of %v to the score",
			props.limits.maxImageDimension2D,
		)
		return
	}

	count: u32
	vk.EnumeratePhysicalDevices(ctx.instance, &count, nil) or_return
	if count == 0 {log.panic("vulkan: no GPU found")}

	devices := make([]vk.PhysicalDevice, count, context.temp_allocator)
	vk.EnumeratePhysicalDevices(ctx.instance, &count, raw_data(devices)) or_return

	best_device_score := -1
	for device in devices {
		if score := score_physical_device(ctx, device); score > best_device_score {
			ctx.physical_device = device
			best_device_score = score
		}
	}

	if best_device_score <= 0 {
		log.panic("vulkan: no suitable GPU found")
	}
	return .SUCCESS
}

Queue_Family_Indices :: struct {
	graphics: Maybe(u32),
	present:  Maybe(u32),
}

find_queue_families :: proc(
	device: vk.PhysicalDevice,
	surface: vk.SurfaceKHR,
) -> (
	ids: Queue_Family_Indices,
) {
	count: u32
	vk.GetPhysicalDeviceQueueFamilyProperties(device, &count, nil)

	families := make([]vk.QueueFamilyProperties, count, context.temp_allocator)
	vk.GetPhysicalDeviceQueueFamilyProperties(device, &count, raw_data(families))

	for family, i in families {
		if .GRAPHICS in family.queueFlags {
			ids.graphics = u32(i)
		}

		supported: b32
		vk.GetPhysicalDeviceSurfaceSupportKHR(device, u32(i), surface, &supported)
		if supported {
			ids.present = u32(i)
		}

		// Found all needed queues?
		_, has_graphics := ids.graphics.?
		_, has_present := ids.present.?
		if has_graphics && has_present {
			break
		}
	}

	return
}

Swapchain_Support :: struct {
	capabilities: vk.SurfaceCapabilitiesKHR,
	formats:      []vk.SurfaceFormatKHR,
	presentModes: []vk.PresentModeKHR,
}

@(private)
query_swapchain_support :: proc(
	device: vk.PhysicalDevice,
	surface: vk.SurfaceKHR,
	allocator := context.temp_allocator,
) -> (
	support: Swapchain_Support,
	result: vk.Result,
) {
	// NOTE: looks like a wrong binding with the third arg being a multipointer.
	vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(device, surface, &support.capabilities) or_return

	{
		count: u32
		vk.GetPhysicalDeviceSurfaceFormatsKHR(device, surface, &count, nil) or_return

		support.formats = make([]vk.SurfaceFormatKHR, count, allocator)
		vk.GetPhysicalDeviceSurfaceFormatsKHR(
			device,
			surface,
			&count,
			raw_data(support.formats),
		) or_return
	}

	{
		count: u32
		vk.GetPhysicalDeviceSurfacePresentModesKHR(device, surface, &count, nil) or_return

		support.presentModes = make([]vk.PresentModeKHR, count, allocator)
		vk.GetPhysicalDeviceSurfacePresentModesKHR(
			device,
			surface,
			&count,
			raw_data(support.presentModes),
		) or_return
	}

	return
}

choose_swapchain_surface_format :: proc(formats: []vk.SurfaceFormatKHR) -> vk.SurfaceFormatKHR {
	for format in formats {
		if format.format == .B8G8R8A8_SRGB && format.colorSpace == .SRGB_NONLINEAR {
			return format
		}
	}

	// Fallback non optimal.
	return formats[0]
}

choose_swapchain_present_mode :: proc(modes: []vk.PresentModeKHR) -> vk.PresentModeKHR {
	// We would like mailbox for the best tradeoff between tearing and latency.
	for mode in modes {
		if mode == .MAILBOX {
			return .MAILBOX
		}
	}
	log.error("Fifo selected")

	// As a fallback, fifo (basically vsync) is always available.
	return .FIFO
}

choose_swapchain_extent :: proc(
	window: glfw.WindowHandle,
	capabilities: vk.SurfaceCapabilitiesKHR,
) -> vk.Extent2D {
	if capabilities.currentExtent.width != max(u32) {
		return capabilities.currentExtent
	}

	width, height := glfw.GetFramebufferSize(window)
	return (vk.Extent2D {
				width = clamp(
					u32(width),
					capabilities.minImageExtent.width,
					capabilities.maxImageExtent.width,
				),
				height = clamp(
					u32(height),
					capabilities.minImageExtent.height,
					capabilities.maxImageExtent.height,
				),
			})
}

vk_messenger_callback :: proc "system" (
	messageSeverity: vk.DebugUtilsMessageSeverityFlagsEXT,
	messageTypes: vk.DebugUtilsMessageTypeFlagsEXT,
	pCallbackData: ^vk.DebugUtilsMessengerCallbackDataEXT,
	pUserData: rawptr,
) -> b32 {
	context = g_logger_context

	level: log.Level
	if .ERROR in messageSeverity {
		level = .Error
	} else if .WARNING in messageSeverity {
		level = .Warning
	} else if .INFO in messageSeverity {
		level = .Info
	} else {
		level = .Debug
	}

	log.logf(level, "vulkan[%v]: %s", messageTypes, pCallbackData.pMessage)
	return false
}

@(private)
physical_device_extensions :: proc(
	device: vk.PhysicalDevice,
	allocator := context.temp_allocator,
) -> (
	exts: []vk.ExtensionProperties,
	res: vk.Result,
) {
	count: u32
	vk.EnumerateDeviceExtensionProperties(device, nil, &count, nil) or_return

	exts = make([]vk.ExtensionProperties, count, allocator)
	vk.EnumerateDeviceExtensionProperties(device, nil, &count, raw_data(exts)) or_return

	return
}

create_shader_module :: proc(device: vk.Device, code: []byte) -> (module: vk.ShaderModule) {
	as_u32 := slice.reinterpret([]u32, code)

	create_info := vk.ShaderModuleCreateInfo {
		sType    = .SHADER_MODULE_CREATE_INFO,
		codeSize = len(code),
		pCode    = raw_data(as_u32),
	}
	must(vk.CreateShaderModule(device, &create_info, nil, &module))
	return
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

record_command_buffer :: proc(
	ctx: ^RenderContext,
	command_buffer: vk.CommandBuffer,
	image_index: u32,
) {
	begin_info := vk.CommandBufferBeginInfo {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
	}
	must(vk.BeginCommandBuffer(command_buffer, &begin_info))

	clear_color := vk.ClearValue{}
	clear_color.color.float32 = {0.0, 0.0, 0.0, 1.0}

	render_pass_info := vk.RenderPassBeginInfo {
		sType = .RENDER_PASS_BEGIN_INFO,
		renderPass = ctx.render_pass,
		framebuffer = ctx.swapchain.frame_buffers[image_index],
		renderArea = {extent = ctx.swapchain.extent},
		clearValueCount = 1,
		pClearValues = &clear_color,
	}
	vk.CmdBeginRenderPass(command_buffer, &render_pass_info, .INLINE)

	vk.CmdBindPipeline(command_buffer, .GRAPHICS, ctx.pipeline)

	viewport := vk.Viewport {
		width    = f32(ctx.swapchain.extent.width),
		height   = f32(ctx.swapchain.extent.height),
		maxDepth = 1.0,
	}
	vk.CmdSetViewport(command_buffer, 0, 1, &viewport)

	scissor := vk.Rect2D {
		extent = ctx.swapchain.extent,
	}
	vk.CmdSetScissor(command_buffer, 0, 1, &scissor)

	vk.CmdDraw(command_buffer, 3, 1, 0, 0)

	vk.CmdEndRenderPass(command_buffer)

	must(vk.EndCommandBuffer(command_buffer))
}

byte_arr_str :: proc(arr: ^[$N]byte) -> string {
	return strings.truncate_to_byte(string(arr[:]), 0)
}

must :: proc(result: vk.Result, loc := #caller_location) {
	if result != .SUCCESS {
		log.panicf("vulkan failure %v", result, location = loc)
	}
}
