package ve

import "base:runtime"
import hm "container/handle_map"
import sm "core:container/small_array"
import "core:log"
import "core:mem"
import "core:slice"
import "core:time"
import "lib/vma"
import vk "vendor:vulkan"

Surface_Handle :: distinct hm.Handle

Surface_Manager :: struct {
	surfaces: hm.Handle_Map(Surface, Surface_Handle),
}

Surface_Color_Attachment :: struct {
	info:         vk.RenderingAttachmentInfo,
	msaa_texture: Maybe(Texture),
	texture_h:    Texture_Handle,
	sampler_info: Sampler_Info,
}

Surface_Color_Attachments :: sm.Small_Array(MAX_COLOR_ATTACHMENTS, Surface_Color_Attachment)

Surface_Depth_Attachment :: union {
	Surface_Common_Depth_Attachment,
	Surface_Readable_Depth_Attachment,
}

Stencil_Info :: struct {
	clear_value: u32,
}

Surface_Common_Depth_Attachment :: struct {
	resource: Texture,
	info:     vk.RenderingAttachmentInfo,
}

Surface_Readable_Depth_Attachment :: struct {
	msaa_texture: Maybe(Texture),
	texture_h:    Texture_Handle,
	info:         vk.RenderingAttachmentInfo,
	sampler_info: Sampler_Info,
}

Surface :: struct {
	fit_screen:        bool,
	width, height:     u32,
	transform:         Gfx_Transform,
	color_attachments: Surface_Color_Attachments,
	depth_attachment:  Maybe(Surface_Depth_Attachment),
	sample_count:      Sample_Count_Flag,
}

DEFAULT_SURFACE_SAMPLER_INFO :: Sampler_Info {
	mag_filter        = .Linear,
	min_filter        = .Linear,
	address_mode_u    = .Clamp_To_Border,
	address_mode_v    = .Clamp_To_Border,
	address_mode_w    = .Clamp_To_Border,
	anisotropy_enable = false,
	border_color      = .Transparent_Black,
	mipmap_mode       = .Linear,
	lod_clamp         = SAMPLER_LOD_CLAMP_NONE,
}

create_surface_fit_screen :: proc(
	sample_count: Sample_Count_Flag = ._1,
	allocator := context.allocator,
	loc := #caller_location,
) -> Surface_Handle {
	assert_gfx_ctx(loc)
	surface := Surface{}
	_surface_init_fit_screen(&surface, sample_count)

	return _surface_manager_add_surface(ctx.gfx.surface_manager, surface)
}

create_surface_with_size :: proc(
	width, height: u32,
	sample_count: Sample_Count_Flag = ._1,
	allocator := context.allocator,
	loc := #caller_location,
) -> Surface_Handle {
	assert_gfx_ctx(loc)
	assert(width > 0 && height > 0, "Surface dimensions must be greater than zero", loc)
	surface := Surface{}
	_surface_init_with_size(&surface, width, height, sample_count)

	return _surface_manager_add_surface(ctx.gfx.surface_manager, surface)
}

destroy_surface :: proc(surface_h: Surface_Handle, loc := #caller_location) {
	assert_gfx_ctx(loc)

	_surface_manager_destroy_surface(ctx.gfx.surface_manager, surface_h, loc)
}

@(require_results)
get_surface :: proc(surface_h: Surface_Handle, loc := #caller_location) -> (^Surface, bool) {
	assert_gfx_ctx(loc)

	return _surface_manager_get_surface(ctx.gfx.surface_manager, surface_h, loc)
}

