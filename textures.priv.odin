#+private
package ve

import "core:fmt"
import "core:log"
import "core:math"
import "core:reflect"
import "core:strings"
import "lib/vma"
import vk "vendor:vulkan"

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

Texture_Data :: struct {
	id:              vk.Image,
	width, height:   int,
	format:          Format,
	view:            vk.ImageView,
	sampler:         vk.Sampler,
	allocation:      vma.Allocation,
	allocation_info: vma.AllocationInfo,
}

Texture_Cubemap :: Texture_Data

Buffer_Image_Copy :: struct {
	buffer_offset:     Device_Size,
	image_subresource: struct {
		apect_mask:       vk.ImageAspectFlags,
		base_array_layer: u32,
	},
	image_extent:      vk.Extent3D,
}

_create_texture :: proc(
	image: Image,
	format: Pixel_Format,
	sampler_info: Sampler_Info = DEFAULT_SAMPLER_INFO,
	mip_levels: u32 = 1,
	loc := #caller_location,
) -> (
	texture: Texture_Data,
) {
	channels: int = pixel_format_to_channels(format)
	image_size := cast(vk.DeviceSize)(image.width * image.height * channels)

	sc := begin_single_cmd()

	// Staging Buffer
	staging_buffer := _create_buffer({.Transfer, .Host_Write}, image_size, image.data)
	defer _destroy_buffer(&staging_buffer)

	format: Format = cast(Format)format

	// Image
	vk_image, allocation, allocation_info := _create_vk_image(
		cast(u32)image.width,
		cast(u32)image.height,
		mip_levels,
		._1,
		_format_to_vk(format),
		.OPTIMAL,
		{.TRANSFER_SRC, .TRANSFER_DST, .SAMPLED},
		vma.MemoryUsage.AUTO_PREFER_DEVICE,
		vma.AllocationCreateFlags{},
	)

	_cmd_image_transition_layout(
		sc.cmd,
		vk_image,
		.UNDEFINED,
		.TRANSFER_DST_OPTIMAL,
		vk.ImageSubresourceRange{aspectMask = {.COLOR}, layerCount = 1, levelCount = mip_levels},
	)
	_cmd_copy_buffer_to_image(
		sc.cmd,
		staging_buffer.id,
		vk_image,
		[]vk.BufferImageCopy {
			vk.BufferImageCopy {
				bufferOffset = 0,
				bufferRowLength = 0,
				bufferImageHeight = 0,
				imageSubresource = vk.ImageSubresourceLayers {
					aspectMask = {.COLOR},
					mipLevel = 0,
					baseArrayLayer = 0,
					layerCount = 1,
				},
				imageOffset = {0, 0, 0},
				imageExtent = vk.Extent3D{cast(u32)image.width, cast(u32)image.height, 1},
			},
		},
	)

	if mip_levels > 1 {
		_generate_mipmaps(
			sc.cmd,
			vk_image,
			_format_to_vk(format),
			cast(i32)image.width,
			cast(i32)image.height,
			mip_levels,
		)
	}

	end_single_cmd(sc)

	image_view := _create_vk_image_view(vk_image, _format_to_vk(format), {.COLOR}, mip_levels)
	sampler: vk.Sampler = _create_sampler(sampler_info)

	texture.id = vk_image
	texture.width, texture.height = image.width, image.height
	texture.view = image_view
	texture.format = format
	texture.sampler = sampler
	texture.allocation = allocation
	texture.allocation_info = allocation_info

	_vk_set_debug_texture_name(texture, fmt.tprintf("%s %s", image.path, _location_to_string(loc)))

	return
}

_destroy_texture :: proc(texture: ^Texture_Data, loc := #caller_location) {
	assert_not_nil(texture, loc)

	_destroy_sampler(texture.sampler)
	vk.DestroyImageView(ctx.gfx.vk_state.device, texture.view, nil)
	vma.DestroyImage(ctx.gfx.vk_state.allocator, texture.id, texture.allocation)

	texture.sampler = 0
	texture.view = 0
	texture.id = 0
	texture.allocation_info = {}
}

