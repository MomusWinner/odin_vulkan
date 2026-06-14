#+private
package ve

import hm "container/handle_map"
import sm "core:container/small_array"
import "core:log"
import vk "vendor:vulkan"

@(private = "file")
UNIFORM_BINDING :: 0
@(private = "file")
STORAGE_BINDING :: 1
@(private = "file")
TEXTURE_BINDING :: 2

BINDLESS_STAGE_FLAGS :: vk.ShaderStageFlags_ALL_GRAPHICS + {.COMPUTE}

@(require_results)
_store_texture :: proc(texture: Texture_Data, loc := #caller_location) -> Texture {
	return _bindless_store_texture(ctx.gfx.bindless, texture, loc)
}

_replace_texture_h :: proc(texture_h: Texture, new_texture: Texture_Data, loc := #caller_location) {
	_bindless_replace_texture(ctx.gfx.bindless, texture_h, new_texture, loc)
}

_update_texture_h :: proc(texture: Texture, loc := #caller_location) {
	_bindless_update_texture(ctx.gfx.bindless, texture, loc)
}

@(require_results)
_get_texture_h :: proc(texture_h: Texture, loc := #caller_location) -> ^Texture_Data {
	t, ok := hm.get(&ctx.gfx.bindless.textures, texture_h)
	assert_texture(ok, loc)
	return t
}

@(require_results)
_has_texture_h :: proc(texture_h: Texture) -> bool {
	return hm.has_handle(&ctx.gfx.bindless.textures, texture_h)
}

@(require_results)
_acquire_texture_h :: proc(texture_h: Texture) -> Texture_Data {
	return _bindless_remove_texture(ctx.gfx.bindless, texture_h)
}

@(require_results)
_store_buffer :: proc(buffer: Buffer_Data, loc := #caller_location) -> Buffer {
	return _bindless_store_buffer(ctx.gfx.bindless, buffer, loc)
}

@(require_results)
_acquire_buffer_h :: proc(buffer_h: Buffer, loc := #caller_location) -> Buffer_Data {
	return _bindless_remove_buffer(ctx.gfx.bindless, buffer_h, loc)
}

@(require_results)
_get_buffer_h :: proc(buffer_h: Buffer, loc := #caller_location) -> ^Buffer_Data {
	result, ok := hm.get(&ctx.gfx.bindless.buffers, buffer_h)
	assert_buffer(ok, loc)
	return result
}

@(require_results)
_has_buffer_h :: proc(buffer_h: Buffer) -> bool {
	return hm.has_handle(&ctx.gfx.bindless.buffers, buffer_h)
}

@(require_results)
_get_bindless_pipeline_set_info :: proc() -> Pipeline_Set_Layout_Info {
	binding_infos := Pipeline_Set_Binding_Infos{}
	sm.push(
		&binding_infos,
		Pipeline_Set_Binding_Info {
			binding = UNIFORM_BINDING,
			descriptor_type = .UNIFORM_BUFFER,
			descriptor_count = MAX_DESCRIPTOR_BINDLESS_COUNT,
			stage_flags = BINDLESS_STAGE_FLAGS,
			flags = vk.DescriptorBindingFlags{.UPDATE_AFTER_BIND, .PARTIALLY_BOUND},
		},
		Pipeline_Set_Binding_Info {
			binding = STORAGE_BINDING,
			descriptor_type = .STORAGE_BUFFER,
			descriptor_count = MAX_DESCRIPTOR_BINDLESS_COUNT,
			stage_flags = BINDLESS_STAGE_FLAGS,
			flags = vk.DescriptorBindingFlags{.UPDATE_AFTER_BIND, .PARTIALLY_BOUND},
		},
		Pipeline_Set_Binding_Info {
			binding = TEXTURE_BINDING,
			descriptor_type = .COMBINED_IMAGE_SAMPLER,
			descriptor_count = MAX_DESCRIPTOR_BINDLESS_COUNT,
			stage_flags = BINDLESS_STAGE_FLAGS,
			flags = vk.DescriptorBindingFlags{.UPDATE_AFTER_BIND, .PARTIALLY_BOUND},
		},
	)

	return Pipeline_Set_Layout_Info{binding_infos = binding_infos}
}

@(require_results)
_get_descriptor_set_bindless :: proc() -> Descriptor_Set {
	return ctx.gfx.bindless.set
}

