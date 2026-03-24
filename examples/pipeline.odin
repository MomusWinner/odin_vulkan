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

create_light_box_pipeline :: proc() -> ve.Graphics_Pipeline {
	stages := ve.Stage_Infos{}
	sm.push_back_elems(
		&stages,
		ve.Pipeline_Stage_Info{stage = .Vertex, shader_path = "examples/assets/shaders/light_box.vert"},
		ve.Pipeline_Stage_Info{stage = .Fragment, shader_path = "examples/assets/shaders/light_box.frag"},
	)

	create_info := get_base_create_pipeline_info()
	create_info.stage_infos = stages

	return ve.create_graphics_pipeline(create_info)
}
