package ve

import "core:log"
import "core:strconv"
import "core:strings"

Obj_Mesh :: struct {
	name:     string,
	vertices: []Vertex,
	indices:  []u16,
}

Obj_Vertex :: struct {
	p, t, n: int,
}

parse_obj :: proc {
	parse_obj_from_file,
	parse_obj_from_memory,
}

parse_obj_from_file :: proc(path: string, allocator := context.allocator) -> ([]Obj_Mesh, bool) {
	data, ok := read_file(path, context.temp_allocator)
	if !ok {
		log.errorf("Couldn't load file by path: %s", path)
		return nil, false
	}

	return parse_obj_from_memory(data, allocator), true
}

parse_obj_from_memory :: proc(data: []byte, allocator := context.allocator) -> []Obj_Mesh {
	parse_f32 :: proc(s: string) -> f32 {
		value, _ := strconv.parse_f32(s)
		return value
	}

	parse_int :: proc(s: string) -> int {
		value, _ := strconv.parse_int(s)
		return value
	}

	// position, texture coordinates, normal
	parse_f :: proc(s: string) -> (p: int, t: int, n: int) {
		indexes := strings.split(s, "/", context.temp_allocator)
		_p: int = parse_int(indexes[0]) - 1
		_t := -1
		_n := -1
		if len(indexes) > 1 do _t = parse_int(indexes[1]) - 1
		if len(indexes) > 2 do _n = parse_int(indexes[2]) - 1
		return _p, _t, _n
	}

	data_string := string(data)

	meshes := make([dynamic]Obj_Mesh, allocator)

	name := ""
	vertices := make([dynamic]Vertex, allocator)
	indices := make([dynamic]u16, allocator)

	index_by_vertex := make(map[Obj_Vertex]u16, context.temp_allocator)

	positions := make([dynamic]vec3, context.temp_allocator)
	normals := make([dynamic]vec3, context.temp_allocator)
	texture_coordinates := make([dynamic]vec2, context.temp_allocator)

	for line in strings.split_lines_iterator(&data_string) {
		ok: bool
		elements := strings.split(line, " ", context.temp_allocator)

		switch elements[0] {
		case "o":
			if name != "" {
				append(&meshes, Obj_Mesh{name = elements[1], vertices = vertices[:], indices = indices[:]})
				vertices = make([dynamic]Vertex, allocator)
				indices = make([dynamic]u16, allocator)
			}
			name = elements[1]
		case "v":
			append(&positions, vec3{parse_f32(elements[1]), parse_f32(elements[2]), parse_f32(elements[3])})
		case "vn":
			append(&normals, vec3{parse_f32(elements[1]), parse_f32(elements[2]), parse_f32(elements[3])})
		case "vt":
			append(&texture_coordinates, vec2{parse_f32(elements[1]), parse_f32(elements[2])})
		case "f":
			/// f v/vt/vn
			values := elements[1:]
			length := len(values)
			if length < 3 do continue
			line_indices := make([]u16, length, context.temp_allocator)
			for i in 0 ..< length {
				p, t, n := parse_f(values[i])
				hash := Obj_Vertex{p, t, n}
				v_index, ok := index_by_vertex[hash]
				if !ok {
					v: Vertex
					if len(positions) > p && p != -1 do v.position = positions[p]
					if len(texture_coordinates) > t && t != -1 do v.tex_coord = texture_coordinates[t]
					if len(normals) > n && n != -1 do v.normal = normals[n]

					append(&vertices, v)
					v_index = cast(u16)len(vertices) - 1
					index_by_vertex[hash] = v_index
				}
				line_indices[i] = v_index
			}
			for i := 1; i < length - 1; i += 1 {
				append(&indices, line_indices[0])
				append(&indices, line_indices[i])
				append(&indices, line_indices[i + 1])
			}
		case:
			continue
		}
	}
	append(&meshes, Obj_Mesh{name = name, vertices = vertices[:], indices = indices[:]})

	return meshes[:]
}
