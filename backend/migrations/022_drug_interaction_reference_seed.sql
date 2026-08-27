-- Curated minimum interaction reference data.
--
-- Evidence reviewed 2026-08-26:
--   * https://medlineplus.gov/druginfo/meds/a682277.html
--   * https://www.nhs.uk/medicines/warfarin/
--
-- This is deliberately a narrow safety backfill, not a substitute for a
-- maintained drug-interaction knowledge base. Keep existing curated entries
-- and only add missing aliases for the aspirin/warfarin interaction.

UPDATE medorbit.medications AS medication
SET known_interactions = COALESCE(medication.known_interactions, '{}'::jsonb)
    || jsonb_build_object(
        'Warfarin', COALESCE(
            medication.known_interactions -> 'Warfarin',
            to_jsonb('Severe - increased bleeding risk. Concomitant therapy may be intentional only under prescriber-directed monitoring; do not start or stop either medicine without consulting a clinician or pharmacist.'::text)
        ),
        'Warfarin Sodium', COALESCE(
            medication.known_interactions -> 'Warfarin Sodium',
            to_jsonb('Severe - increased bleeding risk. Concomitant therapy may be intentional only under prescriber-directed monitoring; do not start or stop either medicine without consulting a clinician or pharmacist.'::text)
        )
    )
WHERE lower(medication.name_en) = 'aspirin';

UPDATE medorbit.medications AS medication
SET known_interactions = COALESCE(medication.known_interactions, '{}'::jsonb)
    || jsonb_build_object(
        'Aspirin', COALESCE(
            medication.known_interactions -> 'Aspirin',
            to_jsonb('Severe - increased bleeding risk. Concomitant therapy may be intentional only under prescriber-directed monitoring; do not start or stop either medicine without consulting a clinician or pharmacist.'::text)
        ),
        'Acetylsalicylic Acid', COALESCE(
            medication.known_interactions -> 'Acetylsalicylic Acid',
            to_jsonb('Severe - increased bleeding risk. Concomitant therapy may be intentional only under prescriber-directed monitoring; do not start or stop either medicine without consulting a clinician or pharmacist.'::text)
        )
    )
WHERE lower(medication.name_en) = 'warfarin';

-- A fresh tracked schema has no application seed data. Add only these two
-- reference records when they are absent so the safety regression is present
-- in every environment, without duplicating records in existing databases.
INSERT INTO medorbit.medications (
    name_ar,
    name_en,
    generic_name,
    drug_class,
    active_ingredients,
    known_interactions,
    is_active
)
SELECT
    'أسبرين',
    'Aspirin',
    'Acetylsalicylic Acid',
    'Antiplatelet',
    ARRAY['Acetylsalicylic Acid'],
    jsonb_build_object(
        'Warfarin', 'Severe - increased bleeding risk. Concomitant therapy may be intentional only under prescriber-directed monitoring; do not start or stop either medicine without consulting a clinician or pharmacist.',
        'Warfarin Sodium', 'Severe - increased bleeding risk. Concomitant therapy may be intentional only under prescriber-directed monitoring; do not start or stop either medicine without consulting a clinician or pharmacist.'
    ),
    true
WHERE NOT EXISTS (
    SELECT 1 FROM medorbit.medications WHERE lower(name_en) = 'aspirin'
);

INSERT INTO medorbit.medications (
    name_ar,
    name_en,
    generic_name,
    drug_class,
    active_ingredients,
    known_interactions,
    is_active
)
SELECT
    'وارفارين',
    'Warfarin',
    'Warfarin Sodium',
    'Anticoagulant',
    ARRAY['Warfarin Sodium'],
    jsonb_build_object(
        'Aspirin', 'Severe - increased bleeding risk. Concomitant therapy may be intentional only under prescriber-directed monitoring; do not start or stop either medicine without consulting a clinician or pharmacist.',
        'Acetylsalicylic Acid', 'Severe - increased bleeding risk. Concomitant therapy may be intentional only under prescriber-directed monitoring; do not start or stop either medicine without consulting a clinician or pharmacist.'
    ),
    true
WHERE NOT EXISTS (
    SELECT 1 FROM medorbit.medications WHERE lower(name_en) = 'warfarin'
);
