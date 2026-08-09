from __future__ import annotations

import importlib.util
import json
import sys
import tempfile
import unittest
from collections import defaultdict
from pathlib import Path


DATA_DIR = Path(__file__).resolve().parents[1] / "data"
sys.path.insert(0, str(DATA_DIR))

from build_ml_dataset import assert_no_group_leakage, assign_group_splits, build_samples
from facility_pipeline import (
    CITY_BBOX,
    GREATER_NABLUS_BBOX,
    _cross_record_quality,
    canonical_from_official,
    canonical_from_osm,
    canonical_type,
    classify_city_scope,
    classify_duplicate,
    deduplicate,
    duplicate_features,
    haversine_meters,
    in_bbox,
    merge_records,
    validate_record,
)
from osm_collector import OSMCollector
from osm_transform import (
    normalize_arabic_key,
    normalize_digits,
    normalize_english_key,
    normalize_phone,
    normalize_specialties,
    normalize_url,
    resolve_names,
)
from save_to_db import plan_ingestion
from train_facility_classifier import train_candidate


def osm_record(**overrides):
    base = {
        "osm_type": "node",
        "osm_id": 1,
        "osm_url": "https://www.openstreetmap.org/node/1",
        "source_record_id": "node:1",
        "source_url": "https://www.openstreetmap.org/node/1",
        "source_type": "openstreetmap",
        "source_name": "OpenStreetMap contributors",
        "name_ar": "مستشفى الاختبار",
        "name_en": "Test Hospital",
        "name_raw": "Test Hospital",
        "latitude": 32.22,
        "longitude": 35.25,
        "type_raw_amenity": "hospital",
        "type_raw_healthcare": None,
        "type_normalized": "hospital",
        "phone": "+970 9 123 4567",
        "address": "Nablus",
        "collected_at": "2026-08-09T00:00:00+00:00",
    }
    base.update(overrides)
    return base


class NormalizationTests(unittest.TestCase):
    def test_arabic_normalization(self):
        self.assertEqual(normalize_arabic_key("  مُسْتَشْفَى  الإِسْرَاء،  "), "مستشفي الاسراء")

    def test_arabic_and_latin_digits(self):
        self.assertEqual(normalize_digits("٠١٢ ۳۴"), "012 34")

    def test_english_normalization_and_abbreviations(self):
        self.assertEqual(normalize_english_key(" Dr.  Hope Med. Ctr! "), "doctor hope medical center")

    def test_phone_normalization(self):
        self.assertEqual(normalize_phone("٠٩-٢٣٤ ٥٦٧٨"), "+97092345678")
        self.assertEqual(normalize_phone("00970 9 234 5678"), "+97092345678")

    def test_url_validation(self):
        self.assertEqual(normalize_url("nnuh.org/en/"), "https://nnuh.org/en")
        self.assertIsNone(normalize_url("not a url"))

    def test_name_resolution_preserves_display(self):
        self.assertEqual(resolve_names(None, "NNUH", "مستشفى النجاح"), ("مستشفى النجاح", "NNUH"))


class GeographyAndTaxonomyTests(unittest.TestCase):
    def test_coordinate_and_bbox_validation(self):
        self.assertTrue(in_bbox(32.22, 35.25, CITY_BBOX))
        self.assertEqual(classify_city_scope(32.22, 35.25), "nablus_city")
        self.assertEqual(classify_city_scope(32.17, 35.19), "greater_nablus")
        self.assertEqual(classify_city_scope(31.9, 35.25), "outside_primary_scope")
        self.assertEqual(classify_city_scope(None, None), "needs_geolocation")
        self.assertTrue(in_bbox(32.17, 35.19, GREATER_NABLUS_BBOX))

    def test_distance_logic(self):
        self.assertAlmostEqual(haversine_meters(32.22, 35.25, 32.22, 35.25), 0.0)
        self.assertGreater(haversine_meters(32.22, 35.25, 32.23, 35.25), 1000)

    def test_facility_type_mapping_and_unknown(self):
        self.assertEqual(canonical_type("dentist", None), "dental")
        self.assertEqual(canonical_type(None, "physiotherapist"), "rehabilitation")
        self.assertIsNone(canonical_type("restaurant", None))

    def test_specialty_mapping_and_unknown(self):
        valid, unknown = normalize_specialties("cardiology;pediatrician;dentist;made_up_specialty")
        self.assertEqual(valid, ["cardiology", "pediatrics", "dentistry"])
        self.assertEqual(unknown, ["made_up_specialty"])

    def test_invalid_coordinates_and_missing_fields(self):
        record = canonical_from_osm(osm_record(latitude=95, longitude=0, name_ar=None, name_en="Only English"))
        record["canonical_id"] = "fac_test"
        codes = {issue["code"] for issue in validate_record(record)}
        self.assertIn("invalid_latitude", codes)
        self.assertIn("arabic_name_contains_no_arabic", codes)

    def test_unknown_category_is_error(self):
        record = canonical_from_osm(osm_record(type_raw_amenity="unknown", type_normalized=None))
        record["canonical_id"] = "fac_unknown"
        issues = validate_record(record)
        self.assertTrue(any(issue["code"] == "unknown_category" and issue["severity"] == "error" for issue in issues))


