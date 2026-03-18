package ve

import "core:c"
import "core:fmt"
import "core:log"
import "core:math"
import "core:mem"
import "core:os"
import "core:strings"
import "lib/vma"
import stb_image "vendor:stb/image"
import vk "vendor:vulkan"

// *_norm_*
// Normalized formats automatically convert integer color values to floating-point ranges in shaders.
//
// For example:
//   format     |      input       |    shader
// RGB_norm_u8: | (255,    0, 128) | (1,  0, 0.5..)
// RGB_norm_i8: | (127, -128,   0) | (1, -1,   0)
// ---
// *_scaled_*
// Scaled formats convert integer values directly to floating-point in shaders.
//
// For example:
//   format       |     input        |        shader
// RGB_scaled_u8: | (255,    0, 128) | (255.0,    0.0, 128.0)
// RGB_scaled_i8: | (127, -128,   0) | (127.0, -128.0,   0.0)
// ---
// *_srgb_u*
// The R, G, and B components are unsigned normalized values that represent values using sRGB nonlinear encoding,
// while the A component (if one exists) is a regular unsigned normalized value.
//
// NOTE: Blending is only defined for floating-point, _norm_, and _srgb_u formats.
// Transfer function: https://registry.khronos.org/DataFormat/specs/1.4/dataformat.1.4.html#TRANSFER_SRGB
// May be useful: https://learnopengl.com/Advanced-Lighting/Gamma-Correction
Pixel_Format :: enum i32 {
	None            = 0,
	// 8 bits
	R_norm_u8       = 9,
	R_norm_i8       = 10,
	R_scaled_u8     = 11,
	R_scaled_i8     = 12,
	R_u8            = 13,
	R_i8            = 14,
	R_srgb_u8       = 15,
	RG_norm_u8      = 16,
	RG_norm_i8      = 17,
	RG_scaled_u8    = 18,
	RG_scaled_i8    = 19,
	RG_u8           = 20,
	RG_i8           = 21,
	RG_srgb_u8      = 22,
	RGB_norm_u8     = 23,
	RGB_norm_i8     = 24,
	RGB_scaled_u8   = 25,
	RGB_scaled_i8   = 26,
	RGB_u8          = 27,
	RGB_i8          = 28,
	RGB_srgb_u8     = 29,
	BGR_norm_u8     = 30,
	BGR_norm_i8     = 31,
	BGR_scaled_u8   = 32,
	BGR_scaled_i8   = 33,
	BGR_u8          = 34,
	BGR_i8          = 35,
	BGR_srgb_u8     = 36,
	RGBA_norm_u8    = 37,
	RGBA_norm_i8    = 38,
	RGBA_scaled_u8  = 39,
	RGBA_scaled_i8  = 40,
	RGBA_u8         = 41,
	RGBA_i8         = 42,
	RGBA_srgb_u8    = 43,
	BGRA_norm_u8    = 44,
	BGRA_norm_i8    = 45,
	BGRA_scaled_u8  = 46,
	BGRA_scaled_i8  = 47,
	BGRA_u8         = 48,
	BGRA_i8         = 49,
	BGRA_srgb_u8    = 50,
	// 16 bits
	R_norm_u16      = 70,
	R_norm_i16      = 71,
	R_scaled_u16    = 72,
	R_scaled_i16    = 73,
	R_u16           = 74,
	R_i16           = 75,
	R_f16           = 76,
	RG_norm_u16     = 77,
	RG_norm_i16     = 78,
	RG_scaled_u16   = 79,
	RG_scaled_i16   = 80,
	RG_u16          = 81,
	RG_i16          = 82,
	RG_f16          = 83,
	RGB_norm_u16    = 84,
	RGB_norm_i16    = 85,
	RGB_scaled_u16  = 86,
	RGB_scaled_i16  = 87,
	RGB_u16         = 88,
	RGB_i16         = 89,
	RGB_f16         = 90,
	RGBA_norm_u16   = 91,
	RGBA_norm_i16   = 92,
	RGBA_scaled_u16 = 93,
	RGBA_scaled_i16 = 94,
	RGBA_u16        = 95,
	RGBA_i16        = 96,
	RGBA_f16        = 97,
	// 32 bits
	R_u32           = 98,
	R_i32           = 99,
	R_f32           = 100,
	RG_u32          = 101,
	RG_i32          = 102,
	RG_f32          = 103,
	RGB_u32         = 104,
	RGB_i32         = 105,
	RGB_f32         = 106,
	RGBA_u32        = 107,
	RGBA_i32        = 108,
	RGBA_f32        = 109,
	// 64 bits
	R_u64           = 110,
	R_i64           = 111,
	R_f64           = 112,
	RG_u64          = 113,
	RG_i64          = 114,
	RG_f64          = 115,
	RGB_u64         = 116,
	RGB_i64         = 117,
	RGB_f64         = 118,
	RGBA_u64        = 119,
	RGBA_i64        = 120,
	RGBA_f64        = 121,
}