_create_sampler :: proc(info: Sampler_Info, loc := #caller_location) -> Sampler {
	max_anisotropy: f32 = ---
	if info.anisotropy_enable && info.max_anisotropy == 0 {
		max_anisotropy = ctx.gfx.limits.max_sampler_anisotropy
	} else {
		max_anisotropy = math.clamp(info.max_anisotropy, 0, ctx.gfx.limits.max_sampler_anisotropy)
	}

	sampler_info := vk.SamplerCreateInfo {
		sType                   = .SAMPLER_CREATE_INFO,
		magFilter               = _sampler_filter_to_vk(info.mag_filter),
		minFilter               = _sampler_filter_to_vk(info.min_filter),
		addressModeU            = _sampler_address_mode_to_vk(info.address_mode_u),
		addressModeV            = _sampler_address_mode_to_vk(info.address_mode_v),
		addressModeW            = _sampler_address_mode_to_vk(info.address_mode_w),
		anisotropyEnable        = cast(b32)info.anisotropy_enable,
		maxAnisotropy           = max_anisotropy,
		borderColor             = _sampler_border_color_to_vk(info.border_color),
		unnormalizedCoordinates = false,
		compareEnable           = false,
		compareOp               = .ALWAYS,
		mipmapMode              = _sampler_filter_to_vk_mipmap_mode(info.mipmap_mode),
		mipLodBias              = 0.0,
		minLod                  = info.lod_clamp.min,
		maxLod                  = info.lod_clamp.max,
	}

	sampler: Sampler
	must(vk.CreateSampler(ctx.gfx.vk_state.device, &sampler_info, nil, &sampler))

	return sampler
}

_destroy_sampler :: proc(sampler: Sampler) {
	vk.DestroySampler(ctx.gfx.vk_state.device, sampler, nil)
}

@(private = "file")
_sampler_filter_to_vk :: proc(f: Sampler_Filter) -> vk.Filter {
	switch f {
	case .Nearest:
		return .NEAREST
	case .Linear:
		return .LINEAR
	}

	return .NEAREST
}

@(private = "file")
_sampler_filter_to_vk_mipmap_mode :: proc(f: Sampler_Filter) -> vk.SamplerMipmapMode {
	switch f {
	case .Nearest:
		return .NEAREST
	case .Linear:
		return .LINEAR
	}

	return .NEAREST
}

@(private = "file")
_sampler_address_mode_to_vk :: proc(a: Sampler_Address_Mode) -> vk.SamplerAddressMode {
	switch a {
	case .Repeat:
		return .REPEAT
	case .Mirrored_Repeat:
		return .MIRRORED_REPEAT
	case .Clamp_To_Edge:
		return .CLAMP_TO_EDGE
	case .Clamp_To_Border:
		return .CLAMP_TO_BORDER
	case .Mirror_Clamp_To_Edge:
		return .MIRROR_CLAMP_TO_EDGE
	}

	return .REPEAT
}

@(private = "file")
_sampler_border_color_to_vk :: proc(b: Sampler_Border_Color) -> vk.BorderColor {
	switch b {
	case .Transparent_Black:
		return .FLOAT_TRANSPARENT_BLACK
	case .Opaque_Black:
		return .FLOAT_OPAQUE_BLACK
	case .Opaque_White:
		return .FLOAT_OPAQUE_WHITE
	}

	return .FLOAT_TRANSPARENT_BLACK
}

_create_vk_image :: proc(
	width, height, mip_levels: u32,
	sample_count: Sample_Count_Flag,
	format: vk.Format,
	tiling: vk.ImageTiling,
	usage: vk.ImageUsageFlags,
	memory_usage: vma.MemoryUsage,
	memory_flags: vma.AllocationCreateFlags,
	array_layers: u32 = 1,
	flags: vk.ImageCreateFlags = {},
) -> (
	vk.Image,
	vma.Allocation,
	vma.AllocationInfo,
) {
	image_info := vk.ImageCreateInfo {
		sType = .IMAGE_CREATE_INFO,
		imageType = .D2,
		extent = vk.Extent3D{width = width, height = height, depth = 1},
		mipLevels = mip_levels,
		arrayLayers = array_layers,
		format = format,
		tiling = tiling,
		initialLayout = .UNDEFINED,
		usage = usage,
		sharingMode = .EXCLUSIVE,
		samples = {sample_count},
		flags = flags,
	}

	image: vk.Image

	allocation_create_info := vma.AllocationCreateInfo {
		usage = memory_usage,
		flags = memory_flags,
	}

	allocation: vma.Allocation
	allocation_info: vma.AllocationInfo

	must(
		vma.CreateImage(
			ctx.gfx.vk_state.allocator,
			&image_info,
			&allocation_create_info,
			&image,
			&allocation,
			&allocation_info,
		),
	)

	return image, allocation, allocation_info
}

