package ve

import hm "container/handle_map"
import "core:c"
import sm "core:container/small_array"
import "core:fmt"
import "core:log"
import "core:slice"
import "core:strings"
import "lib/shaderc"
import vk "vendor:vulkan"

Pipeline_Set_Binding_Info :: struct {
	binding:          u32,
	descriptor_type:  vk.DescriptorType,
	descriptor_count: u32,
	stage_flags:      vk.ShaderStageFlags,
	flags:            Maybe(vk.DescriptorBindingFlags),
}

Pipeline_Resource :: union {
	Texture,
	Buffer,
}

Shader_Stage_Flags :: distinct bit_set[Shader_Stage_Flag]
Shader_Stage_Flag :: enum {
	Vertex,
	Geometry,
	Fragment,
	Compute,
}

Shader_Constant_Value :: struct #raw_union {
	bool:  b32,
	int:   i32,
	uint:  u32,
	float: f32,
}

Shader_Constant :: struct {
	id:    u32,
	value: Shader_Constant_Value,
}
Shader_Constants :: sm.Small_Array(MAX_PIPELINE_SHADER_CONTANT_COUNT, Shader_Constant)

Pipeline_Stage_Info :: struct {
	stage:       Shader_Stage_Flag,
	shader_path: string,
	consts:      Shader_Constants,
}

Pipeline_Color_BlendAttachment_States :: sm.Small_Array(MAX_COLOR_ATTACHMENTS, vk.PipelineColorBlendAttachmentState)
Pipeline_Set_Layout_Infos :: sm.Small_Array(MAX_PIPELINE_SET_COUNT, Pipeline_Set_Layout_Info)
Descriptor_Set_Layouts :: sm.Small_Array(MAX_PIPELINE_SET_COUNT, vk.DescriptorSetLayout)
Stage_Infos :: sm.Small_Array(MAX_PIPELINE_STAGE_COUNT, Pipeline_Stage_Info)

Pipeline_Shader_Stage_Create_Infos :: sm.Small_Array(MAX_PIPELINE_STAGE_COUNT, vk.PipelineShaderStageCreateInfo)
Pipeline_Dynamic_States :: sm.Small_Array(MAX_PIPELINE_DYNAMIC_STATE_COUNT, vk.DynamicState)

Pipeline_Set_Binding_Infos :: sm.Small_Array(MAX_PIPELINE_BINDING_COUNT, Pipeline_Set_Binding_Info)

Pipeline_Set_Layout_Info :: struct {
	binding_infos: Pipeline_Set_Binding_Infos,
}

Stencil_Op_State :: struct {
	failOp:      Stencil_Op,
	passOp:      Stencil_Op,
	depthFailOp: Stencil_Op,
	compareOp:   Compare_Op,
	compareMask: u32,
	writeMask:   u32,
	reference:   u32,
}

Blend_Factor :: enum c.int {
	Zero                     = 0,
	One                      = 1,
	Src_Color                = 2,
	One_Minus_Src_Color      = 3,
	Dst_Color                = 4,
	One_Minus_Dst_Color      = 5,
	Src_Alpha                = 6,
	One_Minus_Src_Alpha      = 7,
	Dst_Alpha                = 8,
	One_Minus_Dst_Alpha      = 9,
	Constant_Color           = 10,
	One_Minus_Constant_Color = 11,
	Constant_Alpha           = 12,
	One_Minus_Constant_Alpha = 13,
	Src_Alpha_Saturate       = 14,
	Src1_Color               = 15,
	One_Minus_Src1_Color     = 16,
	Src1_Alpha               = 17,
	One_Minus_Src1_Alpha     = 18,
}

BlendOp :: enum c.int {
	Add              = 0,
	Subtract         = 1,
	Reverse_Subtract = 2,
	Min              = 3,
	Max              = 4,
}

Blending_Info :: struct {
	src_color_blend_factor: Blend_Factor,
	dst_color_blend_factor: Blend_Factor,
	color_blend_op:         BlendOp,
	src_alpha_blend_factor: Blend_Factor,
	dst_alpha_blend_factor: Blend_Factor,
	alpha_blend_op:         BlendOp,
	color_write_mask:       vk.ColorComponentFlags,
}

Blending_Infos :: sm.Small_Array(MAX_COLOR_ATTACHMENTS, Blending_Info)

Front_Face :: enum c.int {
	Counter_Clockwise = 0,
	Clockwise         = 1,
}

Polygon_Mode :: enum c.int {
	Fill  = 0,
	Line  = 1,
	Point = 2,
}

Primitive_Topology :: enum c.int {
	Point_List                    = 0,
	Line_List                     = 1,
	Line_Strip                    = 2,
	Triangle_List                 = 3,
	Triangle_Strip                = 4,
	Triangle_Fan                  = 5,
	Line_List_With_Adjacency      = 6,
	Line_Strip_With_Adjacency     = 7,
	Triangle_List_With_Adjacency  = 8,
	Triangle_Strip_With_Adjacency = 9,
	Patch_List                    = 10,
}

Cull_Mode_Flags :: distinct bit_set[Cull_Mode_Flag;vk.Flags]
Cull_Mode_Flag :: enum vk.Flags {
	Front = 0,
	Back  = 1,
}

Compare_Op :: enum c.int {
	Never            = 0,
	Less             = 1,
	Equal            = 2,
	Less_Or_Equal    = 3,
	Greater          = 4,
	Not_Equal        = 5,
	Greater_Or_Equal = 6,
	Always           = 7,
}

Stencil_Op :: enum c.int {
	// keeps the current value
	Keep                = 0,
	// sets the value to 0
	Zero                = 1,
	// sets the value to reference
	Replace             = 2,
	// increments the current value and clamps to the maximum representable unsigned value
	Increment_And_Clamp = 3,
	// decrements the current value and clamps to 0
	Decrement_And_Clamp = 4,
	// bitwise-inverts the current value
	Invert              = 5,
	// increments the current value and wraps to 0 when the maximum value would have been exceeded.
	Increment_And_Wrap  = 6,
	// decrements the current value and wraps to the maximum possible value when the value would go below 0.
	Decrement_And_Wrap  = 7,
}

