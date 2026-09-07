import unittest

from score_references import edit_counts, mixed_units, score


class ReferenceScoringTests(unittest.TestCase):
    def test_embedded_english_keeps_word_boundaries(self):
        self.assertEqual(mixed_units("新的 base model"), ["新", "的", "base", "model"])
        self.assertEqual(edit_counts(mixed_units("base model"), mixed_units("base")), (1, 0, 0, 1))

    def test_substitution_insertion_deletion_and_empty_output(self):
        self.assertEqual(edit_counts(["a", "b", "c"], ["a", "x", "c"]), (1, 1, 0, 0))
        self.assertEqual(edit_counts(["a"], ["a", "b"]), (1, 0, 1, 0))
        self.assertEqual(edit_counts(["a", "b"], []), (2, 0, 0, 2))
        result = score([{"clip": "a", "text": "停止"}], [{"event": "clip", "clip": "a", "text": ""}])
        self.assertEqual(result["summary"]["deletions"], 2)
        self.assertEqual(result["summary"]["mixed_error_rate"], 1)
        self.assertEqual(result["summary"]["empty_output"], 1)

    def test_raw_script_errors_are_not_hidden_by_canonical_score(self):
        result = score([{"clip": "a", "text": "語音 model"}], [{"event": "clip", "clip": "a", "text": "语音 model"}])
        self.assertGreater(result["summary"]["raw_character_errors"], 0)
        self.assertEqual(result["summary"]["canonical_character_errors"], 0)

    def test_length_changing_script_phrase_keeps_raw_denominator(self):
        result = score([{"clip": "a", "text": "内存"}], [{"event": "clip", "clip": "a", "text": ""}])
        self.assertEqual(result["summary"]["raw_cer"], 1)
        self.assertEqual(result["summary"]["canonical_cer"], 1)

    def test_repeated_or_missing_results_cannot_hide_failed_clips(self):
        references = [{"clip": "a", "text": "a"}, {"clip": "b", "text": "b"}]
        duplicate = {"event": "clip", "clip": "a", "text": "a"}
        with self.assertRaises(ValueError):
            score(references, [duplicate, duplicate])
        with self.assertRaises(ValueError):
            score(references, [duplicate])

    def test_later_repetitions_do_not_inflate_accuracy(self):
        result = score([{"clip": "a", "text": "yes"}], [
            {"event": "clip", "clip": "a", "text": "", "repetition": 0},
            {"event": "clip", "clip": "a", "text": "yes", "repetition": 1},
        ])
        self.assertEqual(result["summary"]["mixed_error_rate"], 1)


if __name__ == "__main__":
    unittest.main()
