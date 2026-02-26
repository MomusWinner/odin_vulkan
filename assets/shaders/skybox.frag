#version 450

#include "buildin:gen_types.h"

layout(location = 0) in vec3 fragPos;

layout(location = 0) out vec4 outColor;

void main() {
	outColor = texture(uGlobalTexturesCube[getMtrlBase().texture], fragPos);
}
