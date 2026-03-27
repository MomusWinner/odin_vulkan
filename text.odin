package ve

import "core:c"
import sm "core:container/small_array"
import "core:fmt"
import "core:log"
import "core:math/rand"
import image "vendor:stb/image"
import tt "vendor:stb/truetype"
import vk "vendor:vulkan"

Font :: struct {
	size:                    f32,
	glyph_map:               Texture,
	packed_chars:            []tt.packedchar,
	aligned_quads:           []tt.aligned_quad,
	codepoint_to_char_index: map[int]int,
	default_char:            rune,
}

FontVertex :: struct {
	position:   vec3,
	tex_coords: vec2,
}

CharacterRegion :: struct {
	start: i32,
	size:  i32,
}

Create_Font_Info :: struct {
	size:         f32,
	padding:      i32,
	atlas_width:  i32,
	atlas_height: i32,
	regions:      []CharacterRegion,
	default_char: rune,
}

load_font :: proc {
	load_font_from_memory,
	load_font_from_file,
}

load_font_from_file :: proc(
	path: string,
	create_info: Create_Font_Info,
	sampler_info := DEFAULT_SAMPLER_INFO,
	loc := #caller_location,
) -> Font {
	assert(path != "", loc = loc)

	data, ok := read_file(path, context.temp_allocator)
	assert(ok, fmt.tprint("Couldn't load font.", path), loc)

	return load_font_from_memory(data, create_info, sampler_info, loc)
}

load_font_from_memory :: proc(
	data: []byte,
	create_info: Create_Font_Info,
	sampler_info := DEFAULT_SAMPLER_INFO,
	loc := #caller_location,
) -> Font {
	font_number := tt.GetNumberOfFonts(raw_data(data))
	assert(font_number != -1, fmt.tprintf("The font file doesn't correspond to valid font data."), loc)

	total_size: i32
	for regions in create_info.regions {
		total_size += regions.size
	}

	packed_chars := make([]tt.packedchar, total_size)
	aligned_quads := make([]tt.aligned_quad, total_size)

	font_atlas_bitmap := make([]u8, create_info.atlas_width * create_info.atlas_height, context.temp_allocator)

	ctx: tt.pack_context
	tt_must(
		tt.PackBegin(
			&ctx,
			raw_data(font_atlas_bitmap),
			create_info.atlas_width,
			create_info.atlas_height,
			0,
			create_info.padding,
			nil,
		),
	)

	processed_chars: i32
	for region in create_info.regions {
		tt_must(
			tt.PackFontRange(
				&ctx,
				raw_data(data),
				0,
				create_info.size,
				region.start,
				region.size,
				raw_data(packed_chars[processed_chars:processed_chars + region.size]),
			),
			fmt.tprintf(
				"Couldn't place char region [start: %d, size: %d]. Increase atlas size or reduce region size.",
				region.start,
				region.size,
			),
			loc,
		)
		processed_chars += region.size
	}
	tt.PackEnd(&ctx)

	for i in 0 ..< total_size {
		unusedX, unusedY: f32 = ---, ---
		tt.GetPackedQuad(
			raw_data(packed_chars),
			create_info.atlas_width,
			create_info.atlas_height,
			i,
			&unusedX,
			&unusedY,
			&aligned_quads[i],
			false,
		)
	}

	codepoint_to_char_index: map[int]int
	offset: int
	for region in create_info.regions {
		for i in 0 ..< cast(int)region.size {
			codepoint_to_char_index[i + cast(int)region.start] = i + offset
		}
		offset += cast(int)region.size
	}

	// NOTE: Write Font Data to PNG
	image.write_png(
		"font_image.png",
		create_info.atlas_width,
		create_info.atlas_height,
		1,
		raw_data(font_atlas_bitmap),
		create_info.atlas_width,
	)

	image := Image {
		width    = cast(int)create_info.atlas_width,
		height   = cast(int)create_info.atlas_height,
		data     = raw_data(font_atlas_bitmap),
		channels = 1,
	}

	texture := create_texture(image, .R_norm_u8, sampler_info = sampler_info)

	return Font {
		size = create_info.size,
		packed_chars = packed_chars,
		aligned_quads = aligned_quads,
		glyph_map = texture,
		codepoint_to_char_index = codepoint_to_char_index,
		default_char = create_info.default_char,
	}
}

unload_font :: proc(font: ^Font, loc := #caller_location) {
	assert_not_nil(font, loc)

	delete(font.packed_chars)
	delete(font.aligned_quads)
	delete(font.codepoint_to_char_index)
}

@(private = "file")
tt_must :: proc(status: i32, message: string = "Something went wrong with text rendering", loc := #caller_location) {
	if status == 0 {
		log.panic(message, loc)
	}
}

create_text_mesh :: proc(
	font: ^Font,
	text: string,
	size: f32,
	allocator := context.allocator,
	loc := #caller_location,
) -> []FontVertex {
	position := vec3{0, 0, 0}
	vertices := make([]FontVertex, len(text) * 6, allocator)
	vertex_index := 0

	order := [6]int{0, 1, 2, 0, 2, 3}

	for ch in text {
		code_point := cast(i32)ch

		if ch == '\n' {
			position.y -= size * font.size
			position.x = 0
			continue
		} else if code_point == 0 {
			continue
		}

		char_index: int
		if cast(int)code_point in font.codepoint_to_char_index {
			char_index = font.codepoint_to_char_index[cast(int)code_point]
		} else {
			char_index = font.codepoint_to_char_index[cast(int)font.default_char]
			assert(
				char_index != 0,
				fmt.tprintf("The default character '%r' is not exist in Font regions", font.default_char),
				loc,
			)
		}

		packed_char := font.packed_chars[char_index]
		aligned_quad := font.aligned_quads[char_index]

		glyph_size := vec2 {
			cast(f32)(packed_char.x1 - packed_char.x0) * size,
			cast(f32)(packed_char.y1 - packed_char.y0) * size,
		}

		glyph_bounding_box_bottom_left := vec2 {
			position.x + (packed_char.xoff * size),
			position.y +
			(packed_char.yoff - packed_char.yoff2 * 2 + cast(f32)packed_char.y1 - cast(f32)packed_char.y0) * size,
		}

		glyph_vertices := [4]vec2 {
			{glyph_bounding_box_bottom_left.x + glyph_size.x, glyph_bounding_box_bottom_left.y + glyph_size.y},
			{glyph_bounding_box_bottom_left.x, glyph_bounding_box_bottom_left.y + glyph_size.y},
			{glyph_bounding_box_bottom_left.x, glyph_bounding_box_bottom_left.y},
			{glyph_bounding_box_bottom_left.x + glyph_size.x, glyph_bounding_box_bottom_left.y},
		}

		glyph_texture_coords := [4]vec2 {
			{aligned_quad.s1, aligned_quad.t0},
			{aligned_quad.s0, aligned_quad.t0},
			{aligned_quad.s0, aligned_quad.t1},
			{aligned_quad.s1, aligned_quad.t1},
		}

		for i in 0 ..< 6 {
			vertices[vertex_index + i].position = vec3 {
				glyph_vertices[order[i]].x,
				glyph_vertices[order[i]].y,
				position.z,
			}
			vertices[vertex_index + i].tex_coords = glyph_texture_coords[order[i]]
		}

		vertex_index += 6
		position.x += packed_char.xadvance * size
	}

	return vertices
}
