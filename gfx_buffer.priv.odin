#+private
package ve

import hm "container/handle_map"
import "core:fmt"
import "core:log"
import "core:mem"
import "lib/vma"
import vk "vendor:vulkan"

Buffer_Data :: struct {
	id:         vk.Buffer,
	vk_usage:   vk.BufferUsageFlags,
	usage:      Buffer_Usage_Flags,
	mapped:     rawptr,
	size:       Device_Size,
	alloc:      vma.Allocation,
	alloc_info: vma.AllocationInfo,
}

Buffer_Manager :: struct {
	uniform_buffers: hm.Handle_Map(Uniform_Buffer_Data, Uniform_Buffer),
	storage_buffers: hm.Handle_Map(Storage_Buffer_Data, Storage_Buffer),
}

@(require_results)
_create_buffer :: proc(
	usage: Buffer_Usage_Flags,
	size: Device_Size,
	data: rawptr = nil,
	loc := #caller_location,
) -> Buffer_Data {
	when ODIN_DEBUG {
		assert(size > 0, loc = loc)
		required_flags := [?]Buffer_Usage_Flag{.Vertex, .Index, .Uniform, .Storage, .Transfer}
		has_gpu_usage := false
		for flag in required_flags {
			if flag in usage {
				has_gpu_usage = true
				break
			}
		}
		assert(
			has_gpu_usage == true,
			fmt.tprintf("Buffer should have some of these usage flags %v", required_flags),
			loc,
		)
	}

	vk_usage, dst_access_mask, dst_stage_mask := _buffer_get_usage_and_dst_access_stage_mask(usage)

	memory_usage: vma.MemoryUsage
	memory_flags: vma.AllocationCreateFlags

	if .Host_Write in usage {
		memory_usage = .CPU_ONLY
		memory_usage = .AUTO_PREFER_HOST
		memory_flags += {.MAPPED, .HOST_ACCESS_SEQUENTIAL_WRITE}
	}
	if .Host_Read in usage {
		memory_usage = .CPU_ONLY
		memory_usage = .AUTO_PREFER_HOST
		memory_flags -= {.MAPPED, .HOST_ACCESS_SEQUENTIAL_WRITE}
		memory_flags += {.HOST_ACCESS_RANDOM}
	}

	vk_buffer: vk.Buffer
	alloc: vma.Allocation
	alloc_info: vma.AllocationInfo
	mapped: rawptr

	if (.Host_Write in usage || .Host_Read in usage) {
		vk_buffer, alloc, alloc_info = _create_vk_buffer(size, vk_usage, memory_usage, memory_flags, {}, {})
		_vk_map_memory(alloc, &mapped, loc)
		if data != nil {
			_buffer_fill_mapped_memory(alloc, alloc_info, data, size, mapped)
		}
	} else {
		if data != nil {
			vk_buffer, alloc, alloc_info = _create_vk_device_local_buffer(
				data,
				size,
				vk_usage,
				dst_access_mask,
				dst_stage_mask,
				loc,
			)
		} else {
			vk_usage += {.TRANSFER_DST}
			memory_usage = .AUTO_PREFER_DEVICE
			vk_buffer, alloc, alloc_info = _create_vk_buffer(size, vk_usage, memory_usage, {})
		}
	}

	_vk_set_debug_object_name(
		vk_buffer,
		.BUFFER,
		fmt.tprintf("%v %s", usage, _location_to_string(loc, context.temp_allocator)),
	)

	return Buffer_Data {
		id = vk_buffer,
		size = size,
		usage = usage,
		vk_usage = vk_usage,
		alloc = alloc,
		alloc_info = alloc_info,
	}
}

_destroy_buffer :: proc(buffer: ^Buffer_Data, loc := #caller_location) {
	assert_not_nil(buffer, loc)

	if (buffer.mapped != nil) {
		vma.UnmapMemory(ctx.gfx.vk_state.allocator, buffer.alloc)
		buffer.mapped = nil
	}
	vma.DestroyBuffer(ctx.gfx.vk_state.allocator, buffer.id, buffer.alloc)
}

