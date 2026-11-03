extends SceneTree

const Ledger = preload("res://scripts/material_ledger.gd")

var errors: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func check(value: bool, message: String) -> void:
	if not value and message not in errors:
		errors.append(message)
		push_error(message)


func event_count(ledger: RefCounted, type: String) -> int:
	var count := 0
	for event in ledger.events:
		if event.type == type: count += 1
	return count


func ledger_with(records: Array[Dictionary]) -> RefCounted:
	var ledger: RefCounted = Ledger.new()
	ledger.bind_fabrics(records)
	return ledger


func _run() -> void:
	test_shared_arrays()
	test_normalization()
	test_estimate()
	test_reserve_ownership()
	test_no_cross_combining()
	test_cut_conservation()
	test_sewing()
	test_complete()
	test_cancel_before_cut()
	test_cancel_after_cut()
	test_atomic_failures()
	print("MATERIAL_LEDGER_TEST failures=",errors.size())
	quit(0 if errors.is_empty() else 1)


func test_shared_arrays() -> void:
	var batches: Array[Dictionary] = [{"id": "linen_a", "meters": 6.0}]
	var ledger := Ledger.new()
	ledger.bind_fabrics(batches)
	check(not ledger.fabric("linen_a").is_empty(),"Bound fabric not visible before mutation")
	batches.clear()
	check(ledger.fabric_batches.is_empty() and ledger.fabric("linen_a").is_empty(),"bind_fabrics copied the batch array")
	batches.append({"id": "linen_b", "meters": 3.0})
	check(ledger.fabric_batches.size() == 1 and not ledger.fabric("linen_b").is_empty(),"Appends to caller array not shared with ledger")
	var fresh := Ledger.new()
	check(fresh.thread_batches.size() == 1,"Default thread batch missing")
	var spool: Dictionary = fresh.thread_batches[0]
	check(spool.id == "thread_blue" and spool.meters == 80.0 and spool.material == "cotton","Default thread record incorrect")
	check(spool.pigment == Color("779ab1"),"Default thread pigment incorrect")
	check(not fresh.thread("thread_blue").is_empty(),"Default thread not resolvable by id")


func test_normalization() -> void:
	var record := {"id": "plain_roll", "meters": 5.0}
	var ledger := ledger_with([record])
	var live: Dictionary = ledger.fabric("plain_roll")
	check(live.width_m == 1.4 and live.thickness_m == 0.001,"Width/thickness defaults not normalized")
	check(live.material == "cotton" and live.location == "storage","Material/location defaults not normalized")
	check(live.pattern == "plain" and live.pattern_code == 0,"Plain pattern defaults not normalized")
	check(live.capacity_m >= 5.0,"Capacity not normalized to cover meters")
	check(live.pigment in Ledger.PALETTE,"Pigment default not from palette")
	check(ledger.fabric("missing").is_empty(),"Unknown fabric id did not return empty dictionary")
	check(ledger.thread("missing").is_empty(),"Unknown thread id did not return empty dictionary")
	var supplied := {
		"id": "stripe_roll", "meters": 4.0, "width_m": 2.0, "pattern": "stripe",
		"pigment": Color(1, 0, 0), "capacity_m": 9.0, "location": "shelf",
	}
	var ledger2 := ledger_with([supplied])
	var kept: Dictionary = ledger2.fabric("stripe_roll")
	check(kept.width_m == 2.0 and kept.location == "shelf" and kept.capacity_m == 9.0,"Supplied fields overwritten")
	check(kept.pigment == Color(1, 0, 0),"Supplied pigment overwritten")
	check(kept.pattern_code == 1,"Stripe pattern code mapping wrong")
	var checked: Dictionary = ledger2.fabric("stripe_roll")
	kept.meters = 2.5
	check(checked.meters == 2.5,"fabric() did not return the live dictionary")
	var check_roll := {"id": "check_roll", "meters": 4.0, "pattern": "check"}
	check(ledger_with([check_roll]).fabric("check_roll").pattern_code == 2,"Check pattern code mapping wrong")


