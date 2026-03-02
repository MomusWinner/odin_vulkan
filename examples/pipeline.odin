package main

import ve ".."
import sm "core:container/small_array"
import "core:log"
import "core:mem/virtual"
import vk "vendor:vulkan"

create_default_vertex_description :: proc() -> ve.Vertex_Input_Description {
	attribute_descriptions := ve.Vertex_Input_Attribute_Descriptions{}
	sm.push_back_elems(
		&attribute_descriptions,
		ve.Vertex_Input_Attribute_Description {
			location = 0,
			format = .RGB_f32,
			offset = cast(u32)offset_of(ve.Vertex, position),
		},
		ve.Vertex_Input_Attribute_Description {
			location = 1,
			format = .RG_f32,
			offset = cast(u32)offset_of(ve.Vertex, tex_coord),
		},
		ve.Vertex_Input_Attribute_Description {
			location = 2,
			format = .RGB_f32,
			offset = cast(u32)offset_of(ve.Vertex, normal),
		},
		ve.Vertex_Input_Attribute_Description {
			location = 3,
			format = .RGBA_f32,
			offset = cast(u32)offset_of(ve.Vertex, color),
		},
	)

	return ve.Vertex_Input_Description {
		binding = 0,
		stride = size_of(ve.Vertex),
		input_rate = .Vertex,
		attributes = attribute_descriptions,
	}
}

