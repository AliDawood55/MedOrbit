"""Train and evaluate a guarded facility-type metadata classifier baseline."""

from __future__ import annotations

import argparse
import csv
import json
import platform
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any

from facility_pipeline import utc_now


HERE = Path(__file__).resolve().parent
DEFAULT_DATASET = HERE / "ml" / "nablus_facility_type"
DEFAULT_OUTPUT = DEFAULT_DATASET / "model_v1"
MIN_GROUPS_PER_CLASS = 8
MIN_CLASSES = 3


def load_split(path: Path) -> list[dict[str, str]]:
    with path.open(newline="", encoding="utf-8-sig") as handle:
        return list(csv.DictReader(handle))


def eligible_labels(rows: list[dict[str, str]], minimum: int = MIN_GROUPS_PER_CLASS) -> tuple[list[str], dict[str, int]]:
    groups: dict[str, set[str]] = defaultdict(set)
    for row in rows:
        groups[row["label"]].add(row["group_id"])
    counts = dict(sorted((label, len(values)) for label, values in groups.items()))
    return sorted(label for label, count in counts.items() if count >= minimum), counts


def training_decision(all_rows: list[dict[str, str]], labels: list[str]) -> tuple[bool, list[str]]:
    reasons = []
    if len(labels) < MIN_CLASSES:
        reasons.append(f"Only {len(labels)} classes have at least {MIN_GROUPS_PER_CLASS} canonical facilities; {MIN_CLASSES} required")
    for split in ("train", "validation", "test"):
        present = {row["label"] for row in all_rows if row["split"] == split and row["label"] in labels}
        missing = sorted(set(labels) - present)
        if missing:
            reasons.append(f"{split} split lacks eligible classes: {missing}")
    return not reasons, reasons


RULE_KEYWORDS = {
    "hospital": ("hospital", "مستشفى", "مشفى"),
    "pharmacy": ("pharmacy", "صيدلية", "صيدليه"),
    "dental": ("dental", "dentist", "اسنان", "أسنان"),
    "laboratory": ("laboratory", "laboratories", " lab ", "مختبر", "مختبرات"),
    "imaging": ("radiology", "imaging", "اشعة", "أشعة"),
    "rehabilitation": ("physiotherapy", "rehabilitation", "علاج طبيعي", "تأهيل"),
    "medical_center": ("medical center", "medical centre", "مركز طبي"),
    "health_center": ("health center", "health centre", "مركز صحي"),
    "clinic": ("clinic", "doctor", "عيادة", "دكتور"),
}


def deterministic_predict(text: str, labels: list[str], fallback: str) -> str:
    padded = f" {text.casefold()} "
    for label, keywords in RULE_KEYWORDS.items():
        if label in labels and any(keyword in padded for keyword in keywords):
            return label
    return fallback


def evaluate_predictions(y_true, y_pred, labels: list[str]) -> dict[str, Any]:
    from sklearn.metrics import accuracy_score, classification_report, confusion_matrix, precision_recall_fscore_support

    precision, recall, f1, _ = precision_recall_fscore_support(y_true, y_pred, average="macro", zero_division=0)
    return {
        "accuracy": float(accuracy_score(y_true, y_pred)),
        "macro_precision": float(precision),
        "macro_recall": float(recall),
        "macro_f1": float(f1),
        "per_class": classification_report(y_true, y_pred, labels=labels, output_dict=True, zero_division=0),
        "confusion_matrix": {
            "labels": labels,
            "matrix": confusion_matrix(y_true, y_pred, labels=labels).tolist(),
        },
    }


