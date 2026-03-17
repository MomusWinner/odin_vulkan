#version 450

#include "gen_types.h"

layout(location = 0) in vec2 fragTexCoord;
layout(location = 1) in vec4 fragColor;
layout(location = 2) in vec3 fragNormal;
layout(location = 3) in vec3 fragPos;

layout(location = 0) out vec4 outColor;
layout(location = 1) out vec4 outBrightColor;

void main() {
	vec3 color = getLightBoxUBO(H0()).color;
	outColor = vec4(color, 1);

	float brightness = dot(color, vec3(0.2126, 0.7152, 0.0722));
	if(brightness > 1.0)
		outBrightColor = vec4(color, 1.0);
	else
		outBrightColor = vec4(0.0, 0.0, 0.0, 1.0);
}
