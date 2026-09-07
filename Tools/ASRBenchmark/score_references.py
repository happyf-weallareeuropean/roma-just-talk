"""Score independent human references; never infer a reference from an ASR output."""
import argparse
import json
import re
import unicodedata
from pathlib import Path

from opencc import OpenCC

CONVERTER = OpenCC("s2twp")


def text_form(text, canonical=True):
    text = unicodedata.normalize("NFKC", text).lower()
    return CONVERTER.convert(text) if canonical else text


def characters(text, canonical=True):
    return [c for c in text_form(text, canonical)
            if not unicodedata.category(c).startswith(("P", "Z", "C"))]


def mixed_units(text):
    # Preserve spaces until tokenization: "base model" must remain two words.
    return re.findall(r"[a-z]+(?:\d+)?|\d+(?:\.\d+)?|[^\W_]", text_form(text))


def edit_counts(reference, hypothesis):
    """Minimum edit distance and a deterministic S/I/D decomposition."""
    row = [(i, 0, i, 0) for i in range(len(hypothesis) + 1)]
    for i, left in enumerate(reference, 1):
        following = [(i, 0, 0, i)]
        for j, right in enumerate(hypothesis, 1):
            if left == right:
                following.append(row[j - 1])
                continue
            substitution, insertion, deletion = row[j - 1], following[-1], row[j]
            following.append(min(
                (substitution[0] + 1, substitution[1] + 1, substitution[2], substitution[3]),
                (insertion[0] + 1, insertion[1], insertion[2] + 1, insertion[3]),
                (deletion[0] + 1, deletion[1], deletion[2], deletion[3] + 1),
            ))
        row = following
    return row[-1]


def score(references, events):
    names = [r["clip"] for r in references]
    if len(names) != len(set(names)):
        raise ValueError("Duplicate reference clip")
    references_by_name = {r["clip"]: r for r in references}
    clips = [e for e in events if e.get("event") == "clip" and e.get("repetition", 0) == 0]
    event_names = [e["clip"] for e in clips]
    if len(event_names) != len(set(event_names)) or set(event_names) != set(names):
        raise ValueError("Every reference needs exactly one first-repetition result")
    if not clips:
        raise ValueError("No reference clips")
    rows = []
    for event in clips:
        reference = references_by_name[event["clip"]]["text"]
        hypothesis = event["text"]
        units = mixed_units(reference)
        errors, substitutions, insertions, deletions = edit_counts(units, mixed_units(hypothesis))
        rows.append({
            "clip": event["clip"], "reference": reference, "hypothesis": hypothesis,
            "reference_units": len(units), "errors": errors, "substitutions": substitutions,
            "insertions": insertions, "deletions": deletions,
            "reference_characters": len(characters(reference)),
            "raw_reference_characters": len(characters(reference, False)),
            "raw_character_errors": edit_counts(characters(reference, False), characters(hypothesis, False))[0],
            "canonical_character_errors": edit_counts(characters(reference), characters(hypothesis))[0],
            "empty_output": not bool(hypothesis.strip()),
            "exact_match": units == mixed_units(hypothesis),
        })
    totals = {key: sum(row[key] for row in rows) for key in (
        "reference_units", "errors", "substitutions", "insertions", "deletions",
        "reference_characters", "raw_reference_characters", "raw_character_errors", "canonical_character_errors",
        "empty_output", "exact_match",
    )}
    totals["clips"] = len(rows)
    for name, numerator, denominator in (
        ("mixed_error_rate", "errors", "reference_units"),
        ("raw_cer", "raw_character_errors", "raw_reference_characters"),
        ("canonical_cer", "canonical_character_errors", "reference_characters"),
    ):
        totals[name] = totals[numerator] / totals[denominator] if totals[denominator] else None
    return {"summary": totals, "normalization": {
        "common": "NFKC, lowercase; ignore punctuation and spacing for CER",
        "canonical": "OpenCC s2twp script and Taiwan phrase normalization; raw CER retained separately",
        "mixed_units": "Han characters, Latin words, numeric tokens; not a general English WER",
        "repetition": "First only; all reference clips required, including empty results",
    }, "clips": rows}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("references", type=Path)
    parser.add_argument("events", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    events = []
    for line in args.events.read_text().splitlines():
        try:
            events.append(json.loads(line))
        except json.JSONDecodeError:
            continue  # Native SDKs may also write diagnostic lines to stdout.
    result = score(json.loads(args.references.read_text()), events)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps(result["summary"]))


if __name__ == "__main__":
    main()
