package ve

import sm "core:container/small_array"
import "core:log"
import vk "vendor:vulkan"

Mesh :: struct {
	vbo:          Buffer,
	ebo:          Maybe(Buffer),
	vertex_count: u32,
	index_count:  u32,
}

create_mesh :: proc(vertices: []Vertex, indices: []u16, loc := #caller_location) -> Mesh {
	assert(len(vertices) > 0, loc = loc)

	vertices_size := cast(vk.DeviceSize)(size_of(vertices[0]) * len(vertices))
	vertex_buffer := create_buffer({.Vertex}, vertices_size, raw_data(vertices), loc)

	mesh := Mesh {
		vertex_count = cast(u32)len(vertices),
		vbo          = vertex_buffer,
	}

	if len(indices) != 0 {
		indices_size := cast(vk.DeviceSize)(size_of(indices[0]) * len(indices))
		index_buffer := create_buffer({.Index}, indices_size, raw_data(indices), loc)
		mesh.ebo = index_buffer
		mesh.index_count = cast(u32)len(indices)
	} else {
		mesh.ebo = nil
	}

	return mesh
}

destroy_mesh :: proc(mesh: ^Mesh, loc := #caller_location) {
	assert_not_nil(mesh)

	destroy_buffer(&mesh.vbo)
	ebo, has_ebo := mesh.ebo.?
	if has_ebo {
		destroy_buffer(&ebo)
	}
}

draw_mesh :: proc(
	mesh: ^Mesh,
	pipeline: ^Render_Pipeline,
	consts: Push_Constants,
	instance_count: u32 = 1,
	loc := #caller_location,
) {
	assert_gfx_ctx(loc)
	assert_not_nil(mesh, loc)
	assert_not_nil(pipeline, loc)

	ebo, has_ebo := mesh.ebo.?

	cmd_bind_vertex_buffer(mesh.vbo, 0, loc = loc)
	if has_ebo {
		cmd_bind_index_buffer(ebo, loc = loc)
	}

	g_pipeline := cmd_bind_render_pipeline(pipeline, loc)

	consts := _push_constants_to_data(consts)
	cmd_push_constants(g_pipeline, &consts)

	if has_ebo {
		cmd_draw_indexed(mesh.index_count, instance_count)
	} else {
		cmd_draw(mesh.vertex_count, instance_count)
	}
}

@(private)
_push_constants_to_data :: proc(consts: Push_Constants, loc := #caller_location) -> Push_Constants_Data {
	INVALID_HANDLE :: max(u32)

	aspect := cast(f32)get_screen_width() / cast(f32)get_screen_height()
	consts_data := Push_Constants_Data {
		model  = trf_get_matrix(consts.trf) if consts.trf != nil else 1,
		camera = _camera_get_buffer(consts.camera, aspect).index if consts.camera != nil else Nil_Buffer_Handle.index,
	}

	resource_to_index :: proc(r: Resource_Handle) -> u32 {
		switch h in r {
		case Uniform_Buffer_Handle:
			b, ok := get_uniform_buffer(h)
			if !ok {
				return INVALID_HANDLE
			}
			return b.buffer_h.index if has_buffer_h(b.buffer_h) else INVALID_HANDLE
		case Storage_Buffer_Handle:
			b, ok := get_storage_buffer(h)
			if !ok {
				return INVALID_HANDLE
			}
			return b.buffer_h.index if has_buffer_h(b.buffer_h) else INVALID_HANDLE
		case Buffer_Handle:
			return h.index if has_buffer_h(h) else INVALID_HANDLE
		case Texture_Handle:
			return h.index if has_texture_h(h) else INVALID_HANDLE
		}
		return INVALID_HANDLE
	}

	consts_data.handles[0] = resource_to_index(consts.h0)
	consts_data.handles[1] = resource_to_index(consts.h1)
	consts_data.handles[2] = resource_to_index(consts.h2)
	consts_data.handles[3] = resource_to_index(consts.h3)
	consts_data.handles[4] = resource_to_index(consts.h4)
	consts_data.handles[5] = resource_to_index(consts.h5)
	consts_data.handles[6] = resource_to_index(consts.h6)
	consts_data.handles[7] = resource_to_index(consts.h7)
	consts_data.handles[8] = resource_to_index(consts.h8)
	consts_data.handles[9] = resource_to_index(consts.h9)

	return consts_data
}