Image :: struct {
	width:    u32,
	height:   u32,
	channels: u32,
	data:     [^]byte,
	path:     string,
}

Sampler_Border_Color :: enum {
	Transparent_Black = 0,
	Opaque_Black      = 2,
	Opaque_White      = 4,
}

Sampler_Filter :: enum {
	Nearest = 0,
	Linear  = 1,
}

Sampler_Address_Mode :: enum {
	Repeat               = 0,
	Mirrored_Repeat      = 1,
	Clamp_To_Edge        = 2,
	Clamp_To_Border      = 3,
	Mirror_Clamp_To_Edge = 4,
}

Sampler_Lod_Clamp :: struct {
	min: f32,
	max: f32,
}

Sampler_Info :: struct {
	mag_filter:        Sampler_Filter,
	min_filter:        Sampler_Filter,
	address_mode_u:    Sampler_Address_Mode,
	address_mode_v:    Sampler_Address_Mode,
	address_mode_w:    Sampler_Address_Mode,
	anisotropy_enable: bool,
	max_anisotropy:    f32,
	border_color:      Sampler_Border_Color,
	mipmap_mode:       Sampler_Filter,
	lod_clamp:         Sampler_Lod_Clamp,
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


Texture_Encoding :: enum {
	Linear,
	sRGB,
}

Texture :: struct {
	id:              vk.Image,
	view:            vk.ImageView,
	sampler:         vk.Sampler,
	format:          vk.Format,
	allocation:      vma.Allocation,
	allocation_info: vma.AllocationInfo,
}

Texture_Cubemap :: Texture

load_image :: proc(path: string, desired_channels: i32 = 0, loc := #caller_location) -> (image: Image, ok: bool) {
	stb_image.set_flip_vertically_on_load(1)
	width, height, channels: i32

	cpath, alloc_err := strings.clone_to_cstring(path, context.temp_allocator)
	if alloc_err != .None do log.panicf("Failed to allocate memory: %v", alloc_err, loc)

	data := stb_image.load(cpath, &width, &height, &channels, desired_channels)

	if channels == 0 {
		return {}, false
	}

	image.width = cast(u32)width
	image.height = cast(u32)height
	image.channels = desired_channels == 0 ? cast(u32)channels : cast(u32)desired_channels
	image.path = path
	image.data = data
	ok = true

	return
}

destroy_image :: proc(image: Image) {
	stb_image.image_free(image.data)
}

@(require_results)
load_texture :: proc(path: string, mip_levels: u32 = 1, anisotropy: f32 = 1) -> Texture_Handle {
	image, ok := load_image(path)
	defer destroy_image(image)
	if !ok {
		log.error("couldn't load texture by path: ", path)
		return {}
	}
	texture := create_texture(image, mip_levels)

	return store_texture(texture)
}

create_texture :: proc(
	image: Image,
	mip_levels: u32 = 1,
	encoding: Texture_Encoding = .sRGB,
	sampler_info: Sampler_Info = DEFAULT_SAMPLER_INFO,
	loc := #caller_location,
) -> (
	texture: Texture,
) {
	assert_gfx_ctx(loc)

	desired_channels: u32 = image.channels
	image_size := cast(vk.DeviceSize)(image.width * image.height * desired_channels)

	sc := begin_single_cmd()

	// Staging Buffer
	staging_buffer := create_buffer({.Transfer, .Host_Write}, image_size, image.data)
	defer destroy_buffer(&staging_buffer)

	format: vk.Format = _format_to_vk(_chan_encod_to_format(image.channels, encoding))

	// Image
	vk_image, allocation, allocation_info := _create_image(
		image.width,
		image.height,
		mip_levels,
		._1,
		format,
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
				imageExtent = vk.Extent3D{image.width, image.height, 1},
			},
		},
	)

	if mip_levels > 1 {
		_generate_mipmaps(sc.cmd, vk_image, format, cast(i32)image.width, cast(i32)image.height, mip_levels)
	}

	end_single_cmd(sc)

	image_view := _create_image_view(vk_image, format, {.COLOR}, mip_levels)
	sampler: vk.Sampler = create_sampler(sampler_info)

	texture.id = vk_image
	texture.view = image_view
	texture.format = format
	texture.sampler = sampler
	texture.allocation = allocation
	texture.allocation_info = allocation_info

	_vk_set_debug_texture_name(texture, fmt.tprintf("%s %s", image.path, _location_to_string(loc)))

	return
}

