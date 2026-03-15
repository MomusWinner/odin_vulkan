#version 450

layout(location = 0) in vec2 inPosition;
layout(location = 1) in vec2 inVelocity;

layout(location = 0) out vec3 fragColor;

void main() {
	gl_PointSize = 1.0;
	gl_Position = vec4(inPosition, 1.0, 1.0);
	fragColor = mix(vec3(1,0,0), vec3(1,1,0), length(inVelocity));
}