Create_Pipeline_Info :: struct {
	descriptor_set_infos:      Pipeline_Set_Layout_Infos,
	bindless:                  bool,
	stage_infos:               Stage_Infos,
	vertex_input_descriptions: Vertex_Input_Descriptions,
	topology:                  Primitive_Topology,
	rasterizer:                struct {
		polygon_mode: Polygon_Mode,
		line_width:   f32,
		cull_mode:    Cull_Mode_Flags,
		front_face:   Front_Face,
	},
	blending_info:             struct {
		attachment_infos: Blending_Infos,
	},
	depth:                     struct {
		enable:             b32,
		write_enable:       b32,
		compare_op:         Compare_Op,
		bounds_test_enable: b32,
		min_bounds:         f32,
		max_bounds:         f32,
		bias:               struct {
			enable:          b32,
			clamp:           f32,
			constant_factor: f32,
			slope_factor:    f32,
		},
	},
	stencil:                   struct {
		enable: b32,
		front:  Stencil_Op_State,
		back:   Stencil_Op_State,
	},
}

Create_Compute_Pipeline_Info :: struct {
	set_infos:   Pipeline_Set_Layout_Infos,
	shader_path: string,
}

Pipeline :: struct {
	pipeline: vk.Pipeline,
	layout:   Pipeline_Layout_Info,
}

Render_Pipeline :: struct {
	cache:       map[Pipeline_Surface_Info]Graphics_Pipeline,
	create_info: Create_Pipeline_Info,
}

Graphics_Pipeline :: struct {
	using base:   Pipeline,
	surface_info: Surface_Info,
}

Compute_Pipeline :: struct {
	using base:  Pipeline,
	create_info: ^Create_Compute_Pipeline_Info,
}

Push_Constant :: struct {
	model:    mat4,
	camera:   u32,
	material: u32,
	reserve0: u32,
	reserve1: u32,
	reserve2: u32,
	reserve3: u32,
	slots:    [MAX_SLOT_COUNT]u32,
}

Pipeline_Handle :: distinct hm.Handle
Render_Pipeline_Handle :: distinct hm.Handle

Pipeline_Manager :: struct {
	render_pipelines:   hm.Handle_Map(Render_Pipeline, Render_Pipeline_Handle),
	compute_pipelines:  hm.Handle_Map(Compute_Pipeline, Pipeline_Handle),
	compiler:           shaderc.compilerT,
	compiler_options:   shaderc.compileOptionsT,
	enable_compilation: bool,
}

Vertex_Input_Rate :: enum {
	Vertex,
	Instance,
}

Vertex_Input_Attribute_Description :: struct {
	location: u32,
	format:   Pixel_Format,
	offset:   u32,
}

Vertex_Input_Attribute_Descriptions :: sm.Small_Array(
	MAX_PIPELINE_VERTEX_INPUT_ATTRIBUTE_COUNT,
	Vertex_Input_Attribute_Description,
)

Vertex_Input_Description :: struct {
	binding:    u32,
	stride:     u32,
	input_rate: Vertex_Input_Rate,
	attributes: Vertex_Input_Attribute_Descriptions,
}
Vertex_Input_Descriptions :: sm.Small_Array(MAX_PIPELINE_BINDING_COUNT, Vertex_Input_Description)

Pipeline_Surface_Info :: struct {
	sample_count:  Sample_Count_Flag,
	depth_format:  vk.Format,
	color_formats: sm.Small_Array(MAX_COLOR_ATTACHMENTS, vk.Format),
}

hot_reload_shaders :: proc() {
	_pipeline_manager_hot_reload()
}

get_render_pipeline :: proc(handle: Render_Pipeline_Handle) -> (^Render_Pipeline, bool) {
	return _pipeline_manager_get_render_pipeline(ctx.gfx.pipeline_manager, handle)
}

get_compute_pipeline :: proc(handle: Pipeline_Handle) -> (^Compute_Pipeline, bool) {
	return _pipeline_manager_get_compute_pipeline(ctx.gfx.pipeline_manager, handle)
}

_init_pipeline_manager :: proc(enable_compilation: bool) {
	assert(ctx.gfx.pipeline_manager == nil)
	ctx.gfx.pipeline_manager = new(Pipeline_Manager)
	_pipeline_manager_init(ctx.gfx.pipeline_manager, enable_compilation)
}

_destroy_pipeline_manager :: proc() {
	_pipeline_manager_destroy(ctx.gfx.pipeline_manager)
	free(ctx.gfx.pipeline_manager)
}

@(private = "file")
_pipeline_manager_init :: proc(pm: ^Pipeline_Manager, enable_compilation: bool) {
	pm.enable_compilation = enable_compilation
	if pm.enable_compilation {
		when GFX_DEBUG {
			_pipeline_manager_setup_compiler(pm)
		} else {
			log.panic("Couldn't setup Pipeline_Manager compiler in RELEASE mode")
		}
	}
}

@(private = "file")
_pipeline_manager_destroy :: proc(pm: ^Pipeline_Manager) {
	for &pipeline in pm.render_pipelines.values {
		destroy_render_pipeline(&pipeline)
	}
	for &pipeline in pm.compute_pipelines.values {
		destroy_compute_pipeline(&pipeline)
	}
	hm.destroy(&pm.render_pipelines)
	hm.destroy(&pm.compute_pipelines)
	when GFX_DEBUG {
		shaderc.compile_options_release(pm.compiler_options)
		shaderc.compiler_release(pm.compiler)
	}
}

@(private)
_pipeline_manager_add_render_pipeline :: proc(
	pm: ^Pipeline_Manager,
	pipeline: Render_Pipeline,
) -> Render_Pipeline_Handle {
	return hm.insert(&pm.render_pipelines, pipeline)
}

@(private)
_pipeline_manager_registe_compute_pipeline :: proc(
	pm: ^Pipeline_Manager,
	pipeline: Compute_Pipeline,
) -> Pipeline_Handle {
	return hm.insert(&pm.compute_pipelines, pipeline)
}

@(private = "file")
_pipeline_manager_get_render_pipeline :: proc(
	pm: ^Pipeline_Manager,
	handle: Render_Pipeline_Handle,
) -> (
	^Render_Pipeline,
	bool,
) {
	return hm.get(&pm.render_pipelines, handle)
}

@(private = "file")
_pipeline_manager_get_compute_pipeline :: proc(
	pm: ^Pipeline_Manager,
	handle: Pipeline_Handle,
) -> (
	^Compute_Pipeline,
	bool,
) {
	return hm.get(&pm.compute_pipelines, handle)
}

