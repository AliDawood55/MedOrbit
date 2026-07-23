import re
import requests
import time


# amenity / healthcare tag values -> the app's internal clinic "type" vocabulary
# (VALID_CLINIC_TYPES in backend/src/routes/clinic.routes.js). This is a
# categorization/normalization step, not a data fabrication — the raw OSM tag
# value is always preserved alongside the normalized one.
TYPE_MAP = {
    "hospital": "hospital",
    "clinic": "clinic",
    "doctors": "clinic",
    "doctor": "clinic",
    "pharmacy": "pharmacy",
    "dentist": "dental",
    "laboratory": "laboratory",
    "centre": "clinic",
    "radiology": "radiology",
}


class OSMCollector:

    def __init__(self):

        self.places = []

        self.url = (
            "https://overpass-api.de/api/interpreter"
        )


    def fetch_healthcare(self, bbox=(32.18, 35.21, 32.26, 35.31)):

        south, west, north, east = bbox
        bbox_str = f"{south},{west},{north},{east}"

        query = f"""

        [out:json][timeout:180];


        (

        node
        ["amenity"~"^(clinic|hospital|doctors|pharmacy)$"]
        ({bbox_str});


        way
        ["amenity"~"^(clinic|hospital|doctors|pharmacy)$"]
        ({bbox_str});


        node
        ["healthcare"]
        ({bbox_str});


        way
        ["healthcare"]
        ({bbox_str});


        );


        out center;

        """



        for attempt in range(3):

            try:

                print(
                    f"Attempt {attempt+1}"
                )


                response = requests.post(

                    self.url,

                    data=query,

                    headers={
                        "User-Agent":
                        "MedOrbit-AI"
                    },

                    timeout=240
                )


                if response.status_code == 200:

                    data = response.json()

                    break


                print(
                    "Server:",
                    response.status_code
                )


            except Exception as e:

                print(
                    "Error:",
                    e
                )

                time.sleep(10)


        else:

            return []



        for element in data["elements"]:


            place = self.format_place(
                element
            )


            if place:

                self.places.append(
                    place
                )


        return self.remove_duplicates()



    def format_place(self, element):

        tags = element.get(
            "tags",
            {}
        )


        lat = element.get(
            "lat"
        )

        lon = element.get(
            "lon"
        )


        if not lat and "center" in element:

            lat = element["center"]["lat"]
            lon = element["center"]["lon"]


        if not lat:

            return None


        # Address: compose from whatever addr:* parts OSM actually has —
        # never a placeholder. None if nothing at all is present. Some OSM
        # records have a mistagged value that's literally the tag's own key
        # (e.g. addr:city="addr:city", seen on node 431927304) — guard
        # against that class of error generically rather than one node.
        def clean_addr(v):
            if not v or re.match(r"^addr:", v.strip(), re.IGNORECASE):
                return None
            return v

        addr_parts = [
            clean_addr(tags.get("addr:housenumber")),
            clean_addr(tags.get("addr:street")),
            clean_addr(tags.get("addr:city")),
        ]
        addr_parts = [p for p in addr_parts if p]
        address = ", ".join(addr_parts) if addr_parts else clean_addr(tags.get("addr:full"))

        amenity_raw = tags.get("amenity")
        healthcare_raw = tags.get("healthcare")
        type_normalized = (
            TYPE_MAP.get(amenity_raw)
            or TYPE_MAP.get(healthcare_raw)
        )

        osm_type = element.get("type")  # "node" | "way"
        osm_id = element.get("id")

        return {

            "osm_type": osm_type,
            "osm_id": osm_id,
            "osm_url": f"https://www.openstreetmap.org/{osm_type}/{osm_id}" if osm_type and osm_id else None,

            "name_ar": tags.get("name:ar"),
            "name_en": tags.get("name:en"),
            "name_raw": tags.get("name"),

            "latitude": lat,
            "longitude": lon,

            "address": address,

            "phone": tags.get("phone") or tags.get("contact:phone"),

            "type_raw_amenity": amenity_raw,
            "type_raw_healthcare": healthcare_raw,
            "type_normalized": type_normalized,

        }



    def remove_duplicates(self):

        result = {}

        for p in self.places:

            # OSM's own (element type, id) is the real unique key — two
            # distinct real-world places can legitimately share a coordinate
            # (e.g. a pharmacy inside a hospital building).
            key = (
                p["osm_type"],
                p["osm_id"]
            )

            result[key] = p


        return list(result.values())