destroy_texture :: proc(texture: ^Texture, loc := #caller_location) {
	assert_not_nil(texture, loc)

	destroy_sampler(texture.sampler)
	vk.DestroyImageView(ctx.gfx.vk_state.device, texture.view, nil)
	vma.DestroyImage(ctx.gfx.vk_state.allocator, texture.id, texture.allocation)

	texture.sampler = 0
	texture.view = 0
	texture.id = 0
	texture.allocation_info = {}
}

CUBEMAP_LAYERS_COUNT :: 6

// Creates a cubemap texture from 6 face images.
// Face orientation follows the standard cubemap layout:
// 0: +X (right)   1: -X (left)
// 2: +Y (top)     3: -Y (bottom)
// 4: +Z (front)   5: -Z (back)
@(require_results)
load_cubemap_texture :: proc(
	paths: [CUBEMAP_LAYERS_COUNT]string,
	mip_levels: u32 = 1,
	anisotropy: f32 = 1,
) -> Texture_Handle {
	images: [CUBEMAP_LAYERS_COUNT]Image
	for path, i in paths {
		image, ok := load_image(path)
		if !ok {
			log.error("couldn't load texture by path: ", path)
			return {}
		}

		images[i] = image
	}

	texture := create_texture_cubemap(images, mip_levels)

	for &image in images {
		destroy_image(image)
	}

	return store_texture(texture)
}

