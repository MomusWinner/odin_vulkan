# ve 
A small Vulkan Rendering Engine

> [!WARNING]
> **`ve` is currently under active development** and is not recommended for production use. The API may change significantly between versions.
> 
> **Platform Support Note:** Currently only Linux is supported. Windows support is planned for future releases.

##  Key Features

### Pipeline Hot Reloading
Real-time shader and pipeline recompilation during runtime
```odin
    if (ve.is_key_pressed(.R)) {
        gfx.hot_reload_shaders()
    }
```

### Material Code Generation
Automatic material system generation from material structures. A key advantage of this approach is type-safe material interfaces. The generator also handles ``std140`` memory alignment by automatically adding the necessary padding.

Example:
```odin
package main

import "ve"
import gfx "ve/graphics"

@(material)
My_Material :: struct {
    color:   ve.vec4,
    vector:  ve.vec3,
    texture: gfx.Texture_Handle,
}
```

After defining your material struct, run:
```bash
$ make gen
```
This generates two files:
1. An Odin source file in your project package.
2. A shader header file at ``assets/shader/gen_types.h``.

The generated Odin source file provides type-safe getter and setter functions for each field in your material struct:
```odin
    material: gfx.Material

    init_mtrl_my(&material, pipeline_h)

    mtrl_my_set_color(&material, {0.5, 1, 0, 1})
    mtrl_my_set_texture(&material, texture_h)
    mtrl_my_set_vector(&material, {1, 1, 1})

    my_texture := mtrl_my_get_texture(material)
    my_color := mtrl_my_get_color(material)
    my_vector := mtrl_my_get_vector(material)
```


### Bindless Rendering
Leverages modern GPU bindless descriptors to eliminate explicit texture and buffer bind calls, improving performance and simplifying resource management.

### 🚧Archetype ECS🚧
In development

## Vulkan Features
- Dynamic Rendering
- Descriptor Indexing
- Synchronization 2

## Installetion

```bash
# Clone the repository
git clone https://github.com/yourusername/ve.git
cd ve

unzip dependencies.zip
make gen-ve
make gen
make run
```
## Examples

#### Postprocessing
Demonstrates a combination of screen-space blur and custom background color grading applied in post-processing.
<img width="1920" height="1080" alt="screenshot_20260425_104335" src="https://github.com/user-attachments/assets/33f690c5-f6d3-462c-abf4-f4a8bc71acb1" />

#### Text
Shows anti-aliased text rendering with support for custom fonts and layouts.
<img width="1920" height="1080" alt="screenshot_20260425_104659" src="https://github.com/user-attachments/assets/6c157d34-aa46-4585-9925-5b144a3c55f4" />

#### Light
Example of simple lighting with ambient, diffuse components.
<img width="1920" height="1080" alt="screenshot_20260425_104203" src="https://github.com/user-attachments/assets/dd76c602-9e56-4d6f-b21a-707aa0a5d464" />

#### HDR + Bloom
<img width="1920" height="1080" alt="screenshot_20260425_104818" src="https://github.com/user-attachments/assets/59486fa5-84a9-43d8-aad3-124bc2570e7d" />

#### Instancing
<img width="1920" height="1080" alt="screenshot_20260425_104923" src="https://github.com/user-attachments/assets/b295f799-42d4-4ae0-91e4-a30bbd84219c" />

#### Compute
<img width="1920" height="1080" alt="screenshot_20260425_105214" src="https://github.com/user-attachments/assets/d1b4af08-33b4-4692-bcdd-47c88f44b89a" />

#### Skybox
<img width="1920" height="1080" alt="screenshot_20260425_105421" src="https://github.com/user-attachments/assets/aa3640a4-7043-493f-b383-30b4c1335ac3" />

#### Outline
<img width="1920" height="1080" alt="screenshot_20260425_105556" src="https://github.com/user-attachments/assets/17a18dd3-fce1-4923-8aa5-03b6ee866d09" />