_init_bindless :: proc(loc := #caller_location) {
	assert(ctx.gfx.bindless == nil, "Bindless already initialized", loc)

	ctx.gfx.bindless = new(Bindless)
	_bindless_init(ctx.gfx.bindless)
}

_destroy_bindless :: proc(loc := #caller_location) {
	assert(ctx.gfx.bindless != nil, "Bindless already uninitialized", loc)

	_bindless_destroy(ctx.gfx.bindless)
	free(ctx.gfx.bindless)
}

@(private = "file")
_bindless_init :: proc(bindless: ^Bindless, loc := #caller_location) {
	assert_not_nil(bindless, loc)

	descriptor_types := [3]vk.DescriptorType{.UNIFORM_BUFFER, .STORAGE_BUFFER, .COMBINED_IMAGE_SAMPLER}
	descriptor_bindings: [3]vk.DescriptorSetLayoutBinding
	descriptor_binding_flags: [3]vk.DescriptorBindingFlags

	for i in 0 ..< 3 {
		descriptor_bindings[i].binding = cast(u32)i
		descriptor_bindings[i].descriptorType = descriptor_types[i]
		descriptor_bindings[i].descriptorCount = MAX_DESCRIPTOR_BINDLESS_COUNT
		descriptor_bindings[i].stageFlags = BINDLESS_STAGE_FLAGS
		descriptor_binding_flags[i] = {.PARTIALLY_BOUND, .UPDATE_AFTER_BIND}
	}

	binding_flags := vk.DescriptorSetLayoutBindingFlagsCreateInfo {
		sType         = .DESCRIPTOR_SET_LAYOUT_BINDING_FLAGS_CREATE_INFO,
		pNext         = nil,
		pBindingFlags = raw_data(&descriptor_binding_flags),
		bindingCount  = 3,
	}

	create_info := vk.DescriptorSetLayoutCreateInfo {
		sType        = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
		bindingCount = 3,
		pBindings    = raw_data(&descriptor_bindings),
		flags        = {.UPDATE_AFTER_BIND_POOL},
		pNext        = &binding_flags,
	}

	must(vk.CreateDescriptorSetLayout(ctx.gfx.vk_state.device, &create_info, nil, &bindless.set_layout))

	allocate_info := vk.DescriptorSetAllocateInfo {
		sType              = .DESCRIPTOR_SET_ALLOCATE_INFO,
		pNext              = nil,
		descriptorPool     = ctx.gfx.vk_state.descriptor_pool,
		pSetLayouts        = &bindless.set_layout,
		descriptorSetCount = 1,
	}

	must(vk.AllocateDescriptorSets(ctx.gfx.vk_state.device, &allocate_info, &bindless.set))
}

@(private = "file")
_bindless_destroy :: proc(bindless: ^Bindless, loc := #caller_location) {
	assert_not_nil(bindless, loc)

	vk.DestroyDescriptorSetLayout(ctx.gfx.vk_state.device, bindless.set_layout, nil)

	for &texture in bindless.textures.values {
		_destroy_texture(&texture)
	}
	hm.destroy(&bindless.textures)

	for &buffer in bindless.buffers.values {
		_destroy_buffer(&buffer)
	}
	hm.destroy(&bindless.buffers)
}

@(private = "file")
_bindless_bind :: proc(
	bindless: ^Bindless,
	cmd: vk.CommandBuffer,
	pipeline_layout: vk.PipelineLayout,
	loc := #caller_location,
) {
	assert_not_nil(bindless, loc)

	vk.CmdBindDescriptorSets(cmd, .GRAPHICS, pipeline_layout, 0, 1, &bindless.set, 0, nil)
}

@(private = "file")
@(require_results)
_bindless_store_texture :: proc(bindless: ^Bindless, texture: Texture_Data, loc := #caller_location) -> Texture {
	assert_not_nil(bindless, loc)

	handle := hm.insert(&bindless.textures, texture)

	image_info := vk.DescriptorImageInfo {
		imageLayout = .SHADER_READ_ONLY_OPTIMAL,
		imageView   = texture.view,
		sampler     = texture.sampler,
	}

	write := vk.WriteDescriptorSet {
		sType           = .WRITE_DESCRIPTOR_SET,
		descriptorType  = .COMBINED_IMAGE_SAMPLER,
		dstBinding      = TEXTURE_BINDING,
		dstSet          = bindless.set,
		descriptorCount = 1,
		dstArrayElement = handle.index,
		pImageInfo      = &image_info,
	}
	vk.UpdateDescriptorSets(ctx.gfx.vk_state.device, 1, &write, 0, nil)

	return handle
}

