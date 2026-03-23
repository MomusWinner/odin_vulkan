#ifndef BUILDIN_BINDLESS_H
#define BUILDIN_BINDLESS_H

#extension GL_EXT_nonuniform_qualifier : enable

#define BindlessDescriptorSet 0

#define BindlessUniformBinding 0
#define BindlessStorageBinding 1
#define BindlessSamplerBinding 2
#define BindlessComputeBinding 3

#define GetLayoutVariableName(Name) u##Name##Register

// Register unifrom buffer
#define RegisterUniform(Name, Struct) \
	layout(std140, set = BindlessDescriptorSet, binding = BindlessUniformBinding) \
	uniform Name Struct \
	GetLayoutVariableName(Name)[]

// Register storage buffer
#define RegisterBuffer(Layout, BufferAccess, Name, Struct) \
	layout(Layout, set = BindlessDescriptorSet, binding = BindlessStorageBinding) \
	BufferAccess buffer Name Struct GetLayoutVariableName(Name)[]

#define GetResource(Name, Index) \
    GetLayoutVariableName(Name)[Index]

RegisterUniform(DummyUniform, {uint ignore; });
RegisterBuffer(std430, readonly, DummyBuffer, { uint ignore; });

layout(set = BindlessDescriptorSet, binding = BindlessSamplerBinding) \
    uniform sampler2D gTextures2D[];

layout(set = BindlessDescriptorSet, binding = BindlessSamplerBinding) \
    uniform samplerCube gTexturesCube[];

layout( push_constant ) uniform constants {
	mat4 model;
	uint camera;
	uint handle0;
	uint handle1;
	uint handle2;
	uint handle3;
	uint handle4;
	uint handle5;
	uint handle6;
	uint handle7;
	uint handle8;
	uint handle9;
	uint handle10;
	uint reserve0;
	uint reserve1;
	uint reserve2;
	uint reserve3;
} PushConstants;

#define getModel() PushConstants.model

#define HCamera() PushConstants.camera
#define H0() PushConstants.handle0
#define H1() PushConstants.handle1
#define H2() PushConstants.handle2
#define H3() PushConstants.handle3
#define H4() PushConstants.handle4
#define H5() PushConstants.handle5
#define H6() PushConstants.handle6
#define H7() PushConstants.handle7
#define H8() PushConstants.handle8
#define H9() PushConstants.handle9
#define H10() PushConstants.handle10

RegisterUniform(Camera, {
	mat4 view;
	mat4 projection;
	vec3 position;
	float pad0;
});

#define getCameraByHandle(index) GetResource(Camera, index)

#define getCamera() getCameraByHandle(HCamera())

// HELPERS
const uint INVALID_RESOURCE_HANDLE = ~0u;

#define isHandleValid(handle)\
	(handle != INVALID_RESOURCE_HANDLE)

#endif // BUILDIN_BINDLESS_H
