import psycopg2
from osm_collector import OSMCollector
from osm_transform import process_place



conn = psycopg2.connect(

    dbname="medorbit",
    user="postgres",
    password="052963",
    host="localhost",
    port=5432

)


cursor = conn.cursor()



collector = OSMCollector()


raw_places = collector.fetch_healthcare()

places = [
    r for r in
    (process_place(p) for p in raw_places)
    if r is not None
]



print(
    f"Collected {len(raw_places)} places, {len(places)} with a usable name"
)



if not places:

    print(
        "No data collected"
    )

    cursor.close()
    conn.close()

    exit()



inserted = 0



for p in places:

    # Never fabricate an address — blank ('' ) if OSM had none, address_ar/
    # address_en are NOT NULL on this table so a real NULL isn't an option.
    address = p["address"] or ""


    cursor.execute(
        """

        INSERT INTO medorbit.clinics
        (
            name_ar,
            name_en,
            address_ar,
            address_en,
            city,
            latitude,
            longitude,
            phone,
            type,
            services,
            is_active,
            verification_status
        )

        SELECT %s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s
        WHERE NOT EXISTS (
            SELECT 1 FROM medorbit.clinics
            WHERE latitude = %s AND longitude = %s
        )

        """,

        (

            p["name_ar"],
            p["name_en"],

            address,
            address,

            "Nablus",

            p["lat"],
            p["lng"],

            p["phone"],

            p["type"],

            [p["type"]]
            if p["type"]
            else [],

            True,

            "pending",

            p["lat"],
            p["lng"],

        )

    )


    inserted += cursor.rowcount



conn.commit()


cursor.close()
conn.close()



print(
    f"Inserted {inserted} new clinics ({len(places) - inserted} already existed at that coordinate)"
)

print(
    "Database updated successfully"
)