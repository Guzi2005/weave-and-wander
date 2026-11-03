extends SceneTree

## Validates .tres files emitted by the wiki browser serializer.
const Stripe = preload("res://components/motifs/stripe_motif.gd")
const Tassel = preload("res://components/motifs/tassel_motif.gd")

func _initialize() -> void:
	var failures: Array[String] = []
	var stripe := load("res://captures/motif_recipe_roundtrip/stripe-overskirt.tres") as Stripe
	var tassel := load("res://captures/motif_recipe_roundtrip/tassel-sash.tres") as Tassel
	if stripe == null:
		failures.append("Browser StripeMotif recipe did not load")
	else:
		if stripe.repeat_count != 12: failures.append("Stripe repeat_count mismatch")
		if stripe.sequence.size() != 3: failures.append("Stripe sequence mismatch")
		if not stripe.base_color.is_equal_approx(Color("203040")): failures.append("Stripe base color mismatch")
		for patch in stripe.patches():
			if patch.u1 <= patch.u0: failures.append("Invalid stripe patch")
	if tassel == null:
		failures.append("Browser TasselMotif recipe did not load")
	else:
		if tassel.strand_count != 36 or tassel.puff_count != 16: failures.append("Tassel counts mismatch")
		if tassel.seed != 42: failures.append("Tassel seed mismatch")
		if not is_equal_approx(tassel.length, .16): failures.append("Tassel length mismatch")
		if tassel.colors.size() != 2 or not tassel.colors[0].is_equal_approx(Color("112233")):
			failures.append("Tassel colors mismatch")
		var groups := tassel.build(Vector3.ZERO)
		if groups.size() != 2: failures.append("Tassel geometry groups missing")
	for failure in failures: push_error(failure)
	print("MOTIF_RECIPE_ROUNDTRIP_PASS" if failures.is_empty() else "MOTIF_RECIPE_ROUNDTRIP_FAILED")
	quit(0 if failures.is_empty() else 1)