@(require_results)
surface_add_color_attachment :: proc(
	surface: ^Surface,
	clear_value: color = {0.0, 0.0, 0.0, 1.0},
	format: Pixel_Format = .RGBA_norm_u8,
	sampler_info: Sampler_Info = DEFAULT_SURFACE_SAMPLER_INFO,
	loc := #caller_location,
) -> Texture_Handle {
	assert_gfx_ctx(loc)
	assert_not_nil(surface, loc)
	// _, has_color_attachment := 
	// assert(has_color_attachment == false, "Surface already has a color attachment.", loc)

	w, h := surface.width, surface.height

	vk_format := _format_to_vk(format)
	color_attachment := Surface_Color_Attachment{}
	if surface.sample_count == ._1 {
		color_res := _create_surface_color_resolve_resource(w, h, vk_format, sampler_info)

		color_attachment.texture_h = store_texture(color_res, loc)

		color_attachment.info = {
			sType = .RENDERING_ATTACHMENT_INFO,
			pNext = nil,
			imageView = color_res.view,
			imageLayout = .ATTACHMENT_OPTIMAL,
			resolveMode = {},
			loadOp = .CLEAR,
			storeOp = .STORE,
			clearValue = vk.ClearValue{color = {float32 = clear_value}},
		}
	} else {
		msaa := _create_surface_color_resource(w, h, vk_format, surface.sample_count)
		resolve := _create_surface_color_resolve_resource(w, h, vk_format, sampler_info)

		color_attachment.texture_h = store_texture(resolve)
		color_attachment.msaa_texture = msaa

		color_attachment.info = {
			sType = .RENDERING_ATTACHMENT_INFO,
			pNext = nil,
			imageView = msaa.view,
			imageLayout = .ATTACHMENT_OPTIMAL,
			resolveMode = {.AVERAGE_KHR},
			resolveImageView = resolve.view,
			resolveImageLayout = .GENERAL,
			loadOp = .CLEAR,
			storeOp = .STORE,
			clearValue = vk.ClearValue{color = {float32 = clear_value}},
		}
	}
	color_attachment.sampler_info = sampler_info

	sm.append_elem(&surface.color_attachments, color_attachment)

	return color_attachment.texture_h
}

surface_add_depth_attachment :: proc(
	surface: ^Surface,
	clear_value: f32 = 1,
	stencil_info: Maybe(Stencil_Info) = nil,
	loc := #caller_location,
) {
	assert_not_nil(surface, loc)
	_, has_depth_attachment := surface.depth_attachment.?
	assert(has_depth_attachment == false, "Surface already has a depth attachment.", loc)

	stencil, has_stencil := stencil_info.?
	width, height := surface.width, surface.height

	sc := begin_single_cmd()
	depth_resource := _create_surface_depth_resource(width, height, sc.cmd, surface.sample_count, has_stencil)
	end_single_cmd(sc)

	depth_attachment := Surface_Common_Depth_Attachment {
		resource = depth_resource,
		info = {
			sType = .RENDERING_ATTACHMENT_INFO,
			pNext = nil,
			imageView = depth_resource.view,
			imageLayout = .DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
			loadOp = .CLEAR,
			storeOp = .DONT_CARE,
			clearValue = vk.ClearValue{depthStencil = {clear_value, stencil.clear_value}},
		},
	}

	surface.depth_attachment = depth_attachment
}

surface_add_readable_depth_attachment :: proc(
	surface: ^Surface,
	clear_value: f32 = 1,
	sampler_info: Sampler_Info = DEFAULT_SAMPLER_INFO,
	loc := #caller_location,
) -> Texture_Handle {
	assert_not_nil(surface, loc)
	_, has_depth_attachment := surface.depth_attachment.?
	assert(has_depth_attachment == false, "Surface already has a depth attachment.", loc)

	w, h := surface.width, surface.height

	depth_attachment := Surface_Readable_Depth_Attachment{}

	sc := begin_single_cmd()
	depth_resource := _create_surface_depth_resource_sampled(w, h, sc.cmd, sampler_info)
	depth_attachment.texture_h = store_texture(depth_resource)

	if surface.sample_count == ._1 {
		depth_attachment.info = {
			sType = .RENDERING_ATTACHMENT_INFO,
			pNext = nil,
			imageView = depth_resource.view,
			imageLayout = .DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
			loadOp = .CLEAR,
			storeOp = .STORE,
			clearValue = vk.ClearValue{depthStencil = {clear_value, 0}},
		}
	} else {
		msaa := _create_surface_depth_resource(w, h, sc.cmd, surface.sample_count, false)
		depth_attachment.msaa_texture = msaa
		depth_attachment.info = {
			sType = .RENDERING_ATTACHMENT_INFO,
			pNext = nil,
			imageView = msaa.view,
			imageLayout = .DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
			resolveMode = {.AVERAGE_KHR},
			resolveImageView = depth_resource.view,
			resolveImageLayout = .GENERAL,
			loadOp = .CLEAR,
			storeOp = .STORE,
			clearValue = vk.ClearValue{depthStencil = {clear_value, 0}},
		}
	}
	end_single_cmd(sc)

	depth_attachment.sampler_info = sampler_info
	surface.depth_attachment = depth_attachment

	return depth_attachment.texture_h
}