@(private = "file")
_pipeline_manager_hot_reload :: proc() {
	assert(ctx.gfx.pipeline_manager.enable_compilation)

	fence := ctx.gfx.fence
	vk.WaitForFences(ctx.gfx.vk_state.device, 1, &fence, true, max(u64))

	log.debug("--- RELOADING SHADERS ---")
	for &pipeline in ctx.gfx.pipeline_manager.render_pipelines.values {
		_reload_render_pipelines(&pipeline)
	}
}

@(private = "file")
_pipeline_manager_setup_compiler :: proc(pm: ^Pipeline_Manager) {
	pm.compiler = shaderc.compiler_initialize()
	pm.compiler_options = shaderc.compile_options_initialize()
	shaderc.compile_options_set_include_callbacks(
		pm.compiler_options,
		_shader_resolve_include,
		_shader_result_releaser,
		nil,
	)
}

@(private = "file")
_shader_resolve_include :: proc "system" (
	userData: rawptr,
	requestedSource: cstring,
	type: c.int,
	requestingSource: cstring,
	ncludeDepth: c.size_t,
) -> ^shaderc.includeResult {
	context = g_context

	BUILDIN :: "buildin:"
	source: string = strings.clone_from_cstring(requestedSource, allocator = context.temp_allocator)
	path_to_include: strings.Builder
	strings.builder_init_none(&path_to_include, context.temp_allocator)

	if strings.starts_with(source, BUILDIN) {
		strings.write_string(&path_to_include, "./assets/buildin/shaders/")
		strings.write_string(&path_to_include, source[len(BUILDIN):])
	} else {
		strings.write_string(&path_to_include, "./assets/shaders/")
		strings.write_string(&path_to_include, source)
	}

	file := strings.to_string(path_to_include)
	content, ok := read_file(file, context.temp_allocator)
	if !ok {
		log.error("Couldn't read include file", file)
	}

	result := new(shaderc.includeResult)
	result.sourceName = strings.clone_to_cstring(file)
	result.sourceNameLength = len(result.sourceName)
	result.content = strings.clone_to_cstring(cast(string)content)
	result.contentLength = len(result.content)

	return result
}

@(private = "file")
_shader_result_releaser :: proc "system" (userData: rawptr, includeResult: ^shaderc.includeResult) {
	context = g_context
	delete(includeResult.sourceName)
	delete(includeResult.content)
	free(includeResult)
}

create_default_vertex_description :: proc() -> Vertex_Input_Description {
	attribute_descriptions := Vertex_Input_Attribute_Descriptions{}
	sm.push_back_elems(
		&attribute_descriptions,
		Vertex_Input_Attribute_Description {
			location = 0,
			format = .RGB_f32,
			offset = cast(u32)offset_of(Vertex, position),
		},
		Vertex_Input_Attribute_Description {
			location = 1,
			format = .RG_f32,
			offset = cast(u32)offset_of(Vertex, tex_coord),
		},
		Vertex_Input_Attribute_Description {
			location = 2,
			format = .RGB_f32,
			offset = cast(u32)offset_of(Vertex, normal),
		},
		Vertex_Input_Attribute_Description {
			location = 3,
			format = .RGBA_f32,
			offset = cast(u32)offset_of(Vertex, color),
		},
	)

	return Vertex_Input_Description {
		binding = 0,
		stride = size_of(Vertex),
		input_rate = .Vertex,
		attributes = attribute_descriptions,
	}
}

create_render_pipeline :: proc(
	create_pipeline_info: Create_Pipeline_Info,
	loc := #caller_location,
) -> Render_Pipeline_Handle {
	return _pipeline_manager_add_render_pipeline(
		ctx.gfx.pipeline_manager,
		Render_Pipeline{create_info = create_pipeline_info},
	)
}

// Looks up a pipeline in cache using surface settings. If not found, creates a new one.
render_pipeline_get_pipeline :: proc(
	pipeline: ^Render_Pipeline,
	surface_info: Surface_Info,
	loc := #caller_location,
) -> ^Graphics_Pipeline {
	pipeline_surface := _surface_info_to_pipeline_surface_info(surface_info)
	graphics_pipeline, ok := pipeline.cache[pipeline_surface]
	if ok do return &pipeline.cache[pipeline_surface]

	new_pipeline := _create_graphics_pipeline(pipeline.create_info, surface_info, loc)
	pipeline.cache[pipeline_surface] = new_pipeline

	return &pipeline.cache[pipeline_surface]
}

destroy_render_pipeline :: proc(pipeline: ^Render_Pipeline) {
	for key, &pipeline in pipeline.cache {
		_destroy_graphics_pipeline(&pipeline)
	}
	delete(pipeline.cache)
}

@(require_results)
create_compute_pipeline :: proc(
	g: ^Graphics,
	create_pipeline_info: ^Create_Compute_Pipeline_Info,
) -> (
	Pipeline_Handle,
	bool,
) {
	pipeline, ok := _create_compute_pipeline(g, create_pipeline_info, context.allocator)
	if !ok {
		log.errorf("couldn't load pipeline")
		return {}, false
	}

	handle := _pipeline_manager_registe_compute_pipeline(g.pipeline_manager, pipeline)

	return handle, true
}

destroy_compute_pipeline :: proc(pipeline: ^Compute_Pipeline) {
	_destroy_pipline(pipeline)
}

@(private)
_reload_render_pipelines :: proc(pipeline: ^Render_Pipeline) {
	for _, &graphics_pipeline in pipeline.cache {
		_reload_graphics_pipeline(&graphics_pipeline, pipeline.create_info)
	}
}