func test_estimate() -> void:
	var ledger := ledger_with([{"id": "roll", "meters": 10.0}])
	var plan: Dictionary = ledger.estimate("roll")
	check(plan.ok and plan.reason == "","Default estimate rejected")
	check(is_equal_approx(plan.net_m, 0.9),"Net cut estimate wrong")
	check(is_equal_approx(plan.remnant_m, 0.18) and is_equal_approx(plan.waste_m, 0.06),"Remnant/waste estimate wrong")
	check(is_equal_approx(plan.cut_m, plan.net_m + plan.remnant_m + plan.waste_m),"Cut length not the sum of its parts")
	check(is_equal_approx(plan.thread_m, 12.0) and plan.size_factor == 1.0,"Thread estimate or size echo wrong")
	check(plan.cost_estimate > 0.0,"Cost estimate missing")
	var sized: Dictionary = ledger.estimate("roll", 2.0)
	check(sized.ok and is_equal_approx(sized.net_m, 1.8) and is_equal_approx(sized.thread_m, 24.0),"Size factor scaling wrong")
	var stripe := ledger_with([{"id": "stripe_roll", "meters": 10.0, "pattern": "stripe"}])
	var stripe_plan: Dictionary = stripe.estimate("stripe_roll")
	check(stripe_plan.ok and stripe_plan.cut_m > plan.cut_m,"Directional pattern allowance missing")
	for bad_size in [NAN, INF, -INF, 0.0, -1.0, 5.0]:
		check(not ledger.estimate("roll", bad_size).ok,"Illegal size factor accepted: %s" % bad_size)
	check(ledger.estimate("ghost").reason == "unknown_fabric","Missing fabric estimate not rejected")
	check(not ledger_with([{"id": "no_stock"}]).estimate("no_stock").ok,"Missing stock accepted")
	check(not ledger_with([{"id": "neg", "meters": -1.0}]).estimate("neg").ok,"Negative stock accepted")
	check(not ledger_with([{"id": "nan_stock", "meters": NAN}]).estimate("nan_stock").ok,"Nonfinite stock accepted")
	check(not ledger_with([{"id": "narrow", "meters": 10.0, "width_m": 0.3}]).estimate("narrow").ok,"Too narrow width accepted")
	check(ledger_with([{"id": "empty_roll", "meters": 0.0}]).estimate("empty_roll").reason == "insufficient_fabric","Zero stock accepted")
	check(ledger_with([{"id": "short", "meters": 1.0}]).estimate("short").reason == "insufficient_fabric","Insufficient stock accepted")


func test_reserve_ownership() -> void:
	var ledger := ledger_with([{"id": "roll_a", "meters": 6.0}, {"id": "roll_b", "meters": 6.0}])
	ledger.thread_batches.append({"id": "thread_red", "meters": 50.0})
	var job: Dictionary = ledger.reserve("roll_a", "thread_blue")
	check(not job.is_empty() and job.status == "reserved","Reservation failed")
	check(ledger.jobs[job.id] == job,"reserve() did not return the live job")
	check(job.sew_progress == 0.0 and job.output_id == "","Initial job fields wrong")
	check(ledger.fabric("roll_a").meters == 6.0 and ledger.thread("thread_blue").meters == 80.0,"Reservation deducted stock")
	check(job.material_snapshot is Dictionary and job.thread_snapshot is Dictionary,"Snapshots missing")
	check(ledger.available_fabric("roll_a") == 0.0,"Reserved roll still available")
	check(ledger.available_thread("thread_blue") == 0.0,"Reserved spool still available")
	check(ledger.available_fabric("roll_b") == 6.0 and ledger.available_thread("thread_red") == 50.0,"Unrelated stock wrongly blocked")
	check(ledger.reserve("roll_a", "thread_red").is_empty(),"Owned roll reserved by a second job")
	check(ledger.reserve("roll_b", "thread_blue").is_empty(),"Owned spool reserved by a second job")
	check(not ledger.can_reserve("roll_a", "thread_red") and not ledger.can_reserve("roll_b", "thread_blue"),"can_reserve ignored ownership")
	check(not ledger.reserve("roll_b", "thread_red").is_empty(),"Independent roll/spool pair could not reserve")
	check(event_count(ledger, "reserve") == 2,"Reserve events miscounted")


func test_no_cross_combining() -> void:
	var ledger := ledger_with([{"id": "blue_scrap", "meters": 0.8}, {"id": "red_scrap", "meters": 0.8}])
	check(not ledger.can_reserve("blue_scrap", "thread_blue"),"Undersized roll passed can_reserve")
	check(ledger.reserve("blue_scrap", "thread_blue").is_empty(),"Undersized roll reserved")
	check(ledger.reserve("red_scrap", "thread_blue").is_empty(),"Second undersized roll reserved")
	check(ledger.jobs.is_empty() and ledger.fabric("blue_scrap").meters == 0.8 and ledger.fabric("red_scrap").meters == 0.8,"Shortage combined different fabric batches")