get_base_create_pipeline_info :: proc() -> ve.Create_Pipeline_Info {
	vert_descriptions: ve.Vertex_Input_Descriptions
	sm.append(&vert_descriptions, create_default_vertex_description())

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

create_default_pipeline :: proc() -> ve.Render_Pipeline_Handle {

	stages := ve.Stage_Infos{}
	sm.push_back_elems(
		&stages,
		ve.Pipeline_Stage_Info{stage = .Vertex, shader_path = "assets/buildin/shaders/default.vert"},
		ve.Pipeline_Stage_Info{stage = .Fragment, shader_path = "assets/buildin/shaders/default.frag"},
	)

	create_info := get_base_create_pipeline_info()
	create_info.stage_infos = stages

	return ve.create_render_pipeline(create_info)
}

create_postprocessing_pipeline :: proc() -> ve.Render_Pipeline_Handle {
	stages := ve.Stage_Infos{}
	sm.push_back_elems(
		&stages,
		ve.Pipeline_Stage_Info{stage = .Vertex, shader_path = "assets/shaders/postprocessing.vert"},
		ve.Pipeline_Stage_Info{stage = .Fragment, shader_path = "assets/shaders/postprocessing.frag"},
	)

	create_info := get_base_create_pipeline_info()
	create_info.stage_infos = stages

	return ve.create_render_pipeline(create_info)
}

create_depth_pipeline :: proc() -> ve.Render_Pipeline_Handle {
	stages := ve.Stage_Infos{}
	sm.push_back_elems(
		&stages,
		ve.Pipeline_Stage_Info{stage = .Vertex, shader_path = "assets/shaders/depth.vert"},
		ve.Pipeline_Stage_Info{stage = .Fragment, shader_path = "assets/shaders/depth.frag"},
	)

	create_info := get_base_create_pipeline_info()
	create_info.stage_infos = stages

	return ve.create_render_pipeline(create_info)
}

create_light_pipeline :: proc() -> ve.Render_Pipeline_Handle {
	stages := ve.Stage_Infos{}
	sm.push_back_elems(
		&stages,
		ve.Pipeline_Stage_Info{stage = .Vertex, shader_path = "assets/shaders/light.vert"},
		ve.Pipeline_Stage_Info{stage = .Fragment, shader_path = "assets/shaders/light.frag"},
	)

	create_info := get_base_create_pipeline_info()
	create_info.stage_infos = stages

	return ve.create_render_pipeline(create_info)
}

create_depth_only_pipeline :: proc() -> ve.Render_Pipeline_Handle {
	vert_descriptions: ve.Vertex_Input_Descriptions
	sm.append(&vert_descriptions, create_default_vertex_description())

	set_infos := ve.Pipeline_Set_Layout_Infos{}
	sm.push_back(&set_infos, ve.get_bindless_pipeline_set_info())

	stages := ve.Stage_Infos{}
	sm.push_back_elems(&stages, ve.Pipeline_Stage_Info{stage = .Vertex, shader_path = "assets/shaders/light.vert"})

	create_info := get_base_create_pipeline_info()
	create_info.stage_infos = stages
	create_info.depth.bias = {
		enable          = true,
		constant_factor = 1.25,
		clamp           = 0,
		slope_factor    = 4.75,
	}

	return ve.create_render_pipeline(create_info)
}

create_skybox_pipeline :: proc() -> ve.Render_Pipeline_Handle {
	vert_descriptions: ve.Vertex_Input_Descriptions
	sm.append(&vert_descriptions, create_default_vertex_description())

	stages := ve.Stage_Infos{}
	sm.push_back_elems(
		&stages,
		ve.Pipeline_Stage_Info{stage = .Vertex, shader_path = "assets/shaders/skybox.vert"},
		ve.Pipeline_Stage_Info{stage = .Fragment, shader_path = "assets/shaders/skybox.frag"},
	)

	create_info := ve.Create_Pipeline_Info {
		bindless = true,
		vertex_input_descriptions = vert_descriptions,
		stage_infos = stages,
		topology = .Triangle_List,
		rasterizer = {polygon_mode = .Fill, line_width = 1, cull_mode = {.Front}, front_face = .Counter_Clockwise},
	}

	return ve.create_render_pipeline(create_info)
}

create_reflect_pipeline :: proc() -> ve.Render_Pipeline_Handle {
	vert_descriptions: ve.Vertex_Input_Descriptions
	sm.append(&vert_descriptions, create_default_vertex_description())

	set_infos := ve.Pipeline_Set_Layout_Infos{}
	sm.push_back(&set_infos, ve.get_bindless_pipeline_set_info())

	stages := ve.Stage_Infos{}
	sm.push_back_elems(
		&stages,
		ve.Pipeline_Stage_Info{stage = .Vertex, shader_path = "assets/shaders/reflect.vert"},
		ve.Pipeline_Stage_Info{stage = .Fragment, shader_path = "assets/shaders/reflect.frag"},
	)

	create_info := get_base_create_pipeline_info()
	create_info.stage_infos = stages
	create_info.rasterizer = {
		polygon_mode = .Fill,
		line_width   = 1,
		cull_mode    = {},
		front_face   = .Counter_Clockwise,
	}

	return ve.create_render_pipeline(create_info)
}

create_outline_model_pipeline :: proc() -> ve.Render_Pipeline_Handle {
	stages := ve.Stage_Infos{}
	sm.push_back_elems(
		&stages,
		ve.Pipeline_Stage_Info{stage = .Vertex, shader_path = "assets/buildin/shaders/default.vert"},
		ve.Pipeline_Stage_Info{stage = .Fragment, shader_path = "assets/buildin/shaders/default.frag"},
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

	return ve.create_render_pipeline(create_info)
}

create_outline_pipeline :: proc() -> ve.Render_Pipeline_Handle {
	stages := ve.Stage_Infos{}
	sm.push_back_elems(
		&stages,
		ve.Pipeline_Stage_Info{stage = .Vertex, shader_path = "assets/shaders/outline.vert"},
		ve.Pipeline_Stage_Info{stage = .Fragment, shader_path = "assets/shaders/outline.frag"},
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

	return ve.create_render_pipeline(create_info)
}

create_hdr_pipeline :: proc() -> ve.Render_Pipeline_Handle {
	stages := ve.Stage_Infos{}
	sm.push_back_elems(
		&stages,
		ve.Pipeline_Stage_Info{stage = .Vertex, shader_path = "assets/shaders/hdr.vert"},
		ve.Pipeline_Stage_Info{stage = .Fragment, shader_path = "assets/shaders/hdr.frag"},
	)

	create_info := get_base_create_pipeline_info()
	create_info.stage_infos = stages

	return ve.create_render_pipeline(create_info)
}


create_mulilight_pipeline :: proc() -> ve.Render_Pipeline_Handle {
	stages := ve.Stage_Infos{}
	sm.push_back_elems(
		&stages,
		ve.Pipeline_Stage_Info{stage = .Vertex, shader_path = "assets/shaders/multilight.vert"},
		ve.Pipeline_Stage_Info{stage = .Fragment, shader_path = "assets/shaders/multilight.frag"},
	)

	create_info := get_base_create_pipeline_info()
	create_info.stage_infos = stages

	return ve.create_render_pipeline(create_info)
}

create_gaussian_blur_pipeline :: proc(horizontal: b32) -> ve.Render_Pipeline_Handle {
	consts := ve.Shader_Constants{}
	sm.append(&consts, ve.Shader_Constant{id = 0, value = {bool = horizontal}})

	stages := ve.Stage_Infos{}
	sm.push_back_elems(
		&stages,
		ve.Pipeline_Stage_Info{stage = .Vertex, shader_path = "assets/shaders/gaussian_blur.vert"},
		ve.Pipeline_Stage_Info{stage = .Fragment, shader_path = "assets/shaders/gaussian_blur.frag", consts = consts},
	)

	create_info := get_base_create_pipeline_info()
	create_info.stage_infos = stages

	return ve.create_render_pipeline(create_info)
}

create_light_box_pipeline :: proc() -> ve.Render_Pipeline_Handle {
	stages := ve.Stage_Infos{}
	sm.push_back_elems(
		&stages,
		ve.Pipeline_Stage_Info{stage = .Vertex, shader_path = "assets/shaders/light_box.vert"},
		ve.Pipeline_Stage_Info{stage = .Fragment, shader_path = "assets/shaders/light_box.frag"},
	)

	create_info := get_base_create_pipeline_info()
	create_info.stage_infos = stages

	return ve.create_render_pipeline(create_info)
}