_create_vk_image_view :: proc(
	image: vk.Image,
	format: vk.Format,
	aspect: vk.ImageAspectFlags,
	mip_levels: u32,
	view_type: vk.ImageViewType = .D2,
	layer_count: u32 = 1,
) -> vk.ImageView {
	create_info := vk.ImageViewCreateInfo {
		sType = .IMAGE_VIEW_CREATE_INFO,
		image = image,
		viewType = view_type,
		format = format,
		subresourceRange = {aspectMask = aspect, levelCount = mip_levels, layerCount = layer_count},
	}

	image_view: vk.ImageView

	must(
		vk.CreateImageView(ctx.gfx.vk_state.device, &create_info, nil, &image_view),
		"failed to create texture image view!",
	)

	return image_view
}

_generate_mipmaps :: proc(
	cmd: vk.CommandBuffer,
	image: vk.Image,
	format: vk.Format,
	tex_width: i32,
	tex_height: i32,
	mip_levels: u32,
	loc := #caller_location,
) {
	format_properties := vk.FormatProperties{}
	vk.GetPhysicalDeviceFormatProperties(ctx.gfx.vk_state.physical_device, format, &format_properties)
	if .SAMPLED_IMAGE_FILTER_LINEAR not_in format_properties.optimalTilingFeatures {
		log.error("texture image format does not support linear blitting!")
		return
	}

	subresource := vk.ImageSubresourceRange {
		aspectMask     = {.COLOR},
		baseArrayLayer = 0,
		layerCount     = 1,
		levelCount     = 1,
	}

	mip_width := tex_width
	mip_height := tex_height

	for i in 1 ..< mip_levels {
		subresource.baseMipLevel = i - 1
		_cmd_image_transition_layout(cmd, image, .TRANSFER_DST_OPTIMAL, .TRANSFER_SRC_OPTIMAL, subresource)

		blit := vk.ImageBlit {
			srcOffsets = {{0, 0, 0}, {mip_width, mip_height, 1}},
			srcSubresource = {aspectMask = {.COLOR}, mipLevel = i - 1, baseArrayLayer = 0, layerCount = 1},
			dstOffsets = {
				{0, 0, 0},
				{mip_width / 2 if mip_width > 1 else 1, mip_height / 2 if mip_height > 1 else 1, 1},
			},
			dstSubresource = {aspectMask = {.COLOR}, mipLevel = i, baseArrayLayer = 0, layerCount = 1},
		}

		vk.CmdBlitImage(cmd, image, .TRANSFER_SRC_OPTIMAL, image, .TRANSFER_DST_OPTIMAL, 1, &blit, .LINEAR)
		_cmd_image_transition_layout(cmd, image, .TRANSFER_SRC_OPTIMAL, .SHADER_READ_ONLY_OPTIMAL, subresource)

		if mip_width > 1 {
			mip_width /= 2
		}
		if mip_height > 1 {
			mip_height /= 2
		}
	}

	subresource.baseMipLevel = mip_levels - 1
	_cmd_image_transition_layout(cmd, image, .TRANSFER_DST_OPTIMAL, .SHADER_READ_ONLY_OPTIMAL, subresource)
}

_format_to_vk :: #force_inline proc(format: Format) -> vk.Format {
	return cast(vk.Format)format
}

_vk_to_format :: #force_inline proc(format: vk.Format) -> Format {
	f := cast(Format)format
	when GFX_DEBUG {
		ok := reflect.enum_value_has_name(f)
		if !ok {
			log.panicf("Unsupported format: %v", format)
		}
	}

	return f
}

_vk_set_debug_texture_name :: #force_inline proc(texture: Texture_Data, debug_name: string) {
	when ENABLE_VALIDATION_LAYERS {
		_vk_set_debug_object_name(cast(u64)texture.id, .IMAGE, debug_name)
		if texture.view != 0 do _vk_set_debug_object_name(cast(u64)texture.view, .IMAGE_VIEW, debug_name)
		if texture.sampler != 0 do _vk_set_debug_object_name(cast(u64)texture.sampler, .SAMPLER, debug_name)
	}
}
