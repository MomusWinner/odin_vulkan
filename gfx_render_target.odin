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

Render_Target_Color_Attachment :: struct {
	info:         vk.RenderingAttachmentInfo,
	msaa_texture: Maybe(Texture),
	texture_h:    Texture_Handle,
	sampler_info: Sampler_Info,
}

Render_Target_Color_Attachments :: sm.Small_Array(MAX_COLOR_ATTACHMENTS, Render_Target_Color_Attachment)

Render_Target_Depth_Attachment :: union {
	Render_Target_Common_Depth_Attachment,
	Render_Target_Readable_Depth_Attachment,
}

Stencil_Info :: struct {
	clear_value: u32,
}

Render_Target_Common_Depth_Attachment :: struct {
	resource: Texture,
	info:     vk.RenderingAttachmentInfo,
}

Render_Target_Readable_Depth_Attachment :: struct {
	msaa_texture: Maybe(Texture),
	texture_h:    Texture_Handle,
	info:         vk.RenderingAttachmentInfo,
	sampler_info: Sampler_Info,
}

Render_Target :: struct {
	width, height:     u32,
	transform:         Gfx_Transform,
	color_attachments: Render_Target_Color_Attachments,
	depth_attachment:  Maybe(Render_Target_Depth_Attachment),
	sample_count:      Sample_Count_Flag,
}

init_render_target :: proc(
	render_target: ^Render_Target,
	width, height: u32,
	sample_count: Sample_Count_Flag,
	allocator := context.allocator,
	loc := #caller_location,
) {
	assert_not_nil(render_target, loc)
	assert_gfx_ctx(loc)

	render_target.width = width
	render_target.height = height

	init_trf(&render_target.transform)

	render_target.sample_count = sample_count
}

destroy_render_target :: proc(render_target: ^Render_Target, loc := #caller_location) {
	assert_gfx_ctx(loc)
	assert_not_nil(render_target, loc)

	depth_attachment, has_depth_attachment := render_target.depth_attachment.?

	for ca in sm.slice(&render_target.color_attachments) {
		destroy_texture_h(ca.texture_h)
		msaa, has_msaa := ca.msaa_texture.?
		if has_msaa do destroy_texture(&msaa)
	}

	if has_depth_attachment {
		switch &attachment in depth_attachment {
		case Render_Target_Common_Depth_Attachment:
			destroy_texture(&attachment.resource)
		case Render_Target_Readable_Depth_Attachment:
			destroy_texture_h(attachment.texture_h)
			msaa, has_msaa := attachment.msaa_texture.?
			if has_msaa do destroy_texture(&msaa)
		}
	}
}