_buffer_fill :: proc(
	b: ^Buffer_Data,
	data: rawptr,
	size: Device_Size,
	offset: Device_Size = 0,
	loc := #caller_location,
) {
	assert(b != nil, loc = loc)
	assert(data != nil, loc = loc)
	assert(size > 0, loc = loc)
	mem_props := _get_memory_properties(b.alloc_info)

	if .HOST_VISIBLE in mem_props {
		if b.mapped == nil do _vk_map_memory(b.alloc, &b.mapped)
		_buffer_fill_mapped_memory(b.alloc, b.alloc_info, data, size, b.mapped)
	} else if .TRANSFER_DST in b.vk_usage {
		sc := begin_single_cmd()
		staging_buffer := _create_staging_buffer(data, size)
		defer _destroy_buffer(&staging_buffer, loc)
		_, dst_access_mask, dst_stage_mask := _buffer_get_usage_and_dst_access_stage_mask(b.usage)

		_cmd_buffer_barrier(sc.cmd, staging_buffer.id, {.HOST_WRITE}, {.TRANSFER_READ}, {.HOST}, {.TRANSFER})
		_cmd_copy_buffer(sc.cmd, staging_buffer.id, b.id, size)
		_cmd_buffer_barrier(sc.cmd, b.id, {.TRANSFER_WRITE}, dst_access_mask, {.TRANSFER}, dst_stage_mask)
		end_single_cmd(sc)
	} else {
		log.info(b.vk_usage)
		log.panic("Couldn't fill buffer", loc)
	}
}

_buffer_read :: proc(b: ^Buffer_Data, loc := #caller_location) -> (data: rawptr, size: Device_Size) {
	mem_props := _get_memory_properties(b.alloc_info)
	assert(.HOST_VISIBLE in mem_props, loc = loc)
	if b.mapped == nil {
		_vk_map_memory(b.alloc, &b.mapped, loc)
	}
	if !(.HOST_COHERENT in mem_props) {
		vma.InvalidateAllocation(ctx.gfx.vk_state.allocator, b.alloc, 0, cast(vk.DeviceSize)vk.WHOLE_SIZE)
	}
	return b.mapped, b.size
}

_buffer_get_usage_and_dst_access_stage_mask :: proc(
	usage: Buffer_Usage_Flags,
) -> (
	vk_usage: vk.BufferUsageFlags,
	dst_access_mask: vk.AccessFlags2,
	dst_stage_mask: vk.PipelineStageFlags2,
) {
	if .Vertex in usage {
		vk_usage += {.VERTEX_BUFFER}
		dst_access_mask += {.VERTEX_ATTRIBUTE_READ}
		dst_stage_mask += {.VERTEX_ATTRIBUTE_INPUT}
	}
	if .Index in usage {
		vk_usage += {.INDEX_BUFFER}
		dst_access_mask += {.INDEX_READ}
		dst_stage_mask += {.INDEX_INPUT}
	}
	if .Uniform in usage {
		vk_usage += {.UNIFORM_BUFFER}
		dst_access_mask += {.UNIFORM_READ}
		dst_stage_mask += {.COMPUTE_SHADER, .VERTEX_SHADER, .FRAGMENT_SHADER, .GEOMETRY_SHADER}
	}
	if .Storage in usage {
		vk_usage += {.STORAGE_BUFFER}
		dst_access_mask += {.SHADER_READ, .SHADER_WRITE}
		dst_stage_mask += {.COMPUTE_SHADER, .VERTEX_SHADER, .GEOMETRY_SHADER, .FRAGMENT_SHADER}
	}
	if .Transfer in usage {
		vk_usage += {.TRANSFER_SRC}
		dst_access_mask += {.TRANSFER_READ}
		dst_stage_mask += {.TRANSFER}
	}
	return
}

_update_buffers :: proc() {
	// Uniform buffers
	for &ubo in ctx.gfx.buffer_manager.uniform_buffers.values {
		if ubo.dirty {
			ubo.apply(&ubo)
		}
	}

	// Storage buffers
	for &sbo in ctx.gfx.buffer_manager.storage_buffers.values {
		if sbo.dirty {
			sbo.apply(&sbo)
		}
	}
}

_create_vk_buffer :: proc(
	size: vk.DeviceSize,
	usage: vk.BufferUsageFlags,
	memory_usage: vma.MemoryUsage,
	memory_flags: vma.AllocationCreateFlags,
	required_flags: vk.MemoryPropertyFlags = {},
	preferred_flags: vk.MemoryPropertyFlags = {},
) -> (
	vk.Buffer,
	vma.Allocation,
	vma.AllocationInfo,
) {
	buffer_info := vk.BufferCreateInfo {
		sType       = .BUFFER_CREATE_INFO,
		size        = size,
		usage       = usage,
		sharingMode = .EXCLUSIVE,
	}

	allocation_create_info := vma.AllocationCreateInfo {
		usage          = memory_usage,
		flags          = memory_flags,
		requiredFlags  = required_flags,
		preferredFlags = preferred_flags,
	}

	vk_buffer: vk.Buffer
	allocation: vma.Allocation
	allocation_info: vma.AllocationInfo
	vma.CreateBuffer(
		ctx.gfx.vk_state.allocator,
		&buffer_info,
		&allocation_create_info,
		&vk_buffer,
		&allocation,
		&allocation_info,
	)

	return vk_buffer, allocation, allocation_info
}