func test_cut_conservation() -> void:
	var ledger := ledger_with([{"id": "roll", "meters": 6.0}])
	var job: Dictionary = ledger.reserve("roll", "thread_blue")
	var cut_m := float(job.estimate.cut_m)
	check(ledger.cut("ghost_job") == false,"Unknown job cut")
	check(ledger.cut(job.id),"Cut failed")
	var remaining := float(ledger.fabric("roll").meters)
	check(is_equal_approx(remaining, 6.0 - cut_m),"Cut deducted the wrong amount")
	check(is_equal_approx(remaining + float(job.consumed_fabric_m), 6.0),"Fabric conservation broken")
	check(is_equal_approx(float(job.consumed_fabric_m), float(job.net_cut_m) + float(job.remnant_m) + float(job.waste_m)),"Cut parts do not sum to the deduction")
	check(job.status == "cut","Cut status not set")
	check(ledger.remnants.size() == 1,"Cut remnant missing")
	var remnant: Dictionary = ledger.remnants[0]
	check(remnant.source_fabric_id == "roll" and remnant.fabric_id == "roll","Remnant source not recorded")
	check(remnant.location == "table" and remnant.width_m == 1.4,"Remnant fields wrong")
	check(is_equal_approx(remnant.meters, remnant.length_m) and is_equal_approx(remnant.meters, float(job.estimate.remnant_m)),"Remnant length wrong")
	var event_total: int = ledger.events.size()
	check(ledger.cut(job.id),"Duplicate cut rejected")
	check(ledger.fabric("roll").meters == remaining,"Duplicate cut deducted twice")
	check(ledger.remnants.size() == 1 and ledger.events.size() == event_total,"Duplicate cut repeated records or events")
	check(event_count(ledger, "cut") == 1,"Cut events miscounted")
	check(float(job.material_snapshot.meters) == 6.0,"Material snapshot mutated with the roll")


func test_sewing() -> void:
	var ledger := ledger_with([{"id": "roll", "meters": 6.0}])
	var job: Dictionary = ledger.reserve("roll", "thread_blue")
	check(not ledger.advance_sewing(job.id, 0.5),"Sewing advanced before cut")
	ledger.cut(job.id)
	var thread_m := float(job.estimate.thread_m)
	check(ledger.advance_sewing(job.id, 0.5),"Sewing advance failed")
	check(job.status == "sewing" and job.sew_progress == 0.5,"Sewing state wrong")
	check(is_equal_approx(float(job.consumed_thread_m), thread_m * 0.5),"Thread consumption wrong")
	check(is_equal_approx(float(ledger.thread("thread_blue").meters), 80.0 - thread_m * 0.5),"Spool conservation broken")
	var event_total: int = ledger.events.size()
	check(ledger.advance_sewing(job.id, 0.5),"Duplicate progress callback rejected")
	check(ledger.thread("thread_blue").meters == 80.0 - thread_m * 0.5 and ledger.events.size() == event_total,"Duplicate progress consumed or logged again")
	check(not ledger.advance_sewing(job.id, 0.4),"Progress regression accepted")
	check(not ledger.advance_sewing(job.id, 1.2),"Out-of-range progress accepted")
	check(not ledger.advance_sewing(job.id, NAN),"Nonfinite progress accepted")
	check(ledger.advance_sewing(job.id, 1.0),"Final advance failed")
	check(job.status == "sewn" and job.sew_progress == 1.0,"Sewn status not set")
	check(job.status != "completed","Job completed without a complete call")
	check(is_equal_approx(float(job.consumed_thread_m), thread_m),"Thread not fully consumed at completion progress")
	check(ledger.advance_sewing(job.id, 1.0),"Duplicate sewn callback rejected")
	check(not ledger.advance_sewing(job.id, 0.9),"Regression after sewn accepted")


func test_complete() -> void:
	var ledger := ledger_with([{"id": "roll", "meters": 6.0}])
	var job: Dictionary = ledger.reserve("roll", "thread_blue")
	ledger.cut(job.id)
	check(not ledger.complete(job.id, "apron_a"),"Complete allowed before sewn")
	ledger.advance_sewing(job.id, 1.0)
	check(not ledger.complete(job.id, ""),"Empty output id accepted")
	check(ledger.complete(job.id, "apron_a"),"Complete failed")
	check(job.status == "completed" and job.output_id == "apron_a","Completion state wrong")
	var event_total: int = ledger.events.size()
	check(ledger.complete(job.id, "apron_a"),"Repeated completion with same output rejected")
	check(ledger.events.size() == event_total,"Repeated completion repeated bookkeeping")
	check(not ledger.complete(job.id, "apron_b"),"Conflicting output id accepted")
	check(not ledger.cancel(job.id),"Completed work cancelled")
	var remaining := float(ledger.fabric("roll").meters)
	check(ledger.available_fabric("roll") == remaining,"Completed job still holds the roll")
	check(ledger.available_thread("thread_blue") > 0.0,"Completed job still holds the spool")
	check(not ledger.reserve("roll", "thread_blue").is_empty(),"Released roll/spool could not be reserved again")