class DeduplicationAndProvenanceTests(unittest.TestCase):
    def test_exact_duplicate_by_osm_identity(self):
        left = canonical_from_osm(osm_record())
        right = canonical_from_osm(osm_record(name_en="Test Hospital Updated"))
        classification, _ = classify_duplicate(duplicate_features(left, right))
        self.assertEqual(classification, "exact")

    def test_probable_duplicate_by_name_and_distance(self):
        left = canonical_from_osm(osm_record(osm_id=1, source_record_id="node:1"))
        right = canonical_from_osm(osm_record(osm_id=2, source_record_id="node:2", latitude=32.2207, phone="092222222"))
        features = duplicate_features(left, right)
        classification, _ = classify_duplicate(features)
        self.assertEqual(classification, "probable")
        self.assertGreater(features["distance_meters"], 25)

    def test_distinct_same_coordinate_with_different_name_and_type(self):
        left = canonical_from_osm(osm_record())
        right = canonical_from_osm(osm_record(osm_id=2, source_record_id="node:2", name_ar="صيدلية أخرى", name_en="Other Pharmacy", type_raw_amenity="pharmacy", type_normalized="pharmacy"))
        classification, _ = classify_duplicate(duplicate_features(left, right))
        self.assertEqual(classification, "distinct")

    def test_same_phone_far_apart_is_reviewed_not_merged(self):
        left = canonical_from_osm(osm_record(osm_id=1, source_record_id="node:1"))
        right = canonical_from_osm(osm_record(osm_id=2, source_record_id="node:2", latitude=32.245))
        classification, _ = classify_duplicate(duplicate_features(left, right))
        self.assertEqual(classification, "possible")
        canonical, candidates, _ = deduplicate([left, right])
        self.assertEqual(len(canonical), 2)
        self.assertEqual(candidates[0]["classification"], "possible")

    def test_source_provenance_and_verified_cross_validation(self):
        osm = canonical_from_osm(osm_record())
        official = canonical_from_official({
            "canonical_name_ar": "مستشفى الاختبار",
            "canonical_name_en": "Test Hospital",
            "facility_type": "hospital",
            "source_url": "https://official.example/hospital",
            "source_type": "official_hospital",
            "source_name": "Official hospital",
            "source_record_id": "official-1",
            "match_osm_ids": ["node:1"],
        })
        canonical, candidates, conflicts = deduplicate([osm, official])
        self.assertEqual(len(canonical), 1)
        self.assertEqual(canonical[0]["verification_status"], "verified")
        self.assertEqual(len(canonical[0]["source_evidence"]), 2)
        self.assertFalse(candidates)
        self.assertTrue(canonical[0]["field_provenance"])

    def test_conflict_preserved_and_authoritative_value_selected(self):
        osm = canonical_from_osm(osm_record())
        official = canonical_from_official({
            "canonical_name_ar": "مستشفى الاختبار الحكومي",
            "canonical_name_en": "Test Governmental Hospital",
            "facility_type": "hospital",
            "ownership": "government",
            "source_url": "https://gov.example/hospital",
            "source_type": "government_directory",
            "source_name": "Government",
            "source_record_id": "gov-1",
            "match_osm_ids": ["node:1"],
        })
        merged, conflicts = merge_records([osm, official])
        self.assertEqual(merged["canonical_name_en"], "Test Governmental Hospital")
        self.assertTrue(any(conflict["field"] == "canonical_name_en" for conflict in conflicts))

    def test_missing_geolocation_placeholder_is_not_a_conflict(self):
        osm = canonical_from_osm(osm_record())
        official = canonical_from_official({
            "canonical_name_en": "Test Hospital",
            "facility_type": "hospital",
            "source_url": "https://official.example/hospital",
            "source_type": "official_hospital",
            "source_name": "Official hospital",
            "source_record_id": "official-no-coordinates",
            "match_osm_ids": ["node:1"],
        })
        merged, conflicts = merge_records([osm, official])
        self.assertEqual(merged["city_scope"], "nablus_city")
        self.assertFalse(any(conflict["field"] == "city_scope" for conflict in conflicts))

    def test_duplicate_osm_and_phone_overuse_quality(self):
        records = []
        for index in range(3):
            record = canonical_from_osm(osm_record(osm_id=index + 1, source_record_id=f"node:{index + 1}", name_en=f"Facility {index}", phone="092345678"))
            record["canonical_id"] = f"fac_{index}"
            records.append(record)
        records[1]["osm_id"] = records[0]["osm_id"]
        records[1]["osm_type"] = records[0]["osm_type"]
        codes = {issue["code"] for issue in _cross_record_quality(records)}
        self.assertIn("duplicate_osm_id", codes)
        self.assertIn("phone_overuse", codes)

    def test_collector_preserves_raw_tags_and_relations(self):
        query = OSMCollector.build_query(CITY_BBOX)
        self.assertIn("relation", query)
        self.assertIn("dentist", query)
        place = OSMCollector.format_place({"type": "node", "id": 7, "lat": 32.2, "lon": 35.2, "tags": {"amenity": "dentist", "name": "Dental"}})
        self.assertEqual(place["raw_source_payload"]["tags"]["amenity"], "dentist")
        self.assertEqual(place["source_record_id"], "node:7")


