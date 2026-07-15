import psycopg2
from osm_collector import OSMCollector



conn = psycopg2.connect(

    dbname="medorbit",
    user="postgres",
    password="052963",
    host="localhost",
    port=5432

)


cursor = conn.cursor()



collector = OSMCollector()


places = collector.fetch_healthcare()



print(
    f"✅ Collected {len(places)} places"
)



if not places:

    print(
        "❌ No data collected"
    )

    cursor.close()
    conn.close()

    exit()



inserted = 0



for p in places:


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
            services,
            is_active,
            verification_status
        )

        VALUES
        (
            %s,%s,%s,%s,%s,
            %s,%s,%s,%s,%s,%s
        )

        ON CONFLICT DO NOTHING

        """,

        (

            p["name"],
            p["name"],

            p["address"],
            p["address"],

            "Nablus",

            p["latitude"],
            p["longitude"],

            p["phone"],

            [p["type"]]
            if p["type"]
            else [],

            True,

            "pending"

        )

    )


    inserted += 1



conn.commit()


cursor.close()
conn.close()



print(
    f"✅ Inserted {inserted} clinics"
)

print(
    "✅ Database updated successfully"
)