@(require_results)
begin_surface :: proc(
	surface: ^Surface,
	frame_data: Frame_Data,
	active_color_attachments: []int = nil,
	loc := #caller_location,
) -> Frame_Data {
	assert_not_nil(surface, loc)

	cmd_set_viewport(frame_data, surface.width, surface.height)
	cmd_set_scissor(frame_data, surface.width, surface.height)

	cmd := frame_data.cmd

	depth_attachment, has_depth_attachment := surface.depth_attachment.?
	has_color_attachments := sm.len(surface.color_attachments) > 0

	begin_info := vk.CommandBufferBeginInfo {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
	}

	p_color_attachments: sm.Small_Array(MAX_COLOR_ATTACHMENTS, vk.RenderingAttachmentInfo)
	p_depth_attachment: ^vk.RenderingAttachmentInfo = nil

	frame_data_acrive_color: sm.Small_Array(MAX_COLOR_ATTACHMENTS, int)

	src_color_attachments: Surface_Color_Attachments
	if active_color_attachments != nil {
		for ac in active_color_attachments {
			assert(ac < surface.color_attachments.len && ac > 0)
			assert(slice.count(active_color_attachments[:], ac) == 1)
			sm.append(&src_color_attachments, sm.get(surface.color_attachments, ac))
			sm.append(&frame_data_acrive_color, ac)
		}
	} else {
		src_color_attachments = surface.color_attachments
		for _, i in sm.slice(&src_color_attachments) {
			sm.append(&frame_data_acrive_color, i)
		}
	}

	assert(sm.len(src_color_attachments) > 0 || has_depth_attachment, "Couldn't begin_surface() without attachments")

	for ca, i in sm.slice(&src_color_attachments) {
		msaa, has_msaa := ca.msaa_texture.?
		texture, ok := get_texture_h(ca.texture_h, loc)
		assert(ok)

		target := &msaa if has_msaa else texture
		_transition_image_layout(cmd, target.image, {.COLOR}, target.format, .UNDEFINED, .COLOR_ATTACHMENT_OPTIMAL, 1)

		sm.append(&p_color_attachments, ca.info)
	}

	depth_format: vk.Format
	if has_depth_attachment {
		switch &attachment in depth_attachment {
		case Surface_Common_Depth_Attachment:
			p_depth_attachment = &attachment.info
			depth_format = attachment.resource.format
		case Surface_Readable_Depth_Attachment:
			p_depth_attachment = &attachment.info
			msaa, has_msaa := attachment.msaa_texture.?

			texture, ok := get_texture_h(attachment.texture_h)
			assert(ok)
			depth_format = texture.format
			target: ^Texture = &msaa if has_msaa else texture

			_transition_image_layout(
				frame_data.cmd,
				target.image,
				{.DEPTH},
				target.format,
				.SHADER_READ_ONLY_OPTIMAL,
				.DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
				1,
			)
		}
	}

	rendering_info := vk.RenderingInfo {
		sType = .RENDERING_INFO,
		renderArea = {extent = {width = surface.width, height = surface.height}},
		layerCount = 1,
		colorAttachmentCount = cast(u32)src_color_attachments.len,
		pColorAttachments = raw_data(sm.slice(&p_color_attachments)),
		pDepthAttachment = p_depth_attachment,
		pStencilAttachment = p_depth_attachment if _has_stencil_component(depth_format) else nil,
	}

	vk.CmdBeginRendering(cmd, &rendering_info)

	frame_data := frame_data
	frame_data.surface_info = Surface_Info {
		type                     = .Surface,
		sample_count             = surface.sample_count,
		depth_format             = depth_format if has_depth_attachment else .UNDEFINED,
		width                    = surface.width,
		height                   = surface.height,
		active_color_attachments = frame_data_acrive_color,
	}

	if (has_color_attachments) {
		for ca in sm.slice(&src_color_attachments) {
			texture, ok := get_texture_h(ca.texture_h)
			assert(ok)
			sm.push(&frame_data.surface_info.color_formats, texture.format)
		}
	}

	return frame_data
}