@(private = "file")
_bindless_update_texture :: proc(bindless: ^Bindless, texture: Texture, loc := #caller_location) {
	assert_not_nil(bindless, loc)

	data := _get_texture_h(texture)

	image_info := vk.DescriptorImageInfo {
		imageLayout = .SHADER_READ_ONLY_OPTIMAL,
		imageView   = data.view,
		sampler     = data.sampler,
	}

	write := vk.WriteDescriptorSet {
		sType           = .WRITE_DESCRIPTOR_SET,
		descriptorType  = .COMBINED_IMAGE_SAMPLER,
		dstBinding      = TEXTURE_BINDING,
		dstSet          = bindless.set,
		descriptorCount = 1,
		dstArrayElement = texture.index,
		pImageInfo      = &image_info,
	}
	vk.UpdateDescriptorSets(ctx.gfx.vk_state.device, 1, &write, 0, nil)
}

@(private = "file")
_bindless_replace_texture :: proc(
	bindless: ^Bindless,
	texture_h: Texture,
	new_texture: Texture_Data,
	loc := #caller_location,
) {
	assert_not_nil(bindless, loc)

	texture, ok := hm.get(&bindless.textures, texture_h)
	_destroy_texture(texture)
	assert(ok, loc = loc)
	texture^ = new_texture

	image_info := vk.DescriptorImageInfo {
		imageLayout = .SHADER_READ_ONLY_OPTIMAL,
		imageView   = new_texture.view,
		sampler     = new_texture.sampler,
	}

	write := vk.WriteDescriptorSet {
		sType           = .WRITE_DESCRIPTOR_SET,
		descriptorType  = .COMBINED_IMAGE_SAMPLER,
		dstBinding      = TEXTURE_BINDING,
		dstSet          = bindless.set,
		descriptorCount = 1,
		dstArrayElement = texture_h.index,
		pImageInfo      = &image_info,
	}
	vk.UpdateDescriptorSets(ctx.gfx.vk_state.device, 1, &write, 0, nil)
}

@(private = "file")
_bindless_remove_texture :: proc(bindless: ^Bindless, texture_h: Texture, loc := #caller_location) -> Texture_Data {
	assert_not_nil(bindless, loc)
	t, ok := hm.remove(&bindless.textures, texture_h)
	assert_texture(ok, loc)
	return t
}

@(private = "file")
_bindless_store_buffer :: proc(bindless: ^Bindless, buffer: Buffer_Data, loc := #caller_location) -> Buffer {
	assert_not_nil(bindless, loc)

	handle := hm.insert(&bindless.buffers, buffer)

	writes: [2]vk.WriteDescriptorSet

	for &write in writes {
		buffer_info := vk.DescriptorBufferInfo {
			buffer = buffer.id,
			offset = 0,
			range  = cast(vk.DeviceSize)vk.WHOLE_SIZE,
		}

		write.sType = .WRITE_DESCRIPTOR_SET
		write.dstSet = bindless.set
		write.descriptorCount = 1
		write.dstArrayElement = handle.index
		write.pBufferInfo = &buffer_info
	}

	i: u32 = 0
	if vk.BufferUsageFlag.UNIFORM_BUFFER in buffer.vk_usage {
		writes[i].dstBinding = UNIFORM_BINDING
		writes[i].descriptorType = .UNIFORM_BUFFER
		i += 1
	}

	if vk.BufferUsageFlag.STORAGE_BUFFER in buffer.vk_usage {writes[i].dstBinding = STORAGE_BINDING
		writes[i].descriptorType = .STORAGE_BUFFER
		i += 1
	}

	vk.UpdateDescriptorSets(ctx.gfx.vk_state.device, i, raw_data(&writes), 0, nil)

	return handle
}

@(private = "file")
_bindless_remove_buffer :: proc(bindless: ^Bindless, buffer_h: Buffer, loc := #caller_location) -> Buffer_Data {
	assert_not_nil(bindless, loc)
	b, ok := hm.remove(&bindless.buffers, buffer_h)
	assert_buffer(ok, loc)
	return b
}

@(private = "file")
assert_texture :: #force_inline proc(ok: bool, loc := #caller_location) {
	assert(ok, "Invalid texture handle", loc = loc)
}

@(private = "file")
assert_buffer :: #force_inline proc(ok: bool, loc := #caller_location) {
	assert(ok, "Invalid buffer handle", loc = loc)
}