class IngestionPlanningTests(unittest.TestCase):
    def test_insert_then_second_plan_is_idempotent(self):
        candidate = canonical_from_osm(osm_record())
        candidate["canonical_id"] = "fac_insert"
        first = plan_ingestion([candidate], [])
        self.assertEqual(first["counts"]["insert"], 1)
        existing = [{
            "id": "00000000-0000-0000-0000-000000000001",
            "name_ar": candidate["canonical_name_ar"],
            "name_en": candidate["canonical_name_en"],
            "address_ar": candidate["address_ar"] or "",
            "address_en": candidate["address_en"] or "",
            "city": "Nablus",
            "region": None,
            "latitude": candidate["latitude"],
            "longitude": candidate["longitude"],
            "phone": candidate["phone_numbers"][0],
            "email": None,
            "website": None,
            "type": "hospital",
            "services": [],
            "is_active": True,
            "verification_status": "pending",
        }]
        second = plan_ingestion([candidate], existing)
        self.assertEqual(second["counts"]["insert"], 0)
        self.assertEqual(second["counts"]["update"], 0)
        self.assertEqual(second["counts"]["unchanged"], 1)

    def test_existing_populated_fields_are_not_overwritten(self):
        candidate = canonical_from_osm(osm_record(address="New address"))
        candidate["canonical_id"] = "fac_existing"
        existing = [{
            "id": "00000000-0000-0000-0000-000000000002",
            "name_ar": candidate["canonical_name_ar"], "name_en": candidate["canonical_name_en"],
            "address_ar": "Trusted address", "address_en": "Trusted address", "city": "Nablus", "region": None,
            "latitude": candidate["latitude"], "longitude": candidate["longitude"], "phone": "+97099999999",
            "email": "trusted@example.org", "website": "https://trusted.example.org", "type": "hospital",
            "services": ["trusted_service"], "is_active": True, "verification_status": "verified",
        }]
        plan = plan_ingestion([candidate], existing)
        action = plan["actions"][0]
        self.assertNotIn("address_ar", action["updates"])
        self.assertNotIn("phone", action["updates"])
        self.assertNotIn("website", action["updates"])
        self.assertEqual(existing[0]["verification_status"], "verified")


class MlDatasetTests(unittest.TestCase):
    def _records(self):
        records = []
        for label in ("hospital", "clinic", "pharmacy"):
            for index in range(10):
                records.append({
                    "canonical_id": f"{label}-{index}",
                    "canonical_name_ar": f"{label} {index}",
                    "canonical_name_en": f"{label} facility {index}",
                    "aliases": [f"{label} alias {index}"],
                    "facility_type": label,
                    "verification_status": "probable",
                    "city_scope": "nablus_city",
                })
        return records

    def test_group_aware_split_has_no_leakage(self):
        samples = build_samples(self._records(), seed=42)
        assert_no_group_leakage(samples)
        assignments = defaultdict(set)
        for sample in samples:
            assignments[sample["group_id"]].add(sample["split"])
        self.assertTrue(all(len(splits) == 1 for splits in assignments.values()))

    def test_split_seed_is_deterministic(self):
        first = assign_group_splits(self._records(), seed=7)
        second = assign_group_splits(list(reversed(self._records())), seed=7)
        third = assign_group_splits(self._records(), seed=8)
        self.assertEqual(first, second)
        self.assertNotEqual(first, third)

    @unittest.skipUnless(importlib.util.find_spec("sklearn") and importlib.util.find_spec("joblib"), "scikit-learn/joblib not installed")
    def test_model_serialization_loading_and_inference_schema(self):
        import joblib

        rows = []
        for label, token in (("hospital", "hospital مستشفى"), ("clinic", "clinic عيادة"), ("pharmacy", "pharmacy صيدلية")):
            for index in range(8):
                rows.append({"text": f"{token} {index}", "label": label})
        model = train_candidate(rows, c_value=1.0, seed=42)
        with tempfile.TemporaryDirectory() as temp_dir:
            path = Path(temp_dir) / "model.joblib"
            joblib.dump(model, path)
            loaded = joblib.load(path)
            prediction = loaded.predict(["hospital example"])
            self.assertEqual(prediction.shape, (1,))
            self.assertIn(prediction[0], {"hospital", "clinic", "pharmacy"})
            schema = {"input": {"text": "string"}, "output": {"facility_type": list(loaded.classes_)}}
            self.assertIn("text", schema["input"])
            self.assertIn(prediction[0], schema["output"]["facility_type"])


if __name__ == "__main__":
    unittest.main()
