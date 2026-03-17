#version 450

#include "gen_types.h"

layout(location = 0) in vec2 fragTexCoord;

layout(location = 0) out vec4 outColor;

layout (constant_id = 0) const bool horizontal = true;

const int weight_length = 5;
const float weight[weight_length] = float[] (0.227027, 0.1945946, 0.1216216, 0.054054, 0.016216);

#define getImage() gTextures2D[getGaussianBlurUBO(H0()).blur]

void main() {
	vec2 tex_offset = 1.0 / textureSize(getImage(), 0); // gets size of single texel
	vec3 result = texture(getImage(), fragTexCoord).rgb * weight[0]; // current fragment's contribution

	if(horizontal) {
		for(int i = 1; i < weight_length; ++i) {
			result += texture(getImage(), fragTexCoord + vec2(tex_offset.x * i, 0.0)).rgb * weight[i];
			result += texture(getImage(), fragTexCoord - vec2(tex_offset.x * i, 0.0)).rgb * weight[i];
		}
	}
	else {
		for(int i = 1; i < weight_length; ++i) {
			result += texture(getImage(), fragTexCoord + vec2(0.0, tex_offset.y * i)).rgb * weight[i];
			result += texture(getImage(), fragTexCoord - vec2(0.0, tex_offset.y * i)).rgb * weight[i];
		}
	}
	outColor = vec4(result, 1.0);
}
