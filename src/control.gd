extends Control
const PICK_COLOR = preload("res://src/pick_color.tscn")
@onready var menu_button: MenuButton = %MenuButton
@onready var inoput: TextureRect = %Inoput
@onready var output: TextureRect = %Output  ##实际工作图
@onready var sub_viewport: SubViewport = %SubViewport
@onready var file_dialog: FileDialog = $FileDialog
@onready var output_2: TextureRect = %Output2 ##用户看效果图
@onready var color_palette_box: HBoxContainer = %ColorPaletteBox

var opt:PopupMenu
var save_path:String
# 填充调色板数组
var palette_colors: Array[Color] = []
var palette_color_ui_arr:Array[PickColor]
func _ready() -> void:
	opt = menu_button.get_popup()
	opt.index_pressed.connect(_on_index_pressed)
	file_dialog.file_selected.connect(_on_file_selected)
	
func generate_palette():
	palette_colors = []
	var texture = output_2.texture
	if not texture:
		push_warning("No texture found!")
		return
	var image = texture.get_image()
	if not image:
		push_warning("Failed to get image from texture!")
		return
	# 下采样加速处理
	var sample_size = 128  # 可调整采样尺寸
	image.resize(sample_size, sample_size, Image.INTERPOLATE_NEAREST)
	# 收集所有颜色
	var colors:PackedColorArray = []
	for y in image.get_height():
		for x in image.get_width():
			var c = image.get_pixel(x, y)
			if c.a > 0.5:  # 忽略透明像素
				colors.append(c)
	if colors.size() == 0:
		push_warning("No valid colors found!")
		return
	# 执行中位切分算法
	var palette = median_cut(colors, 16)
	for c in palette:
		palette_colors.append(Color(c.r, c.g, c.b))
	# 补满16个颜色
	while palette_colors.size() < 16:
		palette_colors.append(Color.BLACK)
	# 传递给shader
	var mat = output_2.material as ShaderMaterial
	if mat:
		mat.set_shader_parameter("palette", palette_colors)
		output.material.set("shader_parameter/palette",palette_colors)
		mat.set_shader_parameter("palette_size", min(palette.size(), 16))
		output.material.set("shader_parameter/palette_size", min(palette.size(), 16))
		print("Palette generated with ", palette.size(), " colors")

# 中位切分算法核心
func median_cut(colors: PackedColorArray, target: int) -> PackedColorArray:
	var cubes = [{
		colors = colors,
		bounds = _get_color_bounds(colors)
	}]
	while cubes.size() < target:
		# 寻找最大体积的cube
		var max_index = 0
		var max_volume = 0.0
		for i in cubes.size():
			var vol = _calculate_volume(cubes[i].bounds)
			if vol > max_volume:
				max_volume = vol
				max_index = i
		# 切割cube
		var cube = cubes.pop_at(max_index)
		var split_cubes = _split_cube(cube)
		cubes.append_array(split_cubes)
	# 提取平均颜色
	var result: PackedColorArray = []
	for cube in cubes:
		result.append(_average_color(cube.colors))
	return result

# 辅助函数：计算颜色范围
func _get_color_bounds(colors: PackedColorArray) -> Dictionary:
	var bounds = {
		r_min = 1.0, r_max = 0.0,
		g_min = 1.0, g_max = 0.0,
		b_min = 1.0, b_max = 0.0
	}
	for c in colors:
		bounds.r_min = min(bounds.r_min, c.r)
		bounds.r_max = max(bounds.r_max, c.r)
		bounds.g_min = min(bounds.g_min, c.g)
		bounds.g_max = max(bounds.g_max, c.g)
		bounds.b_min = min(bounds.b_min, c.b)
		bounds.b_max = max(bounds.b_max, c.b)
	return bounds

# 辅助函数：计算体积
func _calculate_volume(bounds: Dictionary) -> float:
	var r = bounds.r_max - bounds.r_min
	var g = bounds.g_max - bounds.g_min
	var b = bounds.b_max - bounds.b_min
	return r * g * b

