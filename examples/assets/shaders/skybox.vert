#version 450

#include "buildin:bindless.h"

layout(location = 0) in vec3 inPosition;
layout(location = 1) in vec2 inTexCoord;
layout(location = 2) in vec3 inNormal;
layout(location = 3) in vec4 inColor;

layout(location = 0) out vec3 fragPos;

void main() {
	mat4 view = mat4(mat3(getCamera().view));
	gl_Position = getCamera().projection * view * vec4(inPosition, 1.0);

	fragPos = vec3(inPosition);
	fragPos.xy *= -1;
}