@(private)
_reload_graphics_pipeline :: proc(pipeline: ^Graphics_Pipeline, create_info: Create_Pipeline_Info) {
	create_info := create_info

	vk.DestroyPipeline(ctx.gfx.vk_state.device, pipeline.pipeline, nil)

	shader_stages := _create_shader_stages(create_info, true)
	defer _destroy_shader_stages(shader_stages)

	pipeline_layout := get_pipeline_layout(pipeline.layout)

	pipeline_rendering_info := vk.PipelineRenderingCreateInfo {
		sType                   = .PIPELINE_RENDERING_CREATE_INFO,
		stencilAttachmentFormat = pipeline.surface_info.depth_format if _has_stencil_component(pipeline.surface_info.depth_format) else .UNDEFINED,
		depthAttachmentFormat   = pipeline.surface_info.depth_format,
		colorAttachmentCount    = cast(u32)pipeline.surface_info.color_formats.len,
		pColorAttachmentFormats = raw_data(sm.slice(&pipeline.surface_info.color_formats)),
	}

	vertex_input_sate: vk.PipelineVertexInputStateCreateInfo
	input_assembly_state: vk.PipelineInputAssemblyStateCreateInfo
	view_port_state: vk.PipelineViewportStateCreateInfo
	rasterization_sate: vk.PipelineRasterizationStateCreateInfo
	multisample_state: vk.PipelineMultisampleStateCreateInfo
	color_blend_state: vk.PipelineColorBlendStateCreateInfo

	dynamic_state: vk.PipelineDynamicStateCreateInfo
	dynamic_states: Pipeline_Dynamic_States
	depth_stencil: vk.PipelineDepthStencilStateCreateInfo

	vertex_input_sate = _init_vertex_input_info(&create_info)
	_init_input_assembly_info(&input_assembly_state, &create_info)
	_init_viewport_info(&view_port_state, &create_info)
	_init_rasterizer(&rasterization_sate, &create_info)
	_init_multisampling_info(&multisample_state, &create_info, pipeline.surface_info.sample_count)
	color_blend_state = _init_color_blend_info(&create_info, pipeline.surface_info)
	_init_dynamic_info(&dynamic_state, &dynamic_states, &create_info)
	_init_depth_stencil_info(&depth_stencil, &create_info)

	pipeline_info := vk.GraphicsPipelineCreateInfo {
		sType               = .GRAPHICS_PIPELINE_CREATE_INFO,
		pNext               = &pipeline_rendering_info,
		stageCount          = cast(u32)shader_stages.len,
		pStages             = raw_data(sm.slice(&shader_stages)),
		pVertexInputState   = &vertex_input_sate,
		pInputAssemblyState = &input_assembly_state,
		pViewportState      = &view_port_state,
		pRasterizationState = &rasterization_sate,
		pMultisampleState   = &multisample_state,
		pColorBlendState    = &color_blend_state,
		pDynamicState       = &dynamic_state,
		pDepthStencilState  = &depth_stencil,
		layout              = pipeline_layout,
		subpass             = 0,
		basePipelineIndex   = -1,
	}

	must(vk.CreateGraphicsPipelines(ctx.gfx.vk_state.device, 0, 1, &pipeline_info, nil, &pipeline.pipeline))
}

@(private)
_create_descriptor_pool :: proc() {
	pool_sizes := [?]vk.DescriptorPoolSize {
		vk.DescriptorPoolSize{type = .UNIFORM_BUFFER, descriptorCount = MAX_DESCRIPTOR_UNIFORM_COUNT},
		vk.DescriptorPoolSize{type = .UNIFORM_BUFFER_DYNAMIC, descriptorCount = MAX_DESCRIPTOR_UNIFORM_DYNAMIC_COUNT},
		vk.DescriptorPoolSize{type = .COMBINED_IMAGE_SAMPLER, descriptorCount = MAX_DESCRIPTOR_IMAGE_SAMPLER_COUNT},
		vk.DescriptorPoolSize{type = .STORAGE_BUFFER, descriptorCount = MAX_DESCRIPTOR_STORAGE_COUNT},
	}

	poolInfo := vk.DescriptorPoolCreateInfo {
		sType         = .DESCRIPTOR_POOL_CREATE_INFO,
		flags         = {.UPDATE_AFTER_BIND},
		poolSizeCount = len(pool_sizes),
		pPoolSizes    = raw_data(&pool_sizes),
		maxSets       = MAX_DESCRIPTOR_SET_COUNT,
	}

	must(
		vk.CreateDescriptorPool(ctx.gfx.vk_state.device, &poolInfo, nil, &ctx.gfx.vk_state.descriptor_pool),
		"failed to create descriptor pool!",
	)
}

@(private)
_destroy_descriptor_pool :: proc() {
	vk.DestroyDescriptorPool(ctx.gfx.vk_state.device, ctx.gfx.vk_state.descriptor_pool, nil)
}

// TODO: need modification
// @(private)
// @(require_results)
// create_descriptor_set :: proc(
// 	pipeline: ^Pipeline,
// 	set: u32,
// 	set_info: Pipeline_Layout_Set_Info,
// 	resources: []Pipeline_Resource,
// ) -> vk.DescriptorSet {
// 	descripotr_set_layout := pipeline.descriptor_set_layouts.data[set]
//
// 	alloc_info := vk.DescriptorSetAllocateInfo {
// 		sType              = .DESCRIPTOR_SET_ALLOCATE_INFO,
// 		descriptorPool     = ctx.gfx.vk_state.descriptor_pool,
// 		descriptorSetCount = 1,
// 		pSetLayouts        = &pipeline.descriptor_set_layouts.data[set],
// 	}
//
// 	descriptor_set: vk.DescriptorSet
// 	must(
// 		vk.AllocateDescriptorSets(ctx.gfx.vk_state.device, &alloc_info, &descriptor_set),
// 		"failed to allocate descriptor sets!",
// 	)
//
// 	assert(set_info.binding_infos.len == len(resources))
//
// 	write_descriptor_sets := make([]vk.WriteDescriptorSet, len(resources), context.temp_allocator)
// 	descriptor_image_info := vk.DescriptorImageInfo{}
// 	descriptor_buffer_info := vk.DescriptorBufferInfo{}
//
// 	for i in 0 ..< set_info.binding_infos.len {
// 		binding := set_info.binding_infos.data[i]
// 		resource := resources[i]
//
// 		switch r in resource {
// 		case Texture:
// 			descriptor_image_info.imageLayout = .SHADER_READ_ONLY_OPTIMAL
// 			descriptor_image_info.imageView = r.view
// 			descriptor_image_info.sampler = r.sampler
//
// 			write_descriptor_sets[i] = vk.WriteDescriptorSet {
// 				sType           = .WRITE_DESCRIPTOR_SET,
// 				dstSet          = descriptor_set,
// 				dstBinding      = binding.binding,
// 				descriptorType  = binding.descriptor_type,
// 				dstArrayElement = 0,
// 				descriptorCount = binding.descriptor_count,
// 				pImageInfo      = &descriptor_image_info,
// 			}
// 		case Buffer:
// 			descriptor_buffer_info.buffer = r.buffer
// 			descriptor_buffer_info.offset = 0
// 			descriptor_buffer_info.range = cast(vk.DeviceSize)vk.WHOLE_SIZE
//
// 			write_descriptor_sets[i] = vk.WriteDescriptorSet {
// 				sType           = .WRITE_DESCRIPTOR_SET,
// 				dstSet          = descriptor_set,
// 				dstBinding      = binding.binding,
// 				descriptorType  = binding.descriptor_type,
// 				dstArrayElement = 0,
// 				descriptorCount = binding.descriptor_count,
// 				pBufferInfo     = &descriptor_buffer_info,
// 			}
// 		}
// 	}
//
// 	vk.UpdateDescriptorSets(
// 		ctx.gfx.vk_state.device,
// 		cast(u32)len(write_descriptor_sets),
// 		raw_data(write_descriptor_sets),
// 		0,
// 		nil,
// 	)
//
// 	return descriptor_set
// }

