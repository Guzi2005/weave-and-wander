@tool
extends Resource
## Rest-space shaping for vertical garments. This is not a physics solver.

const HEIGHT_BINS := 32
const ANGLE_BINS := 32
const ANGLE_STEP := TAU / ANGLE_BINS
const ANGLE_SUPPORT := ANGLE_STEP * 2.0
const RADIAL_EPSILON := 0.000001
const HEIGHT_EPSILON := 0.000001

@export var enabled := true
@export var root_height := 1.31
@export var hem_height := 0.20
@export var side_ease: Curve = _curve([Vector2(0, 0), Vector2(1, 0)])
@export var front_ease: Curve = _curve([Vector2(0, 0), Vector2(1, 0)])
@export var back_ease: Curve = _curve([Vector2(0, 0), Vector2(1, 0)])
# Support half-width in rest-space height units. Curves use root=0, hem=1.
@export_range(0.0, 1.0, 0.001, "or_greater") var contour_span := 0.16
@export_range(0.0, 1.0, 0.01) var bridge_tension := 0.0
@export var contour_strength: Curve = _curve([Vector2(0, 0), Vector2(0.15, 1), Vector2(1, 1)])


static func _curve(points: Array[Vector2]) -> Curve:
	var result := Curve.new()
	result.min_value = 0.0
	result.max_value = 1.0
	for point in points:
		result.add_point(point, 0.0, 0.0, Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
	return result


static func _sample(curve: Curve, t: float) -> float:
	if curve == null or curve.point_count == 0: return 0.0
	var value := curve.sample(t)
	return maxf(0.0, value) if is_finite(value) else 0.0


static func _support(distance: float, span: float) -> float:
	var t := clampf(distance / span, 0.0, 1.0)
	var q := 1.0 - t * t
	return q * q * q


func _eligible(index: int, original: PackedVector3Array, fitted: PackedVector3Array, mask: PackedByteArray) -> bool:
	return (mask.is_empty() or mask[index] != 0) and original[index].is_finite() and fitted[index].is_finite() \
		and original[index].y < root_height - HEIGHT_EPSILON and original[index].y >= hem_height \
		and Vector2(original[index].x, original[index].z).length_squared() > RADIAL_EPSILON * RADIAL_EPSILON


func fit(original: PackedVector3Array, fitted: PackedVector3Array, eligible: PackedByteArray = PackedByteArray()) -> PackedVector3Array:
	var result := fitted.duplicate()
	if not enabled or original.size() != fitted.size() or (not eligible.is_empty() and eligible.size() != original.size()): return result
	if not is_finite(root_height) or not is_finite(hem_height) or root_height <= hem_height: return result
	var length := root_height - hem_height
	if not is_finite(length): return result
	var span := maxf(0.0, contour_span) if is_finite(contour_span) else 0.0
	var tension := clampf(bridge_tension, 0, 1) if is_finite(bridge_tension) else 0.0
	var peaks := PackedFloat64Array()
	var heights := PackedFloat64Array()
	var angles := PackedFloat64Array()
	peaks.resize(HEIGHT_BINS * ANGLE_BINS)
	heights.resize(peaks.size())
	angles.resize(peaks.size())
	if span > 0.0 or tension > 0.0:
		# One representative peak per cell bounds work independently of mesh density.
		for index in original.size():
			if not _eligible(index, original, fitted, eligible): continue
			var p := original[index]
			var excess := Vector2(fitted[index].x, fitted[index].z).length() - Vector2(p.x, p.z).length()
			if excess <= 0.0: continue
			var t := clampf((root_height - p.y) / length, 0.0, 1.0)
			var angle := fposmod(atan2(p.x, p.z), TAU)
			var row := mini(HEIGHT_BINS - 1, int(t * HEIGHT_BINS))
			var column := mini(ANGLE_BINS - 1, int(angle / ANGLE_STEP))
			var cell := row * ANGLE_BINS + column
			if excess > peaks[cell] or (excess == peaks[cell] and (p.y < heights[cell] \
				or (p.y == heights[cell] and angle < angles[cell]))):
				peaks[cell] = excess
				heights[cell] = p.y
				angles[cell] = angle
	for index in original.size():
		if not _eligible(index, original, fitted, eligible): continue
		var p := original[index]
		var t := clampf((root_height - p.y) / length, 0.0, 1.0)
		var radial := Vector2(p.x, p.z)
		var direction := radial.normalized()
		# +Z is front; squared directional weights sum to one without front/back bleed.
		var ease := _sample(side_ease, t) * direction.x * direction.x
		ease += _sample(front_ease if direction.y >= 0.0 else back_ease, t) * direction.y * direction.y
		var fitted_radial := Vector2(fitted[index].x, fitted[index].z)
		var own_excess := maxf(0.0, fitted_radial.length() - radial.length())
		var envelope := 0.0
		var strength := clampf(_sample(contour_strength, t), 0.0, 1.0)
		if (span > 0.0 or tension > 0.0) and strength > 0.0:
			var angle := fposmod(atan2(p.x, p.z), TAU)
			var column := mini(ANGLE_BINS - 1, int(angle / ANGLE_STEP))
			var first := mini(HEIGHT_BINS - 1, int(clampf(t - span / length, 0.0, 1.0) * HEIGHT_BINS))
			var last := mini(HEIGHT_BINS - 1, int(clampf(t + span / length, 0.0, 1.0) * HEIGHT_BINS))
			if tension > 0.0:
				first = 0
				last = HEIGHT_BINS - 1
			for row in range(first, last + 1):
				for neighbor in range(column - 2, column + 3):
					var cell := row * ANGLE_BINS + posmod(neighbor, ANGLE_BINS)
					if peaks[cell] <= 0.0: continue
					var distance := absf(p.y - heights[cell])
					var angular_distance := absf(wrapf(angle - angles[cell], -PI, PI))
					if angular_distance >= ANGLE_SUPPORT: continue
					var support := _support(distance, span) if span > 0 and distance < span else 0.0
					if tension > 0:
						# Taut root/hem chords bridge small body protrusions without pulling
						# cloth inward or copying the body's local concavities.
						var peak_t := clampf((root_height - heights[cell]) / length, .00001, .99999)
						var chord := t / peak_t if t < peak_t else (1.0 - t) / (1.0 - peak_t)
						support = maxf(support, maxf(0, chord) * tension)
					var spread := peaks[cell] * support * _support(angular_distance, ANGLE_SUPPORT)
					envelope = maxf(envelope, spread)
		var addition := ease + maxf(0.0, envelope - own_excess) * strength
		if addition <= 0.0 or not is_finite(addition): continue
		var outward := fitted_radial.normalized() if fitted_radial.length_squared() > RADIAL_EPSILON * RADIAL_EPSILON else direction
		var moved := fitted_radial + outward * addition
		if moved.is_finite(): result[index] = Vector3(moved.x, fitted[index].y, moved.y)
	return result
