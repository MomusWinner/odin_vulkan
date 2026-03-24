package main

import ve ".."
import sm "core:container/small_array"
import "core:log"
import "core:mem/virtual"
import vk "vendor:vulkan"

get_base_create_pipeline_info :: proc() -> ve.Create_Pipeline_Info {
	vert_descriptions: ve.Vertex_Input_Descriptions
	sm.append(&vert_descriptions, ve.create_vertex_input_description())

	return ve.Create_Pipeline_Info {
		bindless = true,
		vertex_input_descriptions = vert_descriptions,
		topology = .Triangle_List,
		rasterizer = {polygon_mode = .Fill, line_width = 1, cull_mode = {.Back}, front_face = .Counter_Clockwise},
		depth = {
			enable = true,
			write_enable = true,
			compare_op = .Less,
			bounds_test_enable = false,
			min_bounds = 0,
			max_bounds = 0,
		},
	}
}

create_default_pipeline :: proc() -> ve.Graphics_Pipeline {
	stages := ve.Stage_Infos{}
	sm.push_back_elems(
		&stages,
		ve.Pipeline_Stage_Info{stage = .Vertex, shader_path = "examples/assets/shaders/default.vert"},
		ve.Pipeline_Stage_Info{stage = .Fragment, shader_path = "examples/assets/shaders/default.frag"},
	)

	create_info := get_base_create_pipeline_info()
	create_info.stage_infos = stages

	return ve.create_graphics_pipeline(create_info)
}

create_skybox_pipeline :: proc() -> ve.Graphics_Pipeline {
	vert_descriptions: ve.Vertex_Input_Descriptions
	sm.append(&vert_descriptions, ve.create_vertex_input_description())

	stages := ve.Stage_Infos{}
	sm.push_back_elems(
		&stages,
		ve.Pipeline_Stage_Info{stage = .Vertex, shader_path = "examples/assets/shaders/skybox.vert"},
		ve.Pipeline_Stage_Info{stage = .Fragment, shader_path = "examples/assets/shaders/skybox.frag"},
	)

	create_info := ve.Create_Pipeline_Info {
		bindless = true,
		vertex_input_descriptions = vert_descriptions,
		stage_infos = stages,
		topology = .Triangle_List,
		rasterizer = {polygon_mode = .Fill, line_width = 1, cull_mode = {.Front}, front_face = .Counter_Clockwise},
	}

	return ve.create_graphics_pipeline(create_info)
}

create_postprocessing_pipeline :: proc() -> ve.Graphics_Pipeline {
	stages := ve.Stage_Infos{}
	sm.push_back_elems(
		&stages,
		ve.Pipeline_Stage_Info{stage = .Vertex, shader_path = "examples/assets/shaders/postprocessing.vert"},
		ve.Pipeline_Stage_Info{stage = .Fragment, shader_path = "examples/assets/shaders/postprocessing.frag"},
	)

	create_info := get_base_create_pipeline_info()
	create_info.stage_infos = stages

	return ve.create_graphics_pipeline(create_info)
}

create_light_pipeline :: proc() -> ve.Graphics_Pipeline {
	stages := ve.Stage_Infos{}
	sm.push_back_elems(
		&stages,
		ve.Pipeline_Stage_Info{stage = .Vertex, shader_path = "examples/assets/shaders/light.vert"},
		ve.Pipeline_Stage_Info{stage = .Fragment, shader_path = "examples/assets/shaders/light.frag"},
	)

	create_info := get_base_create_pipeline_info()
	create_info.stage_infos = stages

	return ve.create_graphics_pipeline(create_info)
}

create_depth_only_pipeline :: proc() -> ve.Graphics_Pipeline {
	vert_descriptions: ve.Vertex_Input_Descriptions
	sm.append(&vert_descriptions, ve.create_vertex_input_description())

	stages := ve.Stage_Infos{}
	sm.push_back_elems(
		&stages,
		ve.Pipeline_Stage_Info{stage = .Vertex, shader_path = "examples/assets/shaders/light.vert"},
	)

	create_info := get_base_create_pipeline_info()
	create_info.stage_infos = stages
	create_info.depth.bias = {
		enable          = true,
		clamp           = 1.25,
		constant_factor = 0,
		slope_factor    = 4.75,
	}

	return ve.create_graphics_pipeline(create_info)
}