@(require_results)
render_target_add_color_attachment :: proc(
	surface: ^Render_Target,
	clear_value: color = {0.0, 0.0, 0.0, 1.0},
	format: Pixel_Format = .RGBA_norm_u8,
	sampler_info: Sampler_Info = DEFAULT_SURFACE_SAMPLER_INFO,
	loc := #caller_location,
) -> Texture_Handle {
	assert_gfx_ctx(loc)
	assert_not_nil(surface, loc)

	w, h := surface.width, surface.height

	vk_format := _format_to_vk(format)
	color_attachment := Render_Target_Color_Attachment{}
	if surface.sample_count == ._1 {
		color_res := _create_render_target_color_resolve_resource(w, h, vk_format, sampler_info)

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
		msaa := _create_render_target_color_resource(w, h, vk_format, surface.sample_count)
		resolve := _create_render_target_color_resolve_resource(w, h, vk_format, sampler_info)

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

render_target_add_depth_attachment :: proc(
	surface: ^Render_Target,
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
	depth_resource := _create_render_target_depth_resource(width, height, sc.cmd, surface.sample_count, has_stencil)
	end_single_cmd(sc)

	depth_attachment := Render_Target_Common_Depth_Attachment {
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

render_target_add_readable_depth_attachment :: proc(
	surface: ^Render_Target,
	clear_value: f32 = 1,
	sampler_info: Sampler_Info = DEFAULT_SAMPLER_INFO,
	loc := #caller_location,
) -> Texture_Handle {
	assert_not_nil(surface, loc)
	_, has_depth_attachment := surface.depth_attachment.?
	assert(has_depth_attachment == false, "Surface already has a depth attachment.", loc)

	w, h := surface.width, surface.height

	depth_attachment := Render_Target_Readable_Depth_Attachment{}

	sc := begin_single_cmd()
	depth_resource := _create_render_target_depth_resource_sampled(w, h, sc.cmd, sampler_info)
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
		msaa := _create_render_target_depth_resource(w, h, sc.cmd, surface.sample_count, false)
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

begin_render_target :: proc(surface: ^Render_Target, active_color_attachments: []int = nil, loc := #caller_location) {
	assert_not_nil(surface, loc)

	cmd_set_viewport(surface.width, surface.height)
	cmd_set_scissor(surface.width, surface.height)

	cmd := _get_cmd()
	depth_attachment, has_depth_attachment := surface.depth_attachment.?
	has_color_attachments := sm.len(surface.color_attachments) > 0

	begin_info := vk.CommandBufferBeginInfo {
		sType = .COMMAND_BUFFER_BEGIN_INFO,
	}

	p_color_attachments: sm.Small_Array(MAX_COLOR_ATTACHMENTS, vk.RenderingAttachmentInfo)
	p_depth_attachment: ^vk.RenderingAttachmentInfo = nil

	frame_data_acrive_color: sm.Small_Array(MAX_COLOR_ATTACHMENTS, int)

	src_color_attachments: Render_Target_Color_Attachments
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
		_cmd_image_transition_layout(cmd, target.id, .UNDEFINED, .COLOR_ATTACHMENT_OPTIMAL)

		sm.append(&p_color_attachments, ca.info)
	}

	depth_format: vk.Format
	if has_depth_attachment {
		switch &attachment in depth_attachment {
		case Render_Target_Common_Depth_Attachment:
			p_depth_attachment = &attachment.info
			depth_format = attachment.resource.format
		case Render_Target_Readable_Depth_Attachment:
			p_depth_attachment = &attachment.info
			msaa, has_msaa := attachment.msaa_texture.?

			texture, ok := get_texture_h(attachment.texture_h)
			assert(ok)
			depth_format = texture.format
			target: ^Texture = &msaa if has_msaa else texture

			_cmd_image_transition_layout(
				cmd,
				target.id,
				.SHADER_READ_ONLY_OPTIMAL,
				.DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
				vk.ImageSubresourceRange{aspectMask = {.DEPTH}, layerCount = 1, levelCount = 1},
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

	surface_info := Surface_Info {
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
			sm.push(&surface_info.color_formats, texture.format)
		}
	}

	ctx.gfx.frame.surface_info = surface_info
}

end_render_target :: proc(surface: ^Render_Target, loc := #caller_location) {
	assert_not_nil(surface, loc)

	vk.CmdEndRendering(_get_cmd())

	has_color_attachments := sm.len(surface.color_attachments) > 0
	depth_attachment, has_depth_attachment := surface.depth_attachment.?

	for ca, i in sm.slice(&surface.color_attachments) {
		if !slice.contains(sm.slice(&ctx.gfx.frame.surface_info.active_color_attachments), i) {
			continue
		}
		msaa, has_msaa := ca.msaa_texture.?
		texture, ok := get_texture_h(ca.texture_h, loc)
		assert(ok)

		target := &msaa if has_msaa else texture
		_cmd_image_transition_layout(_get_cmd(), target.id, .COLOR_ATTACHMENT_OPTIMAL, .SHADER_READ_ONLY_OPTIMAL)
	}

	if has_depth_attachment {
		switch attachment in depth_attachment {
		case Render_Target_Common_Depth_Attachment:
		case Render_Target_Readable_Depth_Attachment:
			texture, ok := get_texture_h(attachment.texture_h)
			msaa, has_msaa := attachment.msaa_texture.?
			assert(ok)

			sc := begin_single_cmd()
			target := &msaa if has_msaa else texture

			_cmd_image_transition_layout(
				sc.cmd,
				target.id,
				.DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
				.SHADER_READ_ONLY_OPTIMAL,
				vk.ImageSubresourceRange{aspectMask = {.DEPTH}, layerCount = 1, levelCount = 1},
			)
			end_single_cmd(sc)
		}
	}
}

render_target_resize :: proc(surface: ^Render_Target, width, height: u32, loc := #caller_location) {
	_render_target_resize(surface, width, height, loc)
}

@(private = "file")
_render_target_resize :: proc(surface: ^Render_Target, width, height: u32, loc := #caller_location) {
	surface.width = width
	surface.height = height

	depth_attachment, has_depth_attachment := surface.depth_attachment.?

	_render_target_resize_color_attachments(width, height, surface)

	if has_depth_attachment {
		switch &attachment in depth_attachment {
		case Render_Target_Common_Depth_Attachment:
			has_stencil := _has_stencil_component(attachment.resource.format)

			destroy_texture(&attachment.resource)
			surface.depth_attachment = nil

			if has_stencil {
				render_target_add_depth_attachment(
					surface,
					clear_value = attachment.info.clearValue.depthStencil.depth,
					stencil_info = Stencil_Info{clear_value = attachment.info.clearValue.depthStencil.stencil},
				)
			} else {
				render_target_add_depth_attachment(surface)
			}
		case Render_Target_Readable_Depth_Attachment:
			_render_target_resize_readable_depth_attachment(width, height, surface)
		}
	}
}

@(private = "file")
@(require_results)
_create_render_target_color_resource :: proc(
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

	_vk_set_debug_object_name(cast(u64)image, .IMAGE, "surface msaa image")
	_vk_set_debug_object_name(cast(u64)view, .IMAGE_VIEW, "surface msaa view")

	return Texture {
		id = image,
		debug_name = "surface color attachment",
		view = view,
		format = format,
		allocation = allocation,
		allocation_info = allocation_info,
	}
}

@(private = "file")
@(require_results)
_create_render_target_color_resolve_resource :: proc(
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

	_vk_set_debug_object_name(cast(u64)image, .IMAGE, "surface resolve image")
	_vk_set_debug_object_name(cast(u64)sampler, .SAMPLER, "surface resolve sampler")
	_vk_set_debug_object_name(cast(u64)view, .IMAGE_VIEW, "surface resolve view")

	return Texture {
		id = image,
		debug_name = "surface resolve color attachment",
		sampler = sampler,
		view = view,
		format = format,
		allocation = allocation,
		allocation_info = allocation_info,
	}
}

@(private = "file")
@(require_results)
_create_render_target_depth_resource :: proc(
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

	_cmd_image_transition_layout(
		cmd,
		image,
		.UNDEFINED,
		.DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
		vk.ImageSubresourceRange{aspectMask = aspect, levelCount = 1, layerCount = 1},
	)
	view := _create_image_view(image, format, aspect, 1)

	_vk_set_debug_object_name(cast(u64)image, .IMAGE, "surface depth image")
	_vk_set_debug_object_name(cast(u64)view, .IMAGE_VIEW, "surface depth view")

	return Texture {
		id = image,
		debug_name = "surface depth attachment",
		view = view,
		format = format,
		allocation = allocation,
		allocation_info = allocation_info,
	}
}

@(private = "file")
@(require_results)
_create_render_target_depth_resource_sampled :: proc(
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

	_cmd_image_transition_layout(
		cmd,
		image,
		.UNDEFINED,
		.DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
		vk.ImageSubresourceRange{aspectMask = {.DEPTH}, levelCount = 1, layerCount = 1},
	)

	view := _create_image_view(image, format, {.DEPTH}, 1)
	sampler: Sampler = create_sampler(sampler_info)

	_vk_set_debug_object_name(cast(u64)image, .IMAGE, "surface depth msaa image")
	_vk_set_debug_object_name(cast(u64)view, .IMAGE_VIEW, "surface depth msaa view")
	_vk_set_debug_object_name(cast(u64)sampler, .SAMPLER, "surface depth msaa sampler")

	return Texture {
		id = image,
		debug_name = "surface depth msaa attachment",
		view = view,
		sampler = sampler,
		format = format,
		allocation = allocation,
		allocation_info = allocation_info,
	}
}

@(private = "file")
_render_target_resize_color_attachments :: proc(
	width: u32,
	height: u32,
	surface: ^Render_Target,
	loc := #caller_location,
) {
	assert_gfx_ctx(loc)
	assert_not_nil(surface, loc)

	for &ca in sm.slice(&surface.color_attachments) {
		msaa, has_msaa := ca.msaa_texture.?

		resolve := _create_render_target_color_resolve_resource(
			width,
			height,
			ctx.gfx.swapchain.color_format.format,
			ca.sampler_info,
		)
		update_texture_h(ca.texture_h, resolve)
		ca.info.imageView = resolve.view

		if has_msaa {
			destroy_texture(&msaa)
			new_msaa := _create_render_target_color_resource(
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
_render_target_resize_readable_depth_attachment :: proc(
	width: u32,
	height: u32,
	surface: ^Render_Target,
	loc := #caller_location,
) {
	assert_gfx_ctx(loc)
	assert_not_nil(surface, loc)

	depth_attachment, has_depth_attachment := surface.depth_attachment.?
	assert(has_depth_attachment)
	attachment, ok := depth_attachment.(Render_Target_Readable_Depth_Attachment)
	assert(ok)

	msaa, has_msaa := attachment.msaa_texture.?

	sc := begin_single_cmd()

	resolve := _create_render_target_depth_resource_sampled(width, height, sc.cmd, attachment.sampler_info)
	update_texture_h(attachment.texture_h, resolve)
	attachment.info.imageView = resolve.view

	if has_msaa {
		destroy_texture(&msaa)
		new_msaa := _create_render_target_depth_resource(width, height, sc.cmd, surface.sample_count, false)
		attachment.msaa_texture = new_msaa
		attachment.info.imageView = new_msaa.view
		attachment.info.resolveImageView = resolve.view
	}
	end_single_cmd(sc)

	surface.depth_attachment = attachment
}