end_surface :: proc(surface: ^Surface, frame_data: Frame_Data, loc := #caller_location) {
	frame_data := frame_data
	assert_not_nil(surface, loc)

	vk.CmdEndRendering(frame_data.cmd)

	has_color_attachments := sm.len(surface.color_attachments) > 0
	depth_attachment, has_depth_attachment := surface.depth_attachment.?

	for ca, i in sm.slice(&surface.color_attachments) {
		if !slice.contains(sm.slice(&frame_data.surface_info.active_color_attachments), i) {
			continue
		}
		msaa, has_msaa := ca.msaa_texture.?
		texture, ok := get_texture_h(ca.texture_h, loc)
		assert(ok)

		target := &msaa if has_msaa else texture
		_transition_image_layout(
			frame_data.cmd,
			target.image,
			{.COLOR},
			target.format,
			.COLOR_ATTACHMENT_OPTIMAL,
			.SHADER_READ_ONLY_OPTIMAL,
			1,
		)
	}

	if has_depth_attachment {
		switch attachment in depth_attachment {
		case Surface_Common_Depth_Attachment:
		case Surface_Readable_Depth_Attachment:
			texture, ok := get_texture_h(attachment.texture_h)
			msaa, has_msaa := attachment.msaa_texture.?
			assert(ok)

			sc := begin_single_cmd()
			target := &msaa if has_msaa else texture

			_transition_image_layout(
				sc.cmd,
				target.image,
				{.DEPTH},
				target.format,
				.DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
				.SHADER_READ_ONLY_OPTIMAL,
				1,
			)
			end_single_cmd(sc)
		}
	}
}

surface_resize :: proc(surface: ^Surface, width, height: u32, loc := #caller_location) {
	assert(surface.fit_screen == false, "Manual resize not allowed on fit_screen surfaces.")
	_surface_resize(surface, width, height, loc)
}

@(private)
_init_surface_manager :: proc() {
	assert(ctx.gfx.surface_manager == nil)
	ctx.gfx.surface_manager = new(Surface_Manager)
	_surface_manager_init(ctx.gfx.surface_manager)
}

@(private)
_destroy_surface_manager :: proc(loc := #caller_location) {
	_surface_manager_destroy(ctx.gfx.surface_manager, loc)
	free(ctx.gfx.surface_manager)
}

@(private = "file")
_surface_manager_init :: proc(sm: ^Surface_Manager, loc := #caller_location) {
	assert_not_nil(sm, loc)
}

@(private = "file")
_surface_manager_destroy :: proc(sm: ^Surface_Manager, loc := #caller_location) {
	assert_gfx_ctx(loc)
	assert_not_nil(sm, loc)

	for &surface in sm.surfaces.values {
		_surface_destroy(&surface)
	}

	hm.destroy(&sm.surfaces)
}

@(private)
@(require_results)
_surface_manager_add_surface :: proc(
	sm: ^Surface_Manager,
	surface: Surface,
	loc := #caller_location,
) -> Surface_Handle {
	assert_gfx_ctx(loc)
	assert_not_nil(sm, loc)

	return hm.insert(&sm.surfaces, surface)
}

@(private)
@(require_results)
_surface_manager_get_surface :: proc(
	sm: ^Surface_Manager,
	surface_h: Surface_Handle,
	loc := #caller_location,
) -> (
	^Surface,
	bool,
) {
	assert_not_nil(sm, loc)

	return hm.get(&sm.surfaces, surface_h)
}

@(private)
_surface_manager_destroy_surface :: proc(sm: ^Surface_Manager, surface_h: Surface_Handle, loc := #caller_location) {
	assert_gfx_ctx(loc)
	assert_not_nil(sm, loc)

	surface, ok := hm.remove(&sm.surfaces, surface_h)

	if ok {
		_surface_destroy(&surface)
	}
}

@(private)
_surface_manager_resize_fit_screen_surfaces :: proc(sm: ^Surface_Manager, loc := #caller_location) {
	assert_gfx_ctx(loc)
	assert_not_nil(sm, loc)

	must(vk.QueueWaitIdle(ctx.gfx.vk_state.graphics_queue))
	w, h := get_screen_width(), get_screen_height()
	for &surface in sm.surfaces.values {
		if surface.fit_screen {
			_surface_resize(&surface, w, h)
		}
	}
}

@(private)
_surface_init_fit_screen :: proc(
	surface: ^Surface,
	sample_count: Sample_Count_Flag,
	allocator := context.allocator,
	loc := #caller_location,
) {
	assert_not_nil(surface, loc)
	assert_gfx_ctx(loc)

	surface.fit_screen = true
	surface.width = get_device_width()
	surface.height = get_device_height()

	init_trf(&surface.transform)

	surface.sample_count = sample_count
}

@(private)
_surface_init_with_size :: proc(
	surface: ^Surface,
	width, height: u32,
	sample_count: Sample_Count_Flag,
	allocator := context.allocator,
	loc := #caller_location,
) {
	assert_not_nil(surface, loc)
	assert_gfx_ctx(loc)

	surface.width = width
	surface.height = height

	init_trf(&surface.transform)

	surface.sample_count = sample_count
}

