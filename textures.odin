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

Image :: struct {
	width:    int,
	height:   int,
	channels: int,
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

Texture_Encoding :: enum {
	Linear,
	sRGB,
}

load_image :: proc(path: string, desired_channels: i32 = 0, loc := #caller_location) -> (image: Image, ok: bool) {
	stb_image.set_flip_vertically_on_load(1)
	width, height, channels: i32

	cpath, alloc_err := strings.clone_to_cstring(path, context.temp_allocator)
	if alloc_err != .None do log.panicf("Failed to allocate memory: %v", alloc_err, loc)

	data := stb_image.load(cpath, &width, &height, &channels, desired_channels)

	if channels == 0 {
		return {}, false
	}

	image.width = cast(int)width
	image.height = cast(int)height
	image.channels = desired_channels == 0 ? cast(int)channels : cast(int)desired_channels
	image.path = path
	image.data = data
	ok = true

	return
}

destroy_image :: proc(image: Image) {
	stb_image.image_free(image.data)
}

@(require_results)
load_texture :: proc(path: string, mip_levels: u32 = 1, anisotropy: f32 = 1) -> Texture {
	image, ok := load_image(path)
	defer destroy_image(image)
	if !ok {
		log.error("Couldn't load texture by path: ", path)
		return {}
	}
	return create_texture(image, mip_levels)
}

create_texture :: proc(
	image: Image,
	mip_levels: u32 = 1,
	encoding: Texture_Encoding = .sRGB,
	sampler_info: Sampler_Info = DEFAULT_SAMPLER_INFO,
	loc := #caller_location,
) -> Texture {
	return _store_texture(_create_texture(image, mip_levels, encoding, sampler_info, loc), loc)
}

destroy_texture :: proc(texture: Texture, loc := #caller_location) {
	t := _acquire_texture_h(texture)
	_deffered_destructor_add(t)
}

texture_get_size :: proc(texture: Texture) -> (w: int, h: int) {
	t := _get_texture_h(texture)
	return t.width, t.height
}

texture_get_format :: proc(texture: Texture) -> Format {
	t := _get_texture_h(texture)
	return t.format
}

texture_set_sampler :: proc(texture: Texture, info: Sampler_Info) {
	t := _get_texture_h(texture)
	_destroy_sampler(t.sampler)
	new_sampler := _create_sampler(info)
	t.sampler = new_sampler
	_update_texture_h(texture)
}

CUBEMAP_LAYERS_COUNT :: 6

// Creates a cubemap texture from 6 face images.
// Face orientation follows the standard cubemap layout:
// 0: +X (right)   1: -X (left)
// 2: +Y (top)     3: -Y (bottom)
// 4: +Z (front)   5: -Z (back)
@(require_results)
load_cubemap_texture :: proc(paths: [CUBEMAP_LAYERS_COUNT]string, mip_levels: u32 = 1, anisotropy: f32 = 1) -> Texture {
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

	return _store_texture(texture)
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
	desired_channels: int = image.channels
	layer_size := cast(Device_Size)(image.width * image.height * desired_channels)
	image_size := layer_size * CUBEMAP_LAYERS_COUNT

	sc := begin_single_cmd()

	// Staging Buffer
	staging_buffer := _create_buffer({.Transfer, .Host_Write}, size = image_size)
	defer _destroy_buffer(&staging_buffer)

	data := make([]byte, image_size, context.temp_allocator)
	for face, i in faces {
		offset := cast(Device_Size)i * layer_size
		dest := rawptr(uintptr(&data[0]) + uintptr(offset))
		src := rawptr(face.data)

		mem.copy(dest, src, int(layer_size))
	}

	_buffer_fill(&staging_buffer, raw_data(data), image_size)

	_cmd_buffer_barrier(sc.cmd, staging_buffer.id, {.HOST_WRITE}, {.TRANSFER_READ}, {.HOST}, {.TRANSFER})

	format := _channels_and_encoding_to_format(image.channels, encoding)

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
			imageExtent = vk.Extent3D{cast(u32)image.width, cast(u32)image.height, 1},
		}
	}

	_cmd_copy_buffer_to_image(sc.cmd, staging_buffer.id, vk_image, regions[:])

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

	image_view := _create_vk_image_view(
		vk_image,
		_format_to_vk(format),
		{.COLOR},
		mip_levels,
		.CUBE,
		CUBEMAP_LAYERS_COUNT,
	)
	sampler: vk.Sampler = _create_sampler(sampler_info)

	cubemap.id = vk_image
	cubemap.view = image_view
	cubemap.format = format
	cubemap.sampler = sampler
	cubemap.allocation = allocation
	cubemap.allocation_info = allocation_info

	_vk_set_debug_texture_name(cubemap, fmt.tprintf("%s %s", image.path, _location_to_string(loc)))

	return
}