func test_cancel_before_cut() -> void:
	var ledger := ledger_with([{"id": "roll", "meters": 6.0}])
	var job: Dictionary = ledger.reserve("roll", "thread_blue")
	check(ledger.cancel(job.id),"Cancel before cut failed")
	check(job.status == "cancelled","Cancel status wrong")
	check(ledger.fabric("roll").meters == 6.0 and ledger.thread("thread_blue").meters == 80.0,"Early cancel deducted stock")
	check(ledger.remnants.is_empty(),"Early cancel produced a remnant")
	var event_total: int = ledger.events.size()
	check(ledger.cancel(job.id),"Duplicate cancel rejected")
	check(ledger.events.size() == event_total,"Duplicate cancel repeated events")
	check(ledger.available_fabric("roll") == 6.0,"Cancelled job still holds the roll")
	check(not ledger.reserve("roll", "thread_blue").is_empty(),"Stock not reusable after cancel")


func test_cancel_after_cut() -> void:
	var ledger := ledger_with([{"id": "roll", "meters": 6.0}])
	var job: Dictionary = ledger.reserve("roll", "thread_blue")
	ledger.cut(job.id)
	ledger.advance_sewing(job.id, 0.5)
	var consumed_thread := float(job.consumed_thread_m)
	var remaining := float(ledger.fabric("roll").meters)
	var remnant_total: int = ledger.remnants.size()
	check(ledger.cancel(job.id),"Cancel after cut failed")
	check(job.status == "cancelled","Late cancel status wrong")
	check(float(ledger.fabric("roll").meters) == remaining,"Cancel restored the original roll")
	check(float(job.consumed_thread_m) == consumed_thread,"Cancel erased consumed thread")
	check(float(ledger.thread("thread_blue").meters) == 80.0 - consumed_thread,"Cancel refunded the spool")
	check(ledger.remnants.size() == remnant_total + 1,"Cut piece remnant missing")
	var piece: Dictionary = ledger.remnants.back()
	check(piece.kind == "cut_piece" and piece.location == "table","Cut piece remnant fields wrong")
	check(piece.source_fabric_id == "roll" and is_equal_approx(piece.meters, float(job.net_cut_m)),"Cut piece did not preserve source and net length")
	check(not (job.material_snapshot as Dictionary).is_empty(),"Material snapshot lost on cancel")
	var event_total: int = ledger.events.size()
	check(ledger.cancel(job.id),"Duplicate late cancel rejected")
	check(ledger.remnants.size() == remnant_total + 1 and ledger.events.size() == event_total,"Duplicate cancel repeated records or events")
	check(ledger.available_fabric("roll") == remaining,"Cancelled job still holds the roll")


func test_atomic_failures() -> void:
	var ledger := ledger_with([{"id": "roll", "meters": 6.0}])
	var job: Dictionary = ledger.reserve("roll", "thread_blue")
	var live: Dictionary = ledger.fabric("roll")
	live.meters = 0.5
	var event_total: int = ledger.events.size()
	check(not ledger.cut(job.id),"Cut accepted mutated insufficient quantity")
	check(job.status == "reserved" and ledger.remnants.is_empty() and ledger.events.size() == event_total,"Failed cut left partial changes")
	check(live.meters == 0.5,"Failed cut altered the roll")
	ledger.fabric_batches.clear()
	check(not ledger.cut(job.id),"Cut accepted a disappeared source")
	check(job.status == "reserved","Failed cut changed job status")
	check(ledger.cancel(job.id),"Cancel of un-cuttable job failed")
	var ledger2 := ledger_with([{"id": "roll2", "meters": 6.0}])
	var job2: Dictionary = ledger2.reserve("roll2", "thread_blue")
	ledger2.cut(job2.id)
	ledger2.thread_batches.clear()
	var progress := float(job2.sew_progress)
	event_total = ledger2.events.size()
	check(not ledger2.advance_sewing(job2.id, 0.5),"Sewing advanced with a disappeared spool")
	check(float(job2.sew_progress) == progress and ledger2.events.size() == event_total,"Failed sewing left partial changes")
