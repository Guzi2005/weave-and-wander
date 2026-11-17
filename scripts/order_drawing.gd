extends TextureRect

# Front-view drawings in a shared 64 × 72 paper frame.
const OUTLINES := {
	0: "M23 7 Q32 16 41 7 L50 15 46 29 41 26 40 34 55 63 Q32 69 9 63 L24 34 23 26 18 29 14 15Z",
	1: "M23 9 Q32 0 41 9 L42 25 47 30 52 63 Q32 67 12 63 L17 30 22 25Z M26 11 L25 21 39 21 38 11 Q32 5 26 11Z",
	2: "M23 9 L28 8 32 23 37 8 42 10 Q40 23 47 27 L46 55 36 59 32 54 28 59 18 55 17 27 Q24 22 23 9Z",
	3: "M24 10 L40 10 47 14 58 45 49 49 43 35 44 59 20 59 21 35 15 49 6 45 17 14Z",
	4: "M18 9 L46 9 49 63 35 63 32 32 29 63 15 63Z",
	5: "M21 16 L43 16 52 56 Q32 62 12 56Z",
	9: "M32 24 C22 4 9 22 21 31 C0 30 8 51 23 43 C18 62 38 66 38 46 C52 60 65 42 47 35 C65 22 46 10 39 27 Q37 15 32 24Z",
	10: "M23 11 L41 11 48 15 57 30 48 35 43 29 44 58 20 58 21 29 16 35 7 30 16 15Z",
	11: "M24 11 Q32 17 40 11 Q52 11 54 28 L46 32 42 28 49 57 Q32 65 15 57 L22 28 18 32 10 28 Q12 11 24 11Z",
	12: "M20 13 L44 13 53 59 Q32 65 11 59Z",
	13: "M22 10 L27 9 32 24 38 9 43 11 Q39 23 46 29 L45 57 19 57 18 29 Q25 22 22 10Z",
	17: "M10 55 C-1 1 65 1 54 55 L51 58 C54 9 10 9 13 58Z"
}
const SEAMS := {
	0:"M23 34 H41", 1:"M25 41 H39 V47 Q32 53 25 47Z", 2:"M32 23 V54",
	3:"M24 10 L28 20 32 14 36 20 40 10 M32 14 V58", 4:"M18 15 H46 M32 15 V27",
	5:"M20 21 H44 M26 22 L22 54 M38 22 L42 54", 9:"M36 36 A4 4 0 1 1 28 36 A4 4 0 1 1 36 36",
	10:"M23 11 L24 22 29 20 32 25 40 14 41 11 M32 25 V57", 11:"M21 29 Q32 34 43 29",
	12:"M20 18 H44 M26 19 L20 56 M38 19 L44 56", 13:"M26 11 L32 28 39 11",17:""
}

func configure(data: Dictionary) -> void:
	custom_minimum_size = Vector2(60,72)
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var style := int(data.style)
	var path := str(OUTLINES.get(style, ""))
	var pigment: Color = data.pigment
	var lines := ""
	for i in range(0, 65, 6):
		if int(data.pattern_code) >= 1:
			lines += "M%d 0v72 " % i
		if int(data.pattern_code) == 2:
			lines += "M0 %dh64 " % i
	var scale_y := 1.0
	if style == 12:
		scale_y = remap(float(data.skirt_length), .35, 1.05, .62, 1.02)
	elif style in [10,11,13]:
		scale_y = remap(float(data.garment_length), .55, 1.05, .78, 1.05)
	var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="64" height="72"><g transform="translate(0 3) scale(1 %s)"><defs><clipPath id="cut"><path d="%s" clip-rule="evenodd"/></clipPath></defs><path d="%s" fill="#%s" fill-rule="evenodd"/>' % [scale_y,path,path,pigment.to_html(false)]
	if not lines.is_empty():
		svg += '<path d="%s" clip-path="url(#cut)" fill="none" stroke="#%s" stroke-width="1.4"/>' % [lines, pigment.lightened(.42).to_html(false)]
	if not str(SEAMS.get(style,"")).is_empty():
		svg += '<path d="%s" fill="none" stroke="#%s" stroke-width=".7" opacity=".55"/>' % [SEAMS[style], pigment.darkened(.25).to_html(false)]
	var drawing := Image.new()
	if drawing.load_svg_from_string(svg + "</g></svg>", 2.0) == OK:
		texture = ImageTexture.create_from_image(drawing)