@(private = "file")
@(require_results)
_create_graphics_pipeline :: proc(
	create_info: Create_Pipeline_Info,
	surface_info: Surface_Info,
	loc := #caller_location,
) -> Graphics_Pipeline {
	assert(surface_info.type != .None, loc = loc)

	create_info := create_info
	surface_info := surface_info
	_assert_create_pipeline_info(&create_info, loc)

	shader_stages := _create_shader_stages(create_info, GFX_DEBUG, loc = loc)
	defer _destroy_shader_stages(shader_stages)

	pipeline_layout_info := Pipeline_Layout_Info {
		layout_infos = create_info.descriptor_set_infos,
	}

	if create_info.bindless {
		pipeline_layout_info.push_constant = Push_Constant_Range {
			offset     = 0,
			size       = size_of(Push_Constant),
			stageFlags = vk.ShaderStageFlags_ALL_GRAPHICS,
		}
		sm.append(&create_info.descriptor_set_infos, get_bindless_pipeline_set_info())
		pipeline_layout_info.layout_infos = create_info.descriptor_set_infos
	}

	pipeline_layout := get_pipeline_layout(pipeline_layout_info)

	pipeline_rendering_info := vk.PipelineRenderingCreateInfo {
		sType                   = .PIPELINE_RENDERING_CREATE_INFO,
		stencilAttachmentFormat = surface_info.depth_format if _has_stencil_component(surface_info.depth_format) else .UNDEFINED,
		depthAttachmentFormat   = surface_info.depth_format,
		colorAttachmentCount    = cast(u32)surface_info.color_formats.len,
		pColorAttachmentFormats = raw_data(sm.slice(&surface_info.color_formats)),
	}

	vertex_input_sate: vk.PipelineVertexInputStateCreateInfo
	input_assembly_state: vk.PipelineInputAssemblyStateCreateInfo
	view_port_state: vk.PipelineViewportStateCreateInfo
	rasterization_sate: vk.PipelineRasterizationStateCreateInfo
	multisample_state: vk.PipelineMultisampleStateCreateInfo
	color_blend_state: vk.PipelineColorBlendStateCreateInfo
	dynamic_state: vk.PipelineDynamicStateCreateInfo
	dynamic_states: Pipeline_Dynamic_States
	depth_stencil: vk.PipelineDepthStencilStateCreateInfo

	vertex_input_sate = _init_vertex_input_info(&create_info, loc = loc)
	_init_input_assembly_info(&input_assembly_state, &create_info)
	_init_viewport_info(&view_port_state, &create_info)
	_init_rasterizer(&rasterization_sate, &create_info)
	_init_multisampling_info(&multisample_state, &create_info, surface_info.sample_count)

	color_blend_state = _init_color_blend_info(&create_info, surface_info)
	_init_dynamic_info(&dynamic_state, &dynamic_states, &create_info)
	_init_depth_stencil_info(&depth_stencil, &create_info)

	pipeline_info := vk.GraphicsPipelineCreateInfo {
		sType               = .GRAPHICS_PIPELINE_CREATE_INFO,
		pNext               = &pipeline_rendering_info,
		stageCount          = cast(u32)shader_stages.len,
		pStages             = raw_data(sm.slice(&shader_stages)),
		pVertexInputState   = &vertex_input_sate,
		pInputAssemblyState = &input_assembly_state,
		pViewportState      = &view_port_state,
		pRasterizationState = &rasterization_sate,
		pMultisampleState   = &multisample_state,
		pColorBlendState    = &color_blend_state,
		pDynamicState       = &dynamic_state,
		pDepthStencilState  = &depth_stencil,
		layout              = pipeline_layout,
		subpass             = 0,
		basePipelineIndex   = -1,
	}

	vk_pipeline := vk.Pipeline{}

	must(vk.CreateGraphicsPipelines(ctx.gfx.vk_state.device, 0, 1, &pipeline_info, nil, &vk_pipeline))

	pipeline := Graphics_Pipeline {
		pipeline     = vk_pipeline,
		layout       = pipeline_layout_info,
		surface_info = surface_info,
	}

	return pipeline
}

@(private)
_destroy_graphics_pipeline :: proc(pipeline: ^Graphics_Pipeline) {
	_destroy_pipline(pipeline)
}

@(private = "file")
@(require_results)
_create_compute_pipeline :: proc(
	g: ^Graphics,
	create_info: ^Create_Compute_Pipeline_Info,
	allocator := context.allocator,
) -> (
	Compute_Pipeline,
	bool,
) {
	create_info := create_info

	module, ok := _create_shader_module(create_info.shader_path)
	if !ok {
		log.error("couldn't find comp shader. ", create_info.shader_path)
		return {}, false
	}

	comp_stage_info := vk.PipelineShaderStageCreateInfo {
		sType  = .PIPELINE_SHADER_STAGE_CREATE_INFO,
		stage  = {.COMPUTE},
		module = module,
		pName  = "main",
	}

	pipelie_layout_info := Pipeline_Layout_Info {
		layout_infos = create_info.set_infos,
		push_constant = Push_Constant_Range {
			offset = 0,
			size = size_of(Push_Constant),
			stageFlags = vk.ShaderStageFlags_ALL_GRAPHICS,
		},
	}

	pipeline_layout := get_pipeline_layout(pipelie_layout_info)


	vk_create_info := vk.ComputePipelineCreateInfo {
		sType  = .COMPUTE_PIPELINE_CREATE_INFO,
		layout = pipeline_layout,
		stage  = comp_stage_info,
	}

	pipeline := vk.Pipeline{}

	vk.CreateComputePipelines(g.vk_state.device, vk.FALSE, 1, &vk_create_info, nil, &pipeline)

	compute_pipeline := Compute_Pipeline {
		pipeline    = pipeline,
		create_info = create_info,
		layout      = pipelie_layout_info,
	}

	return compute_pipeline, true
}

