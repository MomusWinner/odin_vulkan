#version 450

#include "buildin:gen_types.h"

layout(location = 0) in vec2 fragTexCoord;
layout(location = 1) in vec4 fragColor;
layout(location = 2) in vec3 fragNormal;
layout(location = 3) in vec3 fragPos;

layout(location = 0) out vec4 outColor;

void main() {
	outColor = vec4(1,1,1,1);
	vec3 I = normalize(fragPos - getCamera().position);
	float ratio = 1.00 / 2.42;
	vec3 R = refract(I, normalize(fragNormal), ratio);

	R.xy *= -1;
	vec3 color = texture(gTexturesCube[H0()], R).rgb;
	color.b += 0.07;
	outColor = vec4(color, 1.0);
}
