class_name Score
extends RefCounted
## 得分公式。后端 backend/Code.gs 的 computeScore 有同一份，
## 两边都用 backend/test/score_vectors.json 校验，改公式时两处和测试向量一起改。


static func compute(s: Dictionary) -> int:
	var base := int(s["kills"]) + int(s["level"]) * 100 + int(s["bosses"]) * 1000
	if bool(s["won"]):
		base += 5000 + maxi(0, 900 - int(s["seconds"])) * 10
	return base
