extends RefCounted
## Shared word wrapping for the mod's draw-based HUD panels.
##
## `break_long_words` splits a single word wider than the line, which the trinket
## reminder descriptions need; other panels keep whole words.

static func wrap(font: Font, text: String, font_size: int, max_width: float, break_long_words := false) -> Array[String]:
	var lines: Array[String] = []
	if font == null or text.is_empty() or max_width <= 0.0:
		return lines
	var current := ""
	for word in text.split(" ", false):
		var candidate := word if current.is_empty() else current + " " + word
		if font.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= max_width:
			current = candidate
			continue
		if not current.is_empty():
			lines.append(current)
		if not break_long_words or font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= max_width:
			current = word
			continue
		# Break a single word that is wider than the line.
		var chunk := ""
		for ch in word:
			var next := chunk + ch
			if not chunk.is_empty() and font.get_string_size(next, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > max_width:
				lines.append(chunk)
				chunk = ch
			else:
				chunk = next
		current = chunk
	if not current.is_empty():
		lines.append(current)
	return lines