@(private = "file")
_destroy_pipline :: proc(pipeline: ^Pipeline) {
	vk.DestroyPipeline(ctx.gfx.vk_state.device, pipeline.pipeline, nil)
}

// @(private = "file")
// @(require_results)
// _set_infos_to_descriptor_set_layouts :: proc(
// 	set_infos: Pipeline_Set_Infos,
// ) -> (
// 	descriptor_set_layouts: Descriptor_Set_Layouts,
// ) {
// 	for i in 0 ..< set_infos.len {
// 		sm.push(&descriptor_set_layouts, _set_info_to_descriptor_set_layout(set_infos.data[i]))
// 	}
//
// 	return descriptor_set_layouts
// }
//
// @(private = "file")
// @(require_results)
// _set_info_to_descriptor_set_layout :: proc(set_info: Pipeline_Set_Info) -> vk.DescriptorSetLayout {
// 	descriptor_bindings: sm.Small_Array(MAX_PIPELINE_BINDING_COUNT, vk.DescriptorSetLayoutBinding)
// 	flags_array: sm.Small_Array(MAX_PIPELINE_BINDING_COUNT, vk.DescriptorBindingFlags)
//
// 	use_binding_flags := false
//
// 	for i in 0 ..< set_info.binding_infos.len {
// 		binding := set_info.binding_infos.data[i]
// 		sm.push(
// 			&descriptor_bindings,
// 			vk.DescriptorSetLayoutBinding {
// 				binding = binding.binding,
// 				descriptorType = binding.descriptor_type,
// 				descriptorCount = binding.descriptor_count,
// 				stageFlags = binding.stage_flags,
// 				pImmutableSamplers = nil,
// 			},
// 		)
//
// 		flags, has_flags := binding.flags.?
// 		if has_flags {
// 			use_binding_flags = true
// 			sm.push(&flags_array, flags)
// 		} else {
// 			sm.push(&flags_array, vk.DescriptorBindingFlags{})
// 		}
// 	}
//
// 	p_binding_flags: ^vk.DescriptorSetLayoutBindingFlagsCreateInfo = nil
//
// 	if use_binding_flags {
// 		binding_flags := vk.DescriptorSetLayoutBindingFlagsCreateInfo {
// 			sType         = .DESCRIPTOR_SET_LAYOUT_BINDING_FLAGS_CREATE_INFO,
// 			pNext         = nil,
// 			pBindingFlags = raw_data(sm.slice(&flags_array)),
// 			bindingCount  = cast(u32)flags_array.len,
// 		}
// 		p_binding_flags = &binding_flags
// 	}
//
// 	descriptor_set_layout := vk.DescriptorSetLayout{}
//
// 	layout_info := vk.DescriptorSetLayoutCreateInfo {
// 		sType        = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
// 		pNext        = p_binding_flags,
// 		bindingCount = cast(u32)descriptor_bindings.len,
// 		pBindings    = raw_data(sm.slice(&descriptor_bindings)),
// 		flags        = {.UPDATE_AFTER_BIND_POOL},
// 	}
//
// 	must(
// 		vk.CreateDescriptorSetLayout(ctx.gfx.vk_state.device, &layout_info, nil, &descriptor_set_layout),
// 		"failed to create descriptor set layout!",
// 	)
//
// 	return descriptor_set_layout
// }

// @(private = "file")
// _destroy_descriptor_set_layout :: proc(descriptor_set_layout: vk.DescriptorSetLayout) {
// 	vk.DestroyDescriptorSetLayout(ctx.gfx.vk_state.device, descriptor_set_layout, nil)
// }

@(private = "file")
@(require_results)
_create_shader_module :: proc {
	_create_shader_module_from_file,
	_create_shader_module_from_memory,
}

@(private = "file")
@(require_results)
_create_shader_module_from_file :: proc(
	path: string,
	compile: bool = false,
	loc := #caller_location,
) -> (
	module: vk.ShaderModule,
	ok: bool,
) {
	source_path := strings.trim_right(path, ".spv")

	if compile {
		when GFX_DEBUG {
			data, w_ok := _shader_compile_and_write(ctx.gfx.pipeline_manager, source_path, loc)
			if !w_ok {
				log.panic("Couldn't write compiled shader ", path)
			}

			return _create_shader_module_from_memory(data), w_ok
		} else {
			log.panic("couldn't compile shader on release mode")
		}
	}
	data, success := read_file(path, context.temp_allocator)

	if !success {
		when GFX_DEBUG {
			data = _shader_compile(ctx.gfx.pipeline_manager, source_path, loc)
			success := wirte_file(path, data)
			if !success {
				log.panic("Couldn't write compiled shader ", path)
			}
		} else {
			log.error("coulnd't load shader module: ", path)
		}
	}

	return _create_shader_module_from_memory(data), success
}

@(private = "file")
@(require_results)
_create_shader_module_from_memory :: proc(code: []byte) -> (module: vk.ShaderModule) {
	as_u32 := slice.reinterpret([]u32, code)

	create_info := vk.ShaderModuleCreateInfo {
		sType    = .SHADER_MODULE_CREATE_INFO,
		codeSize = len(code),
		pCode    = raw_data(as_u32),
	}
	must(vk.CreateShaderModule(ctx.gfx.vk_state.device, &create_info, nil, &module))

	return
}

