#+private
package ve

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

_channels_and_encoding_to_format :: proc(channels: int, encoding: Texture_Encoding) -> Format {
	assert(channels != 0 || channels <= 4)

	switch channels {
	case 1:
		return .R_u8 if encoding == .Linear else .R_srgb_u8
	case 2:
		return .RG_u8 if encoding == .Linear else .RG_srgb_u8
	case 3:
		return .RGB_u8 if encoding == .Linear else .RGB_srgb_u8
	case 4:
		return .RGBA_u8 if encoding == .Linear else .RGBA_srgb_u8
	}
	return .RGBA_srgb_u8
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