# 辅助函数：切割cube
func _split_cube(cube: Dictionary) -> Array:
	var bounds = cube.bounds
	var channel = _get_largest_channel(bounds)
	# 按目标通道排序
	var sorted:Array[Color]
	sorted.append_array(cube.colors.duplicate())
	sorted.sort_custom(func(a, b): return a[channel] < b[channel])
	# 分割中点
	var mid = sorted.size() / 2
	var median = sorted[mid][channel]
	# 创建新bounds
	var bounds1 = bounds.duplicate()
	var bounds2 = bounds.duplicate()
	bounds1[channel + "_max"] = median
	bounds2[channel + "_min"] = median
	return [
		{ colors = sorted.slice(0, mid), bounds = _get_color_bounds(sorted.slice(0, mid)) },
		{ colors = sorted.slice(mid),    bounds = _get_color_bounds(sorted.slice(mid)) }
	]
# 辅助函数：获取最大范围通道
func _get_largest_channel(bounds: Dictionary) -> String:
	var r = bounds.r_max - bounds.r_min
	var g = bounds.g_max - bounds.g_min
	var b = bounds.b_max - bounds.b_min
	if r >= g and r >= b:
		return "r"
	elif g >= r and g >= b:
		return "g"
	else:
		return "b"
# 辅助函数：计算平均颜色
func _average_color(colors: PackedColorArray) -> Color:
	var total = Vector3.ZERO
	for c in colors:
		total += Vector3(c.r, c.g, c.b)
	var avg = total / colors.size()
	return Color(avg.x, avg.y, avg.z)
	
	
func open_img():
	file_dialog.show()
	
func save_and_output():
	sub_viewport.size = inoput.texture.get_size()
	output.texture = inoput.texture
	await RenderingServer.frame_post_draw
	var image: Image = sub_viewport.get_texture().get_image()
	var file_path :String = save_path +"/"+Time.get_datetime_string_from_system().replace(":", "-")+".png"
	var error = image.save_png(file_path)  # 或 save_jpg(), save_webp()
	if error != OK:
		push_error("保存失败！错误代码:", error)
		image.save_png("res:/"+file_path)
	else:
		prints("保存成功！路径:", file_path)
		OS.shell_open(save_path)


func _on_index_pressed(i:int):
	match i:
		0:
			open_img()
		1:
			save_and_output()
		2:
			queue_free()
			get_tree().quit()
		_:
			push_error("something is wrong!")

func _on_file_selected(path:String):
	print(path)
	save_path = path.get_base_dir()
	if FileAccess.file_exists(path):
		var image = Image.new()
		var error = image.load(path)  # 自动识别格式
		if error != OK:
			push_error("错误：无法加载图像，请检查路径或格式")
			return
		inoput.texture = ImageTexture.create_from_image(image)
		output_2.texture = inoput.texture
	else:
		push_error("文件不存在")

func _on_h_slider_pixel_value_changed(value: float) -> void:
	output_2.material.set_shader_parameter("pixel_level",value)
	output.material.set_shader_parameter("pixel_level",value)

func _on_h_slider_color_value_changed(value: float) -> void:
	output_2.material.set_shader_parameter("color_level",value)
	output.material.set_shader_parameter("color_level",value)

# 修改现有的_on_button_pressed函数，添加信号连接
func _on_button_pressed() -> void:
	if not palette_color_ui_arr.is_empty():
		palette_color_ui_arr.map(func(ui):ui.queue_free())
		palette_color_ui_arr = []
	generate_palette()
	output_2.material.set("shader_parameter/use_palette",true)
	output.material.set("shader_parameter/use_palette",true)
	await get_tree().process_frame
	# 创建颜色块时添加索引和信号连接
	for index in palette_colors.size():
		var palette_color_ui = PICK_COLOR.instantiate() as PickColor
		palette_color_ui.color = palette_colors[index]
		color_palette_box.add_child(palette_color_ui)
		palette_color_ui_arr.append(palette_color_ui)
		palette_color_ui.color_changed.connect(
			func(new_color):
				_on_color_changed(index, new_color)
		)
func _on_color_changed(index: int, new_color: Color):
	if index >= 0 && index < palette_colors.size():
		palette_colors[index] = new_color
	var mat = output_2.material as ShaderMaterial
	if mat:
		mat.set_shader_parameter("palette", palette_colors)
		output.material.set("shader_parameter/palette", palette_colors)
	RenderingServer.force_draw()
