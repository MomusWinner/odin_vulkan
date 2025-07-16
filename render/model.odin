package render

import "base:runtime"

import "core:log"
import "core:math"
import "core:slice"
import "core:strings"

import "vendor:glfw"
import vk "vendor:vulkan"

vec2 :: [2]f32
vec3 :: [3]f32

Pipeline :: struct {
	pipeline:        vk.Pipeline,
	pipeline_layout: vk.PipelineLayout,
}

Vertex :: struct {
	pos:   vec2,
	color: vec3,
}


get_vertex_input_binding_description :: proc() -> vk.VertexInputBindingDescription {
	description := vk.VertexInputBindingDescription {
		binding   = 0,
		stride    = size_of(Vertex),
		inputRate = .VERTEX,
	}

	return description
}

get_vertex_attribute_description :: proc() -> [2]vk.VertexInputAttributeDescription {
	descriptions := [2]vk.VertexInputAttributeDescription{}
	descriptions[0] = vk.VertexInputAttributeDescription {
		binding  = 0,
		location = 0,
		format   = .R32G32_SFLOAT,
		offset   = cast(u32)offset_of(Vertex, pos),
	}
	descriptions[1] = vk.VertexInputAttributeDescription {
		binding  = 0,
		location = 1,
		format   = .R32G32B32_SFLOAT,
		offset   = cast(u32)offset_of(Vertex, color),
	}


	return descriptions
}

Model :: struct {
	vertices: []vec3,
}