create_reflect_pipeline :: proc() -> ve.Graphics_Pipeline {
	vert_descriptions: ve.Vertex_Input_Descriptions
	sm.append(&vert_descriptions, ve.create_vertex_input_description())

	stages := ve.Stage_Infos{}
	sm.push_back_elems(
		&stages,
		ve.Pipeline_Stage_Info{stage = .Vertex, shader_path = "examples/assets/shaders/reflect.vert"},
		ve.Pipeline_Stage_Info{stage = .Fragment, shader_path = "examples/assets/shaders/reflect.frag"},
	)

	create_info := get_base_create_pipeline_info()
	create_info.stage_infos = stages
	create_info.rasterizer = {
		polygon_mode = .Fill,
		line_width   = 1,
		cull_mode    = {},
		front_face   = .Counter_Clockwise,
	}

	return ve.create_graphics_pipeline(create_info)
}

create_hdr_pipeline :: proc() -> ve.Graphics_Pipeline {
	stages := ve.Stage_Infos{}
	sm.push_back_elems(
		&stages,
		ve.Pipeline_Stage_Info{stage = .Vertex, shader_path = "examples/assets/shaders/hdr.vert"},
		ve.Pipeline_Stage_Info{stage = .Fragment, shader_path = "examples/assets/shaders/hdr.frag"},
	)

	create_info := get_base_create_pipeline_info()
	create_info.stage_infos = stages

	return ve.create_graphics_pipeline(create_info)
}

create_outline_model_pipeline :: proc() -> ve.Graphics_Pipeline {
	stages := ve.Stage_Infos{}
	sm.push_back_elems(
		&stages,
		ve.Pipeline_Stage_Info{stage = .Vertex, shader_path = "examples/assets/shaders/default.vert"},
		ve.Pipeline_Stage_Info{stage = .Fragment, shader_path = "examples/assets/shaders/default.frag"},
	)

	stencil_state := ve.Stencil_Op_State {
		failOp      = .Replace,
		passOp      = .Replace,
		depthFailOp = .Replace,
		compareOp   = .Always,
		compareMask = 0xff,
		writeMask   = 0xff,
		reference   = 1,
	}

	create_info := get_base_create_pipeline_info()
	create_info.stage_infos = stages
	create_info.stencil = {
		enable = true,
		front  = stencil_state,
		back   = stencil_state,
	}

	return ve.create_graphics_pipeline(create_info)
}

create_outline_pipeline :: proc() -> ve.Graphics_Pipeline {
	stages := ve.Stage_Infos{}
	sm.push_back_elems(
		&stages,
		ve.Pipeline_Stage_Info{stage = .Vertex, shader_path = "examples/assets/shaders/outline.vert"},
		ve.Pipeline_Stage_Info{stage = .Fragment, shader_path = "examples/assets/shaders/outline.frag"},
	)

	stencil_state := ve.Stencil_Op_State {
		failOp      = .Keep,
		passOp      = .Replace,
		depthFailOp = .Keep,
		compareOp   = .Not_Equal,
		compareMask = 0xff,
		writeMask   = 0xff,
		reference   = 1,
	}

	create_info := get_base_create_pipeline_info()
	create_info.stage_infos = stages
	create_info.stencil = {
		enable = true,
		front  = stencil_state,
		back   = stencil_state,
	}

	return ve.create_graphics_pipeline(create_info)
}

create_multilight_pipeline :: proc() -> ve.Graphics_Pipeline {
	stages := ve.Stage_Infos{}
	sm.push_back_elems(
		&stages,
		ve.Pipeline_Stage_Info{stage = .Vertex, shader_path = "examples/assets/shaders/multilight.vert"},
		ve.Pipeline_Stage_Info{stage = .Fragment, shader_path = "examples/assets/shaders/multilight.frag"},
	)

	create_info := get_base_create_pipeline_info()
	create_info.stage_infos = stages

	return ve.create_graphics_pipeline(create_info)
}

create_gaussian_blur_pipeline :: proc(horizontal: b32) -> ve.Graphics_Pipeline {
	consts := ve.Shader_Constants{}
	sm.append(&consts, ve.Shader_Constant{id = 0, value = {bool = horizontal}})

	stages := ve.Stage_Infos{}
	sm.push_back_elems(
		&stages,
		ve.Pipeline_Stage_Info{stage = .Vertex, shader_path = "examples/assets/shaders/gaussian_blur.vert"},
		ve.Pipeline_Stage_Info {
			stage = .Fragment,
			shader_path = "examples/assets/shaders/gaussian_blur.frag",
			consts = consts,
		},
	)

	create_info := get_base_create_pipeline_info()
	create_info.stage_infos = stages

	return ve.create_graphics_pipeline(create_info)
}

