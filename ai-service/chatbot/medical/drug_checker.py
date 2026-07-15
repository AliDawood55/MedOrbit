from typing import List, Dict

class DrugChecker:

    def check_interaction(self, drugs: List[Dict]):

        results = []

        for drug in drugs:
            interactions = drug.get("known_interactions", {})

            for other in drugs:
                if other["id"] == drug["id"]:
                    continue

                if other["id"] in interactions:
                    results.append({
                        "drug_1": drug["name_en"],
                        "drug_2": other["name_en"],
                        "severity": interactions[other["id"]]
                    })

        return results