// Creates a cubemap texture from 6 face images.
// Face orientation follows the standard cubemap layout:
// 0: +X (right)   1: -X (left)
// 2: +Y (top)     3: -Y (bottom)
// 4: +Z (front)   5: -Z (back)
create_texture_cubemap :: proc(
	faces: [CUBEMAP_LAYERS_COUNT]Image,
	mip_levels: u32 = 1,
	encoding: Texture_Encoding = .sRGB,
	sampler_info: Sampler_Info = DEFAULT_SAMPLER_INFO,
	loc := #caller_location,
) -> (
	cubemap: Texture_Cubemap,
) {
	for _, i in faces {
		for _, j in faces {
			if i == j do continue
			ERROR :: "All cubemap faces must have identical width, height, and channel count"
			assert(faces[i].width == faces[j].width, ERROR, loc)
			assert(faces[i].height == faces[j].height, ERROR, loc)
			assert(faces[i].channels == faces[j].channels, ERROR, loc)
		}
	}

	image := faces[0]

	assert_gfx_ctx(loc)

	desired_channels: u32 = image.channels

	layer_size := cast(Device_Size)(image.width * image.height * desired_channels)
	image_size := layer_size * CUBEMAP_LAYERS_COUNT

	sc := begin_single_cmd()

	// Staging Buffer
	staging_buffer := create_buffer({.Transfer, .Host_Write}, size = image_size)
	defer destroy_buffer(&staging_buffer)

	data := make([]byte, image_size, context.temp_allocator)
	for face, i in faces {
		offset := cast(Device_Size)i * layer_size
		dest := rawptr(uintptr(&data[0]) + uintptr(offset))
		src := rawptr(face.data)

		mem.copy(dest, src, int(layer_size))
	}

	buffer_fill(&staging_buffer, raw_data(data), image_size)

	_cmd_buffer_barrier(sc.cmd, staging_buffer.id, {.HOST_WRITE}, {.TRANSFER_READ}, {.HOST}, {.TRANSFER})

	format: vk.Format = _format_to_vk(_chan_encod_to_format(image.channels, encoding))

	// Image
	vk_image, allocation, allocation_info := _create_image(
		image.width,
		image.height,
		mip_levels,
		._1,
		format,
		.OPTIMAL,
		{.TRANSFER_SRC, .TRANSFER_DST, .SAMPLED},
		vma.MemoryUsage.AUTO_PREFER_DEVICE,
		vma.AllocationCreateFlags{},
		6,
		{.CUBE_COMPATIBLE},
	)

	_cmd_image_transition_layout(
		sc.cmd,
		vk_image,
		.UNDEFINED,
		.TRANSFER_DST_OPTIMAL,
		vk.ImageSubresourceRange{aspectMask = {.COLOR}, levelCount = mip_levels, layerCount = CUBEMAP_LAYERS_COUNT},
	)

	regions: [CUBEMAP_LAYERS_COUNT]vk.BufferImageCopy

	for i in 0 ..< CUBEMAP_LAYERS_COUNT {
		regions[i] = vk.BufferImageCopy {
			bufferOffset = layer_size * cast(Device_Size)i,
			bufferRowLength = 0,
			bufferImageHeight = 0,
			imageSubresource = vk.ImageSubresourceLayers {
				aspectMask = {.COLOR},
				mipLevel = 0,
				baseArrayLayer = cast(u32)i,
				layerCount = 1,
			},
			imageOffset = {},
			imageExtent = vk.Extent3D{image.width, image.height, 1},
		}
	}

	_cmd_copy_buffer_to_image(sc.cmd, staging_buffer.id, vk_image, regions[:])

	if mip_levels > 1 {
		_generate_mipmaps(sc.cmd, vk_image, format, cast(i32)image.width, cast(i32)image.height, mip_levels)
	}

	end_single_cmd(sc)

	image_view := _create_image_view(vk_image, format, {.COLOR}, mip_levels, .CUBE, CUBEMAP_LAYERS_COUNT)
	sampler: vk.Sampler = create_sampler(sampler_info)

	cubemap.id = vk_image
	cubemap.view = image_view
	cubemap.format = format
	cubemap.sampler = sampler
	cubemap.allocation = allocation
	cubemap.allocation_info = allocation_info

	_vk_set_debug_texture_name(cubemap, fmt.tprintf("%s %s", image.path, _location_to_string(loc)))

	return
}

