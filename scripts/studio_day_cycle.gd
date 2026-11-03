extends RefCounted

# Art-directed keyframes: hour, sky top, horizon, ambient, sunlight, ambient energy, sun energy, lamp.
const KEYS := [
	[0.0, "101b38", "283d64", "8095c4", "90b0e7", .22, .055, 1.0],
	[5.0, "24385c", "6e739c", "8496be", "9baedf", .27, .07, 1.0],
	[6.0, "7182aa", "f1ad8b", "b2a4bd", "ffc090", .42, .48, .6],
	[7.5, "8fb2cd", "f7ddbc", "dde0e1", "ffe0b3", .65, .8, .12],
	[12.0, "81adc3", "e0eade", "eef4ee", "fff0d8", .76, .86, 0.0],
	[16.5, "8ea9b9", "e7cbbb", "d4d5d7", "ffe0b6", .63, .76, .05],
	[18.0, "777f9d", "f0a180", "b5a1b7", "ffad72", .42, .65, .45],
	[18.8, "4c638e", "b78da7", "8a9dc5", "fdb995", .31, .22, .83],
	[19.5, "233f73", "6b8cbc", "6f91cb", "8babeb", .27, .07, 1.0],
	[21.0, "142544", "3b527c", "8197c2", "90b0e7", .22, .055, 1.0],
	[24.0, "101b38", "283d64", "8095c4", "90b0e7", .22, .055, 1.0],
]


static func sample(minutes: float) -> Dictionary:
	var hour := fposmod(minutes, 1440.0) / 60.0
	for i in range(KEYS.size()-1):
		var a: Array = KEYS[i]
		var b: Array = KEYS[i+1]
		if hour <= float(b[0]):
			var t := smoothstep(float(a[0]), float(b[0]), hour)
			return {
				"hour": hour,
				"sky": Color(a[1]).lerp(Color(b[1]), t),
				"horizon": Color(a[2]).lerp(Color(b[2]), t),
				"ambient": Color(a[3]).lerp(Color(b[3]), t),
				"sun": Color(a[4]).lerp(Color(b[4]), t),
				"ambient_energy": lerpf(a[5], b[5], t),
				"sun_energy": lerpf(a[6], b[6], t),
				"lamps": lerpf(a[7], b[7], t),
			}
	return {}