@(private)
_surface_destroy :: proc(surface: ^Surface, loc := #caller_location) {
	assert_gfx_ctx(loc)
	assert_not_nil(surface, loc)

	depth_attachment, has_depth_attachment := surface.depth_attachment.?

	for ca in sm.slice(&surface.color_attachments) {
		destroy_texture_h(ca.texture_h)
		msaa, has_msaa := ca.msaa_texture.?
		if has_msaa do destroy_texture(&msaa)
	}

	if has_depth_attachment {
		switch &attachment in depth_attachment {
		case Surface_Common_Depth_Attachment:
			destroy_texture(&attachment.resource)
		case Surface_Readable_Depth_Attachment:
			destroy_texture_h(attachment.texture_h)
			msaa, has_msaa := attachment.msaa_texture.?
			if has_msaa do destroy_texture(&msaa)
		}
	}
}

@(private = "file")
_surface_resize :: proc(surface: ^Surface, width, height: u32, loc := #caller_location) {
	surface.width = width
	surface.height = height

	depth_attachment, has_depth_attachment := surface.depth_attachment.?

	_surface_resize_color_attachments(width, height, surface)

	if has_depth_attachment {
		switch &attachment in depth_attachment {
		case Surface_Common_Depth_Attachment:
			has_stencil := _has_stencil_component(attachment.resource.format)

			destroy_texture(&attachment.resource)
			surface.depth_attachment = nil

			if has_stencil {
				surface_add_depth_attachment(
					surface,
					clear_value = attachment.info.clearValue.depthStencil.depth,
					stencil_info = Stencil_Info{clear_value = attachment.info.clearValue.depthStencil.stencil},
				)
			} else {
				surface_add_depth_attachment(surface)
			}
		case Surface_Readable_Depth_Attachment:
			_surface_resize_readable_depth_attachment(width, height, surface)
		}
	}
}

@(private = "file")
@(require_results)
_create_surface_color_resource :: proc(
	width, height: u32,
	format: vk.Format,
	sample_count: Sample_Count_Flag,
	loc := #caller_location,
) -> Texture {
	image, allocation, allocation_info := _create_image(
		width,
		height,
		1,
		sample_count,
		format,
		.OPTIMAL,
		{.COLOR_ATTACHMENT, .SAMPLED},
		.AUTO_PREFER_DEVICE,
		{},
	)

	view := _create_image_view(image, format, {.COLOR}, 1)

	_set_debug_object_name(cast(u64)image, .IMAGE, "surface msaa image")
	_set_debug_object_name(cast(u64)view, .IMAGE_VIEW, "surface msaa view")

	return Texture {
		name = "surface color attachment",
		image = image,
		view = view,
		format = format,
		allocation = allocation,
		allocation_info = allocation_info,
	}
}

@(private = "file")
@(require_results)
_create_surface_color_resolve_resource :: proc(
	width, height: u32,
	format: vk.Format,
	sampler_info: Sampler_Info = DEFAULT_SAMPLER_INFO,
	loc := #caller_location,
) -> Texture {
	image, allocation, allocation_info := _create_image(
		width,
		height,
		1,
		._1,
		format,
		.OPTIMAL,
		{.COLOR_ATTACHMENT, .SAMPLED},
		.AUTO_PREFER_DEVICE,
		{},
	)

	view := _create_image_view(image, format, {.COLOR}, 1)
	sampler: Sampler = create_sampler(sampler_info)

	_set_debug_object_name(cast(u64)image, .IMAGE, "surface resolve image")
	_set_debug_object_name(cast(u64)sampler, .SAMPLER, "surface resolve sampler")
	_set_debug_object_name(cast(u64)view, .IMAGE_VIEW, "surface resolve view")

	return Texture {
		name = "surface resolve color attachment",
		image = image,
		sampler = sampler,
		view = view,
		format = format,
		allocation = allocation,
		allocation_info = allocation_info,
	}
}

