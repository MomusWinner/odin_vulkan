#version 450

#include "buildin:bindless.h"

layout(location = 0) in vec3 fragPos;

layout(location = 0) out vec4 outColor;

void main() {
	outColor = texture(gTexturesCube[H0()], fragPos);
}
