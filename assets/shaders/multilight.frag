#version 450

#include "gen_types.h"

layout(location = 0) in vec2 fragTexCoord;
layout(location = 1) in vec4 fragColor;
layout(location = 2) in vec3 fragNormal;
layout(location = 3) in vec3 fragPos;

layout(location = 0) out vec4 outColor;
layout(location = 1) out vec4 outBrightColor;

#define getLight(i) getMtrlMultilight().lights[i]

void main() {
	vec3 color = getMtrlMultilight().color;
	vec3 normal = normalize(fragNormal);
	// ambient
	vec3 ambient = 0.0 * color;
	// lighting
	vec3 lighting = vec3(0.0);

	for (int i = 0; i < 4; i++) {
		// diffuse
		vec3 lightDir = normalize(getLight(i).position - fragPos);
		float diff = max(dot(lightDir, normal), 0.0);
		vec3 diffuse = vec3(getLight(i).color) * diff * color;
		vec3 result = diffuse;
		// attenuation (use quadratic as we have gamma correction)
		float distance = length(fragPos - getLight(i).position);
		result *= 1.0 / (distance * distance);
		lighting += result;
	}

	outColor = vec4(ambient + lighting, 1.0);

	float brightness = dot(outColor.rgb, vec3(0.2126, 0.7152, 0.0722));
	if(brightness > 1.0)
		outBrightColor = vec4(outColor.rgb, 1.0);
	else
		outBrightColor = vec4(0.0, 0.0, 0.0, 1.0);
}
