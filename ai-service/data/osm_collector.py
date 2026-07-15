import requests
import time


class OSMCollector:

    def __init__(self):

        self.places = []

        self.url = (
            "https://overpass-api.de/api/interpreter"
        )


    def fetch_healthcare(self):


        query = """

        [out:json][timeout:180];


        (

        node
        ["amenity"~"clinic|hospital|doctors|pharmacy"]
        (32.15,35.15,32.30,35.35);


        way
        ["amenity"~"clinic|hospital|doctors|pharmacy"]
        (32.15,35.15,32.30,35.35);


        );


        out center;

        """



        for attempt in range(3):

            try:

                print(
                    f"🔄 Attempt {attempt+1}"
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


        return {

            "name":
            tags.get(
                "name",
                "Unknown"
            ),

            "latitude":
            lat,

            "longitude":
            lon,

            "address":
            tags.get(
                "addr:street",
                "N/A"
            ),

            "phone":
            tags.get(
                "phone"
            ),

            "type":
            tags.get(
                "amenity"
            )

        }



    def remove_duplicates(self):

        result = {}

        for p in self.places:

            key = (
                p["latitude"],
                p["longitude"]
            )

            result[key] = p


        return list(result.values())