create_light_source_pipeline :: proc() -> ve.Graphics_Pipeline {
	stages := ve.Stage_Infos{}
	sm.push_back_elems(
		&stages,
		ve.Pipeline_Stage_Info{stage = .Vertex, shader_path = "examples/assets/shaders/light_source.vert"},
		ve.Pipeline_Stage_Info{stage = .Fragment, shader_path = "examples/assets/shaders/light_source.frag"},
	)

	create_info := get_base_create_pipeline_info()
	create_info.stage_infos = stages

	return ve.create_graphics_pipeline(create_info)
}

create_instance_vertex_description :: proc() -> ve.Vertex_Input_Description {
	attribute_descriptions := ve.Vertex_Input_Attribute_Descriptions{}
	sm.push_back_elems(
		&attribute_descriptions,
		ve.Vertex_Input_Attribute_Description {
			location = 4,
			format = .RGB_f32,
			offset = cast(u32)offset_of(Rock_Instance, position),
		},
		ve.Vertex_Input_Attribute_Description {
			location = 5,
			format = .RGB_f32,
			offset = cast(u32)offset_of(Rock_Instance, color),
		},
		ve.Vertex_Input_Attribute_Description {
			location = 6,
			format = .R_f32,
			offset = cast(u32)offset_of(Rock_Instance, scale),
		},
	)

	return ve.Vertex_Input_Description {
		binding = 1,
		stride = size_of(Rock_Instance),
		input_rate = .Instance,
		attributes = attribute_descriptions,
	}
}

create_instancing_pipeline :: proc() -> ve.Graphics_Pipeline {
	vert_descriptions: ve.Vertex_Input_Descriptions
	sm.append(&vert_descriptions, ve.create_vertex_input_description())
	sm.append(&vert_descriptions, create_instance_vertex_description())

	stages := ve.Stage_Infos{}
	sm.push_back_elems(
		&stages,
		ve.Pipeline_Stage_Info{stage = .Vertex, shader_path = "examples/assets/shaders/instancing.vert"},
		ve.Pipeline_Stage_Info{stage = .Fragment, shader_path = "examples/assets/shaders/instancing.frag"},
	)

	create_info := ve.Create_Pipeline_Info {
		bindless = true,
		vertex_input_descriptions = vert_descriptions,
		stage_infos = stages,
		topology = .Triangle_List,
		rasterizer = {polygon_mode = .Fill, line_width = 1, cull_mode = {.Back}, front_face = .Counter_Clockwise},
		depth = {enable = true, write_enable = true, compare_op = .Less},
	}

	return ve.create_graphics_pipeline(create_info)
}

create_particle_vertex_description :: proc() -> ve.Vertex_Input_Description {
	attribute_descriptions := ve.Vertex_Input_Attribute_Descriptions{}
	sm.push_back_elems(
		&attribute_descriptions,
		ve.Vertex_Input_Attribute_Description {
			location = 0,
			format = .RG_f32,
			offset = cast(u32)offset_of(std430_Particle, position),
		},
		ve.Vertex_Input_Attribute_Description {
			location = 1,
			format = .RG_f32,
			offset = cast(u32)offset_of(std430_Particle, velocity),
		},
	)

	return ve.Vertex_Input_Description {
		binding = 0,
		stride = size_of(std430_Particle),
		input_rate = .Vertex,
		attributes = attribute_descriptions,
	}
}

create_particle_pipeline :: proc() -> ve.Graphics_Pipeline {
	stages := ve.Stage_Infos{}
	sm.push_back_elems(
		&stages,
		ve.Pipeline_Stage_Info{stage = .Vertex, shader_path = "examples/assets/shaders/particle.vert"},
		ve.Pipeline_Stage_Info{stage = .Fragment, shader_path = "examples/assets/shaders/particle.frag"},
	)

	vert_descriptions: ve.Vertex_Input_Descriptions
	sm.append(&vert_descriptions, create_particle_vertex_description())

	create_info := get_base_create_pipeline_info()
	create_info.stage_infos = stages
	create_info.vertex_input_descriptions = vert_descriptions
	create_info.topology = .Point_List
	create_info.rasterizer.cull_mode = {}
	create_info.depth.enable = false

	return ve.create_graphics_pipeline(create_info)
}

create_compute_pipeline :: proc(x_invocations: i32) -> ve.Compute_Pipeline {
	consts := ve.Shader_Constants{}
	sm.append(&consts, ve.Shader_Constant{id = 0, value = {int = x_invocations}})

	info := ve.Create_Compute_Pipeline_Info {
		bindless    = true,
		shader_path = "examples/assets/shaders/particle.comp",
		consts      = consts,
	}
	handle := ve.create_compute_pipeline(info)
	return handle
}
