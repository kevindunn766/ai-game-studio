# Shared noise-based PATCH scatter with density + scale falloff. This is the fix
# for "solo items, no falloff": instead of N uniform-random points, it samples a
# dense field of candidates, gates them through a low-frequency noise field so they
# clump into patches, and within each patch makes them BOTH denser and larger
# toward the centre.
#
# Returns an array of { pos: Vector3 (y=0), scale: float, yaw: float, f: float }
# where f is 0 at a patch edge .. 1 at a patch centre (use it for extra tint/shade).

static func patch(rng: RandomNumberGenerator, noise: FastNoiseLite,
		x0: float, x1: float, z0: float, z1: float,
		density: float, threshold: float, edge_prob: float,
		scale_min: float, scale_max: float,
		noise_ox: float, noise_oz: float) -> Array:
	var pts: Array = []
	var attempts: int = int(maxf(0.0, (x1 - x0) * (z1 - z0) * density))
	for i in range(attempts):
		var x: float = rng.randf_range(x0, x1)
		var z: float = rng.randf_range(z0, z1)
		var n: float = (noise.get_noise_2d(x + noise_ox, z + noise_oz) + 1.0) * 0.5
		if n < threshold:
			continue                                        # gap between patches
		var f: float = smoothstep(threshold, 1.0, n)        # 0 edge .. 1 centre
		if rng.randf() > edge_prob + (1.0 - edge_prob) * f:
			continue                                        # density falloff
		var sc: float = lerpf(scale_min, scale_max, f) * rng.randf_range(0.8, 1.2)  # scale falloff + jitter
		pts.append({ "pos": Vector3(x, 0.0, z), "scale": sc, "yaw": rng.randf() * TAU, "f": f })
	return pts
