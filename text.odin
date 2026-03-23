package ve

import "core:c"
import sm "core:container/small_array"
import "core:fmt"
import "core:log"
import image "vendor:stb/image"
import tt "vendor:stb/truetype"
import vk "vendor:vulkan"

Font :: struct {
	name:                    string,
	size:                    f32,
	texture_h:               Texture,
	packed_chars:            []tt.packedchar,
	aligned_quads:           []tt.aligned_quad,
	codepoint_to_char_index: map[int]int,
	default_char:            rune,
}

FontVertex :: struct {
	position:   vec3,
	tex_coords: vec2,
}

Text :: struct {
	font:      ^Font,
	text:      string,
	size:      f32,
	vbo:       Buffer,
	vertices:  []FontVertex,
	transform: Gfx_Transform,
	ubo:       Uniform_Buffer,
	pipeline:  Graphics_Pipeline,
}

CharacterRegion :: struct {
	start: i32,
	size:  i32,
}

Create_Font_Info :: struct {
	path:         string,
	size:         f32,
	padding:      i32,
	atlas_width:  i32,
	atlas_height: i32,
	regions:      []CharacterRegion,
	default_char: rune,
}

@(private)
PIXEL_SIZE :: 0.002 // TODO:

load_font :: proc(create_info: Create_Font_Info, loc := #caller_location) -> Font {
	assert(create_info.path != "", loc = loc)
	assert(create_info.atlas_width > 0, loc = loc)
	assert(create_info.atlas_height > 0, loc = loc)
	assert(create_info.atlas_height > 0, loc = loc)
	assert(create_info.padding >= 0, loc = loc)
	assert(create_info.size > 0, loc = loc)
	assert(len(create_info.regions) >= 0, loc = loc)
	assert(create_info.default_char != 0, loc = loc)

	data, ok := read_file(create_info.path, context.temp_allocator)
	assert(ok, fmt.tprint("Couldn't load font. %s", create_info.path), loc)

	font_number := tt.GetNumberOfFonts(raw_data(data))
	assert(
		font_number != -1,
		fmt.tprintf("The font file doesn't correspond to valid font data.", create_info.path),
		loc,
	)

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
			{},
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
	// image.write_png(
	// 	"font_image.png",
	// 	create_info.atlas_width,
	// 	create_info.atlas_height,
	// 	1,
	// 	raw_data(font_atlas_bitmap),
	// 	create_info.atlas_width,
	// )

	image := Image {
		width    = cast(int)create_info.atlas_width,
		height   = cast(int)create_info.atlas_height,
		data     = raw_data(font_atlas_bitmap),
		channels = 1,
	}

	texture_h := create_texture(image, 1)

	return Font {
		name = create_info.path,
		size = create_info.size,
		packed_chars = packed_chars,
		aligned_quads = aligned_quads,
		texture_h = texture_h,
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

create_text :: proc(
	font: ^Font,
	text: string,
	start_position: vec3,
	color: vec4,
	size: f32,
	loc := #caller_location,
) -> Text {
	assert_not_nil(font, loc)

	trf := Gfx_Transform{}
	init_trf(&trf)
	trf_set_position(&trf, start_position)
	trf_set_scale(&trf, vec3{1, 1, 1} * size)

	ubo_h := create_ubo_base()
	ubo_base_set_texture(ubo_h, font.texture_h)
	ubo_base_set_color(ubo_h, color)

	text := Text {
		text      = text,
		font      = font,
		ubo       = ubo_h,
		pipeline  = ctx.gfx.buildin.pipeline.text_h,
		transform = trf,
		size      = size,
	}

	vbo, vertices := _generate_text_mesh(&text)
	text.vbo = vbo
	text.vertices = vertices

	return text
}

text_set_string :: proc(text: ^Text, text_str: string, loc := #caller_location) {
	assert_not_nil(text, loc)

	text.text = text_str
	_deffered_destructor_add(text.vbo)

	text.vbo, _ = _generate_text_mesh(text, loc)
}

text_set_color :: proc(text: ^Text, color: vec4, loc := #caller_location) {
	assert_not_nil(text, loc)

	ubo_base_set_color(text.ubo, color)
}

text_set_position :: proc(text: ^Text, position: vec3, loc := #caller_location) {
	assert_not_nil(text, loc)

	trf_set_position(&text.transform, position)
}

draw_text :: proc(text: ^Text, camera: ^Camera, loc := #caller_location) {
	assert_not_nil(text, loc)

	cmd_bind_vertex_buffer(text.vbo, 0)

	layout := cmd_bind_graphics_pipeline(text.pipeline)

	const := _get_push_constants_data(&text.transform, {h0 = text.ubo})
	cmd_push_constants(layout, &const)

	cmd_draw(cast(u32)len(text.vertices))
}

destroy_text :: proc(text: ^Text, loc := #caller_location) {
	assert_not_nil(text, loc)

	destroy_buffer(text.vbo)
}

@(private)
_text_shader_attribute :: proc() -> Vertex_Input_Description {
	attribute_descriptions := Vertex_Input_Attribute_Descriptions{}
	sm.push_back_elems(
		&attribute_descriptions,
		Vertex_Input_Attribute_Description {
			location = 0,
			format = .RGB_f32,
			offset = cast(u32)offset_of(FontVertex, position),
		},
		Vertex_Input_Attribute_Description {
			location = 1,
			format = .RG_f32,
			offset = cast(u32)offset_of(FontVertex, tex_coords),
		},
	)

	return Vertex_Input_Description {
		binding = 0,
		stride = size_of(FontVertex),
		input_rate = .Vertex,
		attributes = attribute_descriptions,
	}
}

@(private)
_text_default_pipeline :: proc() -> Graphics_Pipeline {
	vert_descriptions: Vertex_Input_Descriptions
	sm.append(&vert_descriptions, _text_shader_attribute())

	stages := Stage_Infos{}
	sm.push_back_elems(
		&stages,
		Pipeline_Stage_Info{stage = .Vertex, shader_path = "assets/buildin/shaders/text.vert"},
		Pipeline_Stage_Info{stage = .Fragment, shader_path = "assets/buildin/shaders/text.frag"},
	)

	create_info := Create_Pipeline_Info {
		bindless = true,
		vertex_input_descriptions = vert_descriptions,
		stage_infos = stages,
		topology = .Triangle_List,
		rasterizer = {polygon_mode = .Fill, line_width = 1, cull_mode = {}, front_face = .Clockwise},
		depth = {
			enable = true,
			write_enable = true,
			compare_op = .Less,
			bounds_test_enable = false,
			min_bounds = 0,
			max_bounds = 0,
		},
		stencil = {enable = false},
	}

	return create_graphics_pipeline(create_info)
}

@(private = "file")
tt_must :: proc(status: i32, message: string = "Something went wrong with text rendering", loc := #caller_location) {
	if status == 0 {
		log.panic(message, loc)
	}
}

@(private = "file")
_generate_text_mesh :: proc(text: ^Text, loc := #caller_location) -> (Buffer, []FontVertex) {
	position := vec3{0, 0, 0}
	vertices := make([]FontVertex, len(text.text) * 6, context.temp_allocator)
	vertex_index := 0

	order := [6]int{0, 1, 2, 0, 2, 3}

	for ch in text.text {
		code_point := cast(i32)ch

		if ch == '\n' {
			position.y -= PIXEL_SIZE * text.size * text.font.size
			position.x = 0
			continue
		} else if code_point == 0 {
			continue
		}

		char_index: int
		if cast(int)code_point in text.font.codepoint_to_char_index {
			char_index = text.font.codepoint_to_char_index[cast(int)code_point]
		} else {
			char_index = text.font.codepoint_to_char_index[cast(int)text.font.default_char]
			assert(
				char_index != 0,
				fmt.tprintf(
					"The default character '%r' is not exist in Font (%s) regions",
					text.font.default_char,
					text.font.name,
				),
				loc,
			)
		}

		packed_char := text.font.packed_chars[char_index]
		aligned_quad := text.font.aligned_quads[char_index]

		glyph_size := vec2 {
			cast(f32)(packed_char.x1 - packed_char.x0) * PIXEL_SIZE * text.size,
			cast(f32)(packed_char.y1 - packed_char.y0) * PIXEL_SIZE * text.size,
		}

		glyph_bounding_box_bottom_left := vec2 {
			position.x + (packed_char.xoff * PIXEL_SIZE * text.size),
			position.y +
			(packed_char.yoff - packed_char.yoff2 * 2 + cast(f32)packed_char.y1 - cast(f32)packed_char.y0) *
				PIXEL_SIZE *
				text.size,
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
		position.x += packed_char.xadvance * PIXEL_SIZE * text.size
	}

	vertices_size := cast(vk.DeviceSize)(size_of(FontVertex) * len(vertices))
	vertex_buffer := create_buffer({.Vertex}, vertices_size, raw_data(vertices), loc)

	return vertex_buffer, vertices
}