@(private = "file")
@(require_results)
_create_surface_depth_resource :: proc(
	width: u32,
	height: u32,
	cmd: Command_Buffer,
	sample_count: Sample_Count_Flag,
	stencil: bool,
	loc := #caller_location,
) -> Texture {
	if stencil {

	}
	format := ctx.gfx.swapchain_cfg.depth_stencil_format if stencil else ctx.gfx.swapchain_cfg.depth_format
	aspect: vk.ImageAspectFlags = {.DEPTH, .STENCIL} if stencil else {.DEPTH}

	image, allocation, allocation_info := _create_image(
		width,
		height,
		1,
		sample_count,
		format,
		.OPTIMAL,
		{.DEPTH_STENCIL_ATTACHMENT},
		.AUTO_PREFER_DEVICE,
		{},
	)

	_transition_image_layout(cmd, image, aspect, format, .UNDEFINED, .DEPTH_STENCIL_ATTACHMENT_OPTIMAL, 1)
	view := _create_image_view(image, format, aspect, 1)

	_set_debug_object_name(cast(u64)image, .IMAGE, "surface depth image")
	_set_debug_object_name(cast(u64)view, .IMAGE_VIEW, "surface depth view")

	return Texture {
		name = "surface depth attachment",
		image = image,
		view = view,
		format = format,
		allocation = allocation,
		allocation_info = allocation_info,
	}
}

@(private = "file")
@(require_results)
_create_surface_depth_resource_sampled :: proc(
	width: u32,
	height: u32,
	cmd: Command_Buffer,
	sampler_info: Sampler_Info,
	loc := #caller_location,
) -> Texture {
	format := ctx.gfx.swapchain_cfg.depth_format
	image, allocation, allocation_info := _create_image(
		width,
		height,
		1,
		._1,
		format,
		.OPTIMAL,
		{.DEPTH_STENCIL_ATTACHMENT, .SAMPLED},
		.AUTO_PREFER_DEVICE,
		{},
	)

	_transition_image_layout(cmd, image, {.DEPTH}, format, .UNDEFINED, .DEPTH_STENCIL_ATTACHMENT_OPTIMAL, 1)

	view := _create_image_view(image, format, {.DEPTH}, 1)
	sampler: Sampler = create_sampler(sampler_info)

	_set_debug_object_name(cast(u64)image, .IMAGE, "surface depth msaa image")
	_set_debug_object_name(cast(u64)view, .IMAGE_VIEW, "surface depth msaa view")
	_set_debug_object_name(cast(u64)sampler, .SAMPLER, "surface depth msaa sampler")

	return Texture {
		name = "surface depth msaa attachment",
		image = image,
		view = view,
		sampler = sampler,
		format = format,
		allocation = allocation,
		allocation_info = allocation_info,
	}
}

@(private = "file")
_surface_resize_color_attachments :: proc(width: u32, height: u32, surface: ^Surface, loc := #caller_location) {
	assert_gfx_ctx(loc)
	assert_not_nil(surface, loc)

	for &ca in sm.slice(&surface.color_attachments) {
		msaa, has_msaa := ca.msaa_texture.?

		resolve := _create_surface_color_resolve_resource(
			width,
			height,
			ctx.gfx.swapchain.color_format.format,
			ca.sampler_info,
		)
		update_texture_h(ca.texture_h, resolve)
		ca.info.imageView = resolve.view

		if has_msaa {
			destroy_texture(&msaa)
			new_msaa := _create_surface_color_resource(
				width,
				height,
				ctx.gfx.swapchain.color_format.format,
				surface.sample_count,
			)
			ca.msaa_texture = new_msaa
			ca.info.imageView = new_msaa.view
			ca.info.resolveImageView = resolve.view
		}
	}
}

@(private = "file")
_surface_resize_readable_depth_attachment :: proc(width: u32, height: u32, surface: ^Surface, loc := #caller_location) {
	assert_gfx_ctx(loc)
	assert_not_nil(surface, loc)

	depth_attachment, has_depth_attachment := surface.depth_attachment.?
	assert(has_depth_attachment)
	attachment, ok := depth_attachment.(Surface_Readable_Depth_Attachment)
	assert(ok)

	msaa, has_msaa := attachment.msaa_texture.?

	sc := begin_single_cmd()

	resolve := _create_surface_depth_resource_sampled(width, height, sc.cmd, attachment.sampler_info)
	update_texture_h(attachment.texture_h, resolve)
	attachment.info.imageView = resolve.view

	if has_msaa {
		destroy_texture(&msaa)
		new_msaa := _create_surface_depth_resource(width, height, sc.cmd, surface.sample_count, false)
		attachment.msaa_texture = new_msaa
		attachment.info.imageView = new_msaa.view
		attachment.info.resolveImageView = resolve.view
	}
	end_single_cmd(sc)

	surface.depth_attachment = attachment
}