@(private = "file")
@(require_results)
_create_shader_stages :: proc(
	create_info: Create_Pipeline_Info,
	compile := false,
	loc := #caller_location,
) -> (
	shader_stages: Pipeline_Shader_Stage_Create_Infos,
) {
	for i in 0 ..< create_info.stage_infos.len {
		stage_info := create_info.stage_infos.data[i]

		path := strings.concatenate({stage_info.shader_path, ".spv"}, context.temp_allocator)
		shader_module, c_ok := _create_shader_module(path, compile, loc)

		if !c_ok {
			log.panicf("couldn't create shader module for stage %v. Path: %s", stage_info.stage, stage_info.shader_path)
		}

		spec: ^vk.SpecializationInfo = nil
		if sm.len(stage_info.consts) > 0 {
			map_entry := make([]vk.SpecializationMapEntry, sm.len(stage_info.consts), context.temp_allocator)
			const_data := make([]Shader_Constant_Value, sm.len(stage_info.consts), context.temp_allocator)
			offset: u32
			for const, i in sm.slice(&stage_info.consts) {
				map_entry[i] = vk.SpecializationMapEntry {
					constantID = const.id,
					offset     = offset,
					size       = size_of(Shader_Constant_Value),
				}
				const_data[i] = const.value
				offset += size_of(Shader_Constant_Value)
			}

			spec = new(vk.SpecializationInfo, context.temp_allocator)
			spec.pData = raw_data(const_data)
			spec.dataSize = cast(int)offset
			spec.pMapEntries = raw_data(map_entry)
			spec.mapEntryCount = cast(u32)len(map_entry)
		}

		sm.push(
			&shader_stages,
			vk.PipelineShaderStageCreateInfo {
				sType = .PIPELINE_SHADER_STAGE_CREATE_INFO,
				stage = _to_vulkan_stages({stage_info.stage}),
				module = shader_module,
				pName = "main",
				pSpecializationInfo = spec,
			},
		)
	}

	return
}

@(private = "file")
_destroy_shader_stages :: proc(shader_stages: Pipeline_Shader_Stage_Create_Infos) {
	for i in 0 ..< shader_stages.len {
		vk.DestroyShaderModule(ctx.gfx.vk_state.device, shader_stages.data[i].module, nil)
	}
}

@(private = "file")
_init_dynamic_info :: proc(
	info: ^vk.PipelineDynamicStateCreateInfo,
	dynamic_states: ^Pipeline_Dynamic_States,
	create_info: ^Create_Pipeline_Info,
) {
	sm.append_elems(dynamic_states, vk.DynamicState.VIEWPORT, vk.DynamicState.SCISSOR)

	info.sType = .PIPELINE_DYNAMIC_STATE_CREATE_INFO
	info.dynamicStateCount = cast(u32)sm.len(dynamic_states^)
	info.pDynamicStates = raw_data(sm.slice(dynamic_states))
}

@(private = "file")
_init_vertex_input_info :: proc(
	create_info: ^Create_Pipeline_Info,
	allocator := context.temp_allocator,
	loc := #caller_location,
) -> vk.PipelineVertexInputStateCreateInfo {
	a := create_info.vertex_input_descriptions
	desc_len := cast(u32)sm.len(create_info.vertex_input_descriptions)

	binding_desc := make([]vk.VertexInputBindingDescription, desc_len, allocator)
	for desc, i in sm.slice(&create_info.vertex_input_descriptions) {
		binding_desc[i] = vk.VertexInputBindingDescription {
			binding   = desc.binding,
			stride    = desc.stride,
			inputRate = .VERTEX if desc.input_rate == .Vertex else .INSTANCE,
		}
	}

	attribute_desc := make(
		[dynamic]vk.VertexInputAttributeDescription,
		0,
		MAX_PIPELINE_VERTEX_INPUT_ATTRIBUTE_COUNT,
		allocator,
	)
	for &desc in sm.slice(&create_info.vertex_input_descriptions) {
		for attr in sm.slice(&desc.attributes) {
			append(
				&attribute_desc,
				vk.VertexInputAttributeDescription {
					binding = desc.binding,
					location = attr.location,
					format = _format_to_vk(attr.format),
					offset = attr.offset,
				},
			)
		}
	}

	assert(
		len(attribute_desc) <= MAX_PIPELINE_VERTEX_INPUT_ATTRIBUTE_COUNT,
		fmt.tprintf(
			"Vertex attributes exceeded: %d used (max %d).",
			len(attribute_desc),
			MAX_PIPELINE_VERTEX_INPUT_ATTRIBUTE_COUNT,
		),
		loc,
	)

	return vk.PipelineVertexInputStateCreateInfo {
		sType = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
		vertexBindingDescriptionCount = cast(u32)len(binding_desc),
		pVertexBindingDescriptions = raw_data(binding_desc),
		vertexAttributeDescriptionCount = cast(u32)len(attribute_desc),
		pVertexAttributeDescriptions = raw_data(attribute_desc),
	}
}

@(private = "file")
_init_input_assembly_info :: proc(info: ^vk.PipelineInputAssemblyStateCreateInfo, create_info: ^Create_Pipeline_Info) {
	info.sType = .PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO
	info.topology = cast(vk.PrimitiveTopology)create_info.topology
}

@(private = "file")
_init_viewport_info :: proc(info: ^vk.PipelineViewportStateCreateInfo, create_info: ^Create_Pipeline_Info) {
	info.sType = .PIPELINE_VIEWPORT_STATE_CREATE_INFO
	info.viewportCount = 1
	info.scissorCount = 1
}

@(private = "file")
_init_rasterizer :: proc(info: ^vk.PipelineRasterizationStateCreateInfo, create_info: ^Create_Pipeline_Info) {
	info.sType = .PIPELINE_RASTERIZATION_STATE_CREATE_INFO

	info.depthBiasEnable = create_info.depth.bias.enable
	info.depthBiasClamp = create_info.depth.bias.clamp
	info.depthBiasConstantFactor = create_info.depth.bias.constant_factor
	info.depthBiasSlopeFactor = create_info.depth.bias.slope_factor

	info.polygonMode = cast(vk.PolygonMode)create_info.rasterizer.polygon_mode
	info.lineWidth = create_info.rasterizer.line_width
	info.cullMode = transmute(vk.CullModeFlags)create_info.rasterizer.cull_mode
	info.frontFace = cast(vk.FrontFace)create_info.rasterizer.front_face
}

@(private = "file")
_init_multisampling_info :: proc(
	info: ^vk.PipelineMultisampleStateCreateInfo,
	create_info: ^Create_Pipeline_Info,
	sampel_count: vk.SampleCountFlag,
) {
	info.sType = .PIPELINE_MULTISAMPLE_STATE_CREATE_INFO
	info.rasterizationSamples = {sampel_count}
	info.minSampleShading = 1
}