create_sampler :: proc(info: Sampler_Info, loc := #caller_location) -> Sampler {
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

destroy_sampler :: proc(sampler: Sampler) {
	vk.DestroySampler(ctx.gfx.vk_state.device, sampler, nil)
}

@(private)
_sampler_filter_to_vk :: proc(f: Sampler_Filter) -> vk.Filter {
	switch f {
	case .Nearest:
		return .NEAREST
	case .Linear:
		return .LINEAR
	}

	return .NEAREST
}

@(private)
_sampler_filter_to_vk_mipmap_mode :: proc(f: Sampler_Filter) -> vk.SamplerMipmapMode {
	switch f {
	case .Nearest:
		return .NEAREST
	case .Linear:
		return .LINEAR
	}

	return .NEAREST
}

@(private)
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

@(private)
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

@(private)
_create_image :: proc(
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

@(private)
_create_image_view :: proc(
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

Buffer_Image_Copy :: struct {
	buffer_offset:     Device_Size,
	image_subresource: struct {
		apect_mask:       vk.ImageAspectFlags,
		base_array_layer: u32,
	},
	image_extent:      vk.Extent3D,
}

@(private = "file")
_cmd_copy_buffer_to_image :: proc(
	cmd: vk.CommandBuffer,
	buffer: vk.Buffer,
	image: vk.Image,
	regions: []vk.BufferImageCopy,
) {
	vk.CmdCopyBufferToImage(cmd, buffer, image, .TRANSFER_DST_OPTIMAL, cast(u32)len(regions), raw_data(regions))
}

@(private = "file")
_generate_mipmaps :: proc(
	cmd: vk.CommandBuffer,
	image: vk.Image,
	format: vk.Format,
	tex_width: i32,
	tex_height: i32,
	mip_levels: u32,
	loc := #caller_location,
) {
	assert_gfx_ctx(loc)

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

@(private = "file")
_chan_encod_to_format :: proc(channels: u32, encoding: Texture_Encoding) -> Pixel_Format {
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

_format_to_vk :: #force_inline proc(format: Pixel_Format) -> vk.Format {
	return transmute(vk.Format)format
}

@(private)
_cmd_image_transition_layout :: proc(
	cmd: vk.CommandBuffer,
	image: vk.Image,
	old_layout: vk.ImageLayout,
	new_layout: vk.ImageLayout,
	subresource_range: vk.ImageSubresourceRange = {aspectMask = {.COLOR}, levelCount = 1, layerCount = 1},
) {
	src_stage, dst_stage: vk.PipelineStageFlags2
	src_access, dst_access: vk.AccessFlags2

	if old_layout == .UNDEFINED && new_layout == .TRANSFER_DST_OPTIMAL {
		src_access = {}
		dst_access = {.TRANSFER_WRITE}

		src_stage = {}
		dst_stage = {.TRANSFER}
	} else if old_layout == .TRANSFER_DST_OPTIMAL && new_layout == .SHADER_READ_ONLY_OPTIMAL {
		src_access = {.TRANSFER_WRITE}
		dst_access = {.SHADER_READ}

		src_stage = {.TRANSFER}
		dst_stage = {.VERTEX_SHADER, .FRAGMENT_SHADER}
	} else if old_layout == .UNDEFINED && new_layout == .DEPTH_STENCIL_ATTACHMENT_OPTIMAL {
		src_access = {}
		dst_access = {.DEPTH_STENCIL_ATTACHMENT_READ, .DEPTH_STENCIL_ATTACHMENT_WRITE}

		src_stage = {}
		dst_stage = {.EARLY_FRAGMENT_TESTS}
	} else if old_layout == .DEPTH_STENCIL_ATTACHMENT_OPTIMAL && new_layout == .SHADER_READ_ONLY_OPTIMAL {
		src_access = {.DEPTH_STENCIL_ATTACHMENT_WRITE}
		dst_access = {.SHADER_READ}

		src_stage = {.EARLY_FRAGMENT_TESTS}
		dst_stage = {.VERTEX_SHADER, .FRAGMENT_SHADER}
	} else if old_layout == .SHADER_READ_ONLY_OPTIMAL && new_layout == .DEPTH_STENCIL_ATTACHMENT_OPTIMAL {
		src_access = {.SHADER_READ}
		dst_access = {.DEPTH_STENCIL_ATTACHMENT_WRITE}

		src_stage = {.VERTEX_SHADER, .FRAGMENT_SHADER}
		dst_stage = {.EARLY_FRAGMENT_TESTS}
	} else if old_layout == .UNDEFINED && new_layout == .COLOR_ATTACHMENT_OPTIMAL {
		src_access = {}
		dst_access = {.COLOR_ATTACHMENT_WRITE}

		src_stage = {.ALL_COMMANDS}
		dst_stage = {.COLOR_ATTACHMENT_OUTPUT}
	} else if old_layout == .COLOR_ATTACHMENT_OPTIMAL && new_layout == .PRESENT_SRC_KHR {
		src_access = {.COLOR_ATTACHMENT_WRITE}
		dst_access = {}

		src_stage = {.COLOR_ATTACHMENT_OUTPUT}
		dst_stage = {}
	} else if old_layout == .COLOR_ATTACHMENT_OPTIMAL && new_layout == .SHADER_READ_ONLY_OPTIMAL {
		src_access = {.COLOR_ATTACHMENT_WRITE}
		dst_access = {.MEMORY_READ}

		src_stage = {.COLOR_ATTACHMENT_OUTPUT}
		dst_stage = {.VERTEX_SHADER, .FRAGMENT_SHADER}
	} else if old_layout == .SHADER_READ_ONLY_OPTIMAL && new_layout == .COLOR_ATTACHMENT_OPTIMAL {
		src_access = {.MEMORY_READ}
		dst_access = {.COLOR_ATTACHMENT_WRITE}

		src_stage = {.VERTEX_SHADER, .FRAGMENT_SHADER}
		dst_stage = {.COLOR_ATTACHMENT_OUTPUT}
	} else if old_layout == .TRANSFER_DST_OPTIMAL && new_layout == .TRANSFER_SRC_OPTIMAL {
		src_access = {.TRANSFER_WRITE}
		dst_access = {.TRANSFER_READ}

		src_stage = {.TRANSFER}
		dst_stage = {.TRANSFER}
	} else if old_layout == .TRANSFER_SRC_OPTIMAL && new_layout == .SHADER_READ_ONLY_OPTIMAL {
		src_access = {.TRANSFER_READ}
		dst_access = {.SHADER_READ}

		src_stage = {.TRANSFER}
		dst_stage = {.VERTEX_SHADER, .FRAGMENT_SHADER}
	} else {
		log.panicf("unsuported layout transition!\nold_layout %v \nnew_layout: %v", old_layout, new_layout)
	}

	barrier := vk.ImageMemoryBarrier2 {
		sType               = .IMAGE_MEMORY_BARRIER_2,
		oldLayout           = old_layout,
		newLayout           = new_layout,
		srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		image               = image,
		subresourceRange    = subresource_range,
		srcStageMask        = src_stage,
		srcAccessMask       = src_access,
		dstAccessMask       = dst_access,
		dstStageMask        = dst_stage,
	}

	dependency_info := vk.DependencyInfo {
		sType                   = .DEPENDENCY_INFO,
		imageMemoryBarrierCount = 1,
		pImageMemoryBarriers    = &barrier,
		dependencyFlags         = {},
	}

	vk.CmdPipelineBarrier2(cmd, &dependency_info)
}

_vk_set_debug_texture_name :: #force_inline proc(texture: Texture, debug_name: string) {
	when ENABLE_VALIDATION_LAYERS {
		_vk_set_debug_object_name(cast(u64)texture.id, .IMAGE, debug_name)
		if texture.view != 0 do _vk_set_debug_object_name(cast(u64)texture.view, .IMAGE_VIEW, debug_name)
		if texture.view != 0 do _vk_set_debug_object_name(cast(u64)texture.sampler, .SAMPLER, debug_name)
	}
}