@(private = "file")
_create_vk_device_local_buffer :: proc(
	data: rawptr,
	size: vk.DeviceSize,
	usage: vk.BufferUsageFlags,
	dst_access_mask: vk.AccessFlags2,
	dst_stage_mask: vk.PipelineStageFlags2,
	loc := #caller_location,
) -> (
	vk_buffer: vk.Buffer,
	allocation: vma.Allocation,
	allocation_info: vma.AllocationInfo,
) {
	sc := begin_single_cmd()

	// TODO: Don't create a staging buffer if the device has enough DEVICE_LOCAL and HOST_VISIBLE memeory
	// Staging buffer
	staging_buffer := _create_staging_buffer(data, size, loc)
	_cmd_buffer_barrier(sc.cmd, staging_buffer.id, {.HOST_WRITE}, {.TRANSFER_READ}, {.HOST}, {.TRANSFER})
	defer _destroy_buffer(&staging_buffer)

	// Result buffer
	vk_buffer, allocation, allocation_info = _create_vk_buffer(size, {.TRANSFER_DST} + usage, .AUTO_PREFER_DEVICE, {})
	_cmd_copy_buffer(sc.cmd, staging_buffer.id, vk_buffer, size)
	_cmd_buffer_barrier(sc.cmd, vk_buffer, {.TRANSFER_WRITE}, dst_access_mask, {.TRANSFER}, dst_stage_mask)

	end_single_cmd(sc)
	return
}

@(private = "file")
_create_staging_buffer :: proc(data: rawptr, size: Device_Size, loc := #caller_location) -> (buffer: Buffer_Data) {
	assert(data != nil, loc = loc)
	assert(size > 0, loc = loc)
	vk_buffer, alloc, alloc_info := _create_vk_buffer(
		size,
		{.TRANSFER_SRC},
		.AUTO_PREFER_HOST,
		{.HOST_ACCESS_RANDOM, .MAPPED},
		{},
		{},
	)
	_vk_map_memory(alloc, &buffer.mapped)
	_buffer_fill_mapped_memory(alloc, alloc_info, data, size, buffer.mapped)

	return Buffer_Data{id = vk_buffer, size = size, vk_usage = {.TRANSFER_SRC}, alloc = alloc, alloc_info = alloc_info}
}

_vk_map_memory :: proc(alloc: vma.Allocation, out_mapped: ^rawptr, loc := #caller_location) {
	must(vma.MapMemory(ctx.gfx.vk_state.allocator, alloc, out_mapped), loc = loc)
}

_init_buffer_manager :: proc() {
	ctx.gfx.buffer_manager = new(Buffer_Manager)
}

_destroy_buffer_manager :: proc() {
	for ubo in ctx.gfx.buffer_manager.uniform_buffers.values {
		free(ubo.data)
	}
	hm.destroy(&ctx.gfx.buffer_manager.uniform_buffers)

	for sbo in ctx.gfx.buffer_manager.storage_buffers.values {
		free(sbo.data)
	}
	hm.destroy(&ctx.gfx.buffer_manager.storage_buffers)

	free(ctx.gfx.buffer_manager)
}

@(private = "file")
_buffer_fill_mapped_memory :: proc(
	alloc: vma.Allocation,
	allloc_info: vma.AllocationInfo,
	data: rawptr,
	size: Device_Size,
	mapped: rawptr,
) {
	assert(data != nil)
	assert(size > 0)
	assert(mapped != nil)
	mem_props := _get_memory_properties(allloc_info)
	mem.copy(mapped, data, int(size))
	if !(.HOST_COHERENT in mem_props) {
		vma.FlushAllocation(ctx.gfx.vk_state.allocator, alloc, 0, cast(vk.DeviceSize)vk.WHOLE_SIZE)
	}
}

@(private = "file")
_get_memory_properties :: proc(alloc_info: vma.AllocationInfo) -> vk.MemoryPropertyFlags {
	return ctx.gfx.vk_state.memory_propertices.memoryTypes[alloc_info.memoryType].propertyFlags
}