def train_candidate(train_rows: list[dict[str, str]], c_value: float, seed: int):
    from sklearn.feature_extraction.text import TfidfVectorizer
    from sklearn.linear_model import LogisticRegression
    from sklearn.pipeline import Pipeline

    model = Pipeline([
        ("vectorizer", TfidfVectorizer(analyzer="char_wb", ngram_range=(2, 5), min_df=1, sublinear_tf=True)),
        ("classifier", LogisticRegression(C=c_value, class_weight="balanced", max_iter=2000, random_state=seed)),
    ])
    model.fit([row["text"] for row in train_rows], [row["label"] for row in train_rows])
    return model


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dataset-dir", type=Path, default=DEFAULT_DATASET)
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--refit-train-validation", action="store_true")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    manifest = json.loads((args.dataset_dir / "dataset_manifest.json").read_text(encoding="utf-8"))
    rows_by_split = {split: load_split(args.dataset_dir / f"{split}.csv") for split in ("train", "validation", "test")}
    all_rows = [row for rows in rows_by_split.values() for row in rows]
    labels, class_group_counts = eligible_labels(all_rows)
    allowed, reasons = training_decision(all_rows, labels)
    excluded_labels = sorted(set(class_group_counts) - set(labels))
    decision = {
        "created_at": utc_now(),
        "trained": allowed,
        "task": "facility_type_classification_from_public_facility_names",
        "dataset_version": manifest["dataset_version"],
        "eligible_labels": labels,
        "excluded_underrepresented_labels": excluded_labels,
        "class_group_counts": class_group_counts,
        "minimum_groups_per_class": MIN_GROUPS_PER_CLASS,
        "reasons": reasons,
        "clinical_use": False,
        "notice": "Facility metadata classifier only; not for diagnosis, treatment, triage, or clinical reasoning.",
    }
    args.output_dir.mkdir(parents=True, exist_ok=True)
    (args.output_dir / "training_decision.json").write_text(json.dumps(decision, ensure_ascii=False, indent=2, sort_keys=True), encoding="utf-8")
    if not allowed:
        print(json.dumps(decision, ensure_ascii=False, indent=2, sort_keys=True))
        return

    try:
        import joblib
        import sklearn
    except ImportError as exc:
        raise SystemExit(f"Training dependencies unavailable: {exc}") from exc

    filtered = {
        split: [row for row in rows if row["label"] in labels]
        for split, rows in rows_by_split.items()
    }
    seed = int(manifest["random_seed"])
    validation_results = []
    best_model = None
    best_score = -1.0
    best_c = None
    for c_value in (0.5, 1.0, 2.0, 4.0):
        candidate = train_candidate(filtered["train"], c_value, seed)
        predictions = candidate.predict([row["text"] for row in filtered["validation"]])
        metrics = evaluate_predictions([row["label"] for row in filtered["validation"]], predictions, labels)
        validation_results.append({"C": c_value, "metrics": metrics})
        if metrics["macro_f1"] > best_score:
            best_model, best_score, best_c = candidate, metrics["macro_f1"], c_value

    test_true = [row["label"] for row in filtered["test"]]
    test_pred = best_model.predict([row["text"] for row in filtered["test"]])
    test_metrics = evaluate_predictions(test_true, test_pred, labels)
    fallback = Counter(row["label"] for row in filtered["train"]).most_common(1)[0][0]
    rules_pred = [deterministic_predict(row["text"], labels, fallback) for row in filtered["test"]]
    rules_metrics = evaluate_predictions(test_true, rules_pred, labels)

    production_model = best_model
    production_fit = "train_only"
    if args.refit_train_validation:
        production_model = train_candidate(filtered["train"] + filtered["validation"], best_c, seed)
        production_fit = "train_plus_validation_after_frozen_test_evaluation"

    joblib.dump(production_model, args.output_dir / "facility_classifier.joblib")
    joblib.dump(production_model.named_steps["vectorizer"], args.output_dir / "facility_vectorizer.joblib")
    joblib.dump(production_model.named_steps["classifier"], args.output_dir / "facility_classifier_model.joblib")
    (args.output_dir / "label_encoder.json").write_text(json.dumps({"classes": labels}, indent=2), encoding="utf-8")
    feature_schema = {
        "input": {"text": "non-empty UTF-8 facility name or alias"},
        "output": {"facility_type": labels},
        "normalization": "TfidfVectorizer char_wb 2-5 grams; no clinical text",
    }
    (args.output_dir / "feature_schema.json").write_text(json.dumps(feature_schema, ensure_ascii=False, indent=2, sort_keys=True), encoding="utf-8")
    metadata = {
        "model_version": "nablus-facility-type-v1",
        "dataset_version": manifest["dataset_version"],
        "created_at": utc_now(),
        "task": "facility_type_classification",
        "features": feature_schema,
        "classes": labels,
        "train_count": len(filtered["train"]),
        "validation_count": len(filtered["validation"]),
        "test_count": len(filtered["test"]),
        "random_seed": seed,
        "training_configuration": {
            "model": "TF-IDF char_wb + LogisticRegression",
            "candidate_C": [0.5, 1.0, 2.0, 4.0],
            "selected_C": best_c,
            "class_weight": "balanced",
            "production_fit": production_fit,
        },
        "validation_candidates": validation_results,
        "test_metrics": test_metrics,
        "deterministic_rules_test_metrics": rules_metrics,
        "known_limitations": [
            "Labels are primarily derived from OSM metadata and may contain source errors.",
            "Underrepresented facility types are excluded rather than guessed.",
            "The model is limited to facility metadata and must never be used for diagnosis or treatment.",
        ],
        "runtime": {"python": platform.python_version(), "scikit_learn": sklearn.__version__, "joblib": joblib.__version__},
    }
    (args.output_dir / "model_metadata.json").write_text(json.dumps(metadata, ensure_ascii=False, indent=2, sort_keys=True), encoding="utf-8")
    print(json.dumps(metadata, ensure_ascii=False, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