@(private = "file")
_init_color_blend_info :: proc(
	create_info: ^Create_Pipeline_Info,
	surface_info: Surface_Info,
	allocator := context.temp_allocator,
) -> vk.PipelineColorBlendStateCreateInfo {
	attachment_count := sm.len(surface_info.color_formats)
	attachment_states := make([]vk.PipelineColorBlendAttachmentState, attachment_count, allocator)

	attachment_infos := create_info.blending_info.attachment_infos
	for i in 0 ..< attachment_count {
		if sm.len(attachment_infos) <= i {
			attachment_states[i] = vk.PipelineColorBlendAttachmentState {
				blendEnable    = false,
				colorWriteMask = {.R, .G, .B, .A},
			}
			continue
		}

		attachment_states[i] = vk.PipelineColorBlendAttachmentState {
			blendEnable         = true,
			srcColorBlendFactor = cast(vk.BlendFactor)sm.get(attachment_infos, i).src_color_blend_factor,
			dstColorBlendFactor = cast(vk.BlendFactor)sm.get(attachment_infos, i).dst_color_blend_factor,
			colorBlendOp        = cast(vk.BlendOp)sm.get(attachment_infos, i).color_blend_op,
			srcAlphaBlendFactor = cast(vk.BlendFactor)sm.get(attachment_infos, i).src_alpha_blend_factor,
			dstAlphaBlendFactor = cast(vk.BlendFactor)sm.get(attachment_infos, i).dst_alpha_blend_factor,
			alphaBlendOp        = cast(vk.BlendOp)sm.get(attachment_infos, i).alpha_blend_op,
			colorWriteMask      = sm.get(attachment_infos, i).color_write_mask,
		}
	}

	return vk.PipelineColorBlendStateCreateInfo {
		sType = .PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
		attachmentCount = cast(u32)attachment_count,
		pAttachments = raw_data(attachment_states),
	}
}

@(private = "file")
_init_depth_stencil_info :: proc(info: ^vk.PipelineDepthStencilStateCreateInfo, create_info: ^Create_Pipeline_Info) {
	info.sType = .PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO
	info.depthTestEnable = create_info.depth.enable
	info.depthWriteEnable = create_info.depth.write_enable
	info.depthCompareOp = cast(vk.CompareOp)create_info.depth.compare_op
	info.depthBoundsTestEnable = create_info.depth.bounds_test_enable
	info.minDepthBounds = create_info.depth.min_bounds
	info.maxDepthBounds = create_info.depth.max_bounds
	info.stencilTestEnable = create_info.stencil.enable
	info.front = transmute(vk.StencilOpState)create_info.stencil.front
	info.back = transmute(vk.StencilOpState)create_info.stencil.back
}

@(private = "file")
@(require_results)
_shader_compile_and_write :: proc(pm: ^Pipeline_Manager, path: string, loc := #caller_location) -> ([]byte, bool) {
	data := _shader_compile(pm, path, loc)
	result_path := strings.concatenate({path, ".spv"}, context.temp_allocator)

	return data, wirte_file(result_path, data)
}

@(private = "file")
_shader_compile :: proc(pm: ^Pipeline_Manager, path: string, loc := #caller_location) -> []u8 {
	kind: shaderc.shaderKind
	file_ext := strings.split(path, ".", context.temp_allocator)[1]

	switch file_ext {
	case "frag":
		kind = .FragmentShader
	case "vert":
		kind = .VertexShader
	case "comp":
		kind = .ComputeShader
	}

	data, ok := read_file(path, context.temp_allocator)
	if !ok {
		log.panic("Failed to load file:", path, location = loc)
	}

	source := strings.clone_to_cstring(cast(string)data, context.temp_allocator)

	strs := strings.split(path, "/", context.temp_allocator)
	file_name := strs[len(strs) - 1]
	b := strings.builder_make(context.temp_allocator)
	strings.write_string(&b, file_name)
	input_file_name := strings.to_cstring(&b)

	result := shaderc.compile_into_spv(
		pm.compiler,
		source,
		len(source),
		kind,
		input_file_name,
		"main",
		pm.compiler_options,
	)

	if (shaderc.result_get_compilation_status(result) != shaderc.compilationStatus.Success) {
		log.error("Failed to compile ", path, "shader")
		log.panic(string(shaderc.result_get_error_message(result)))
	} else {
		log.debug("Success compile shader", path)
	}

	result_len := shaderc.result_get_length(result)
	bytes := shaderc.result_get_bytes(result)
	shaderCode := transmute([]u8)bytes[:result_len]

	return shaderCode
}


@(private = "file")
_to_vulkan_stages :: proc(flags: Shader_Stage_Flags) -> vk.ShaderStageFlags {
	result: vk.ShaderStageFlags = {}

	if .Vertex in flags do result |= {.VERTEX}
	if .Geometry in flags do result |= {.GEOMETRY}
	if .Fragment in flags do result |= {.FRAGMENT}
	if .Compute in flags do result |= {.COMPUTE}

	return result
}

_surface_info_to_pipeline_surface_info :: proc(surface: Surface_Info) -> Pipeline_Surface_Info {
	color_formats := sm.Small_Array(MAX_COLOR_ATTACHMENTS, vk.Format){}
	return Pipeline_Surface_Info {
		sample_count = surface.sample_count,
		depth_format = surface.depth_format,
		color_formats = surface.color_formats,
	}
}

@(private = "file")
_assert_create_pipeline_info :: #force_inline proc(create_info: ^Create_Pipeline_Info, loc := #caller_location) {
	when GFX_DEBUG {
		// Validate pipeline stage unique
		for i_s, i in sm.slice(&create_info.stage_infos) {
			for j_s, j in sm.slice(&create_info.stage_infos) {
				if i == j do continue
				assert(
					i_s.stage != j_s.stage,
					fmt.tprintf("Stage %v is duplicated. Stage must be unique across the pipeline.", i_s.stage),
					loc,
				)
			}
		}

		// Validate vertex input binding unique
		for i_d, i in sm.slice(&create_info.vertex_input_descriptions) {
			for j_d, j in sm.slice(&create_info.vertex_input_descriptions) {
				if i == j do continue
				assert(i_d.binding != j_d.binding, "Vertex input bindings should be unique.", loc)
			}
		}

		// Validate vertex input location unique
		attribute_desc := make([dynamic]u32, 0, MAX_PIPELINE_VERTEX_INPUT_ATTRIBUTE_COUNT, context.temp_allocator)
		for &d, i in sm.slice(&create_info.vertex_input_descriptions) {
			for a in sm.slice(&d.attributes) {
				assert(
					!slice.contains(attribute_desc[:], a.location),
					fmt.tprintf(
						"Vertex attribute location (%d) is duplicated. Location must be unique across the pipeline.",
						a.location,
					),
					loc,
				)
				append(&attribute_desc, a.location)
			}
		}
	}
}
