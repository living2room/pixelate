shader_type canvas_item;

// --- 核心控制参数 --- //
uniform int pixel_level : hint_range(1, 512) = 128;
uniform int color_level : hint_range(2, 128) = 64;
uniform bool use_palette = false;      // 调色板开关
uniform vec4 palette[16];              // 调色板颜色数组
uniform int palette_size = 0;          // 实际使用的颜色数量

void fragment() {
    // 像素化处理
    vec2 pixel_scale = vec2(float(pixel_level));
    vec2 uv_quantized = (floor(UV * pixel_scale) + 0.5) / pixel_scale;
    vec4 color = texture(TEXTURE, uv_quantized);

    // 颜色空间处理
    float use_linear = step(32.0, float(color_level));
    color.rgb = mix(
        color.rgb,
        pow(color.rgb, vec3(2.2)),
        use_linear
    );

    // 颜色量化处理
    float step_size = 1.0 / (float(color_level) - 1.0);
    vec3 quantized = vec3(
        round(color.r / step_size) * step_size,
        round(color.g / step_size) * step_size,
        round(color.b / step_size) * step_size
    );

    // 调色板颜色替换
    if (use_palette && palette_size > 0) {
        float min_dist = 9999.0;
        vec3 closest_color = quantized;
        
        for (int i = 0; i < 16; i++) {
            if (i >= palette_size) break;
            
            vec3 palette_color = palette[i].rgb;
            // 统一到相同颜色空间比较
            vec3 compare_color = mix(palette_color, pow(palette_color, vec3(2.2)), use_linear);
            float dist = distance(quantized, compare_color);
            
            if (dist < min_dist) {
                min_dist = dist;
                closest_color = palette_color;
            }
        }
        quantized = closest_color;
    }

    // 最终颜色空间转换
    quantized = mix(
        quantized,
        pow(quantized, vec3(1.0/2.2)),
        use_linear
    );

    COLOR = vec4(quantized, color.a);
}