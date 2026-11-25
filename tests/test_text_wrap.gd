extends "test_runner.gd"
## Unit tests for the shared HUD word wrap (core/text_wrap.gd).

const TextWrap = preload("../core/text_wrap.gd")


func test_missing_inputs_return_no_lines() -> void:
	assert_empty(TextWrap.wrap(null, "abc", 8, 100.0))
	assert_empty(TextWrap.wrap(ThemeDB.fallback_font, "", 8, 100.0))
	assert_empty(TextWrap.wrap(ThemeDB.fallback_font, "abc", 8, 0.0))


func test_wraps_on_word_boundaries() -> void:
	var lines := TextWrap.wrap(ThemeDB.fallback_font, "one two three four five six", 16, 60.0)
	assert_true(lines.size() > 1, "long text wraps")
	for line in lines:
		assert_false(str(line).begins_with(" "), "no leading spaces")
	assert_eq(" ".join(lines), "one two three four five six", "words are preserved")


func test_long_word_is_only_split_when_requested() -> void:
	var word := "supercalifragilisticexpialidocious"
	var kept := TextWrap.wrap(ThemeDB.fallback_font, word, 16, 20.0)
	assert_eq(kept.size(), 1, "a long word stays whole by default")
	assert_eq(str(kept[0]), word)
	var split := TextWrap.wrap(ThemeDB.fallback_font, word, 16, 20.0, true)
	assert_true(split.size() > 1, "break_long_words splits it")
	assert_eq("".join(split), word, "no characters are lost")
