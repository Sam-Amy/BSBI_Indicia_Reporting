
-- Query used for reporting BSBI-related indicia occurrences

-- For convenience a temporary view is used (this can be still created by accounts with only read permission) which (as it's temporary) is dropped automatically once the session closes.

-- Run this from the command-line psql utility, as I had problems when trying to use the pgAdmin front end, though things may have improved since then

CREATE TEMP VIEW v1 AS
SELECT 
o.id AS occurrence_id,
o.sample_id,
o.parent_sample_id, -- for list-entered records with precise grid-refs the *useful* sample is the parent one
o.survey_id,
surveys.title AS survey_title,

o.website_id,
o.input_form, -- needed if want to link back to the record
      
--(snf.website_title || ' | ' || snf.survey_title || coalesce(' | ' || snf.group_title, '')) AS Source,
      
-- snf.public_entered_sref,
snf.entered_sref_system,
snf.attr_sref_precision,
snf.privacy_precision,
o.confidential,

-- cannot use cached public_entered_sref as censored records are suppressed and lat/lng precision is excessively truncated
case when s.entered_sref_system = '4326' and coalesce(s.entered_sref, l.centroid_sref) ~ '^-?[0-9]*\.[0-9]*,[ ]*-?[0-9]*\.[0-9]*' then
      abs(round(((string_to_array(coalesce(s.entered_sref, l.centroid_sref), ','))[1])::numeric, 5))::varchar
      || case when ((string_to_array(coalesce(s.entered_sref, l.centroid_sref), ','))[1])::float>0 then 'N' else 'S' end
      || ', '
      || abs(round(((string_to_array(coalesce(s.entered_sref, l.centroid_sref), ','))[2])::numeric, 5))::varchar
      || case when ((string_to_array(coalesce(s.entered_sref, l.centroid_sref), ','))[2])::float > 0 then 'E' else 'W' end
    when s.entered_sref_system = '4326' and coalesce(s.entered_sref, l.centroid_sref) ~ '^-?[0-9]*\.[0-9]*[NS](, |[, ])*-?[0-9]*\.[0-9]*[EW]' then
      abs(round(((regexp_split_to_array(coalesce(s.entered_sref, l.centroid_sref), '([NS](, |[, ]))|[EW]'))[1])::numeric, 5))::varchar
      || case when coalesce(s.entered_sref, l.centroid_sref) like '%N%' then 'N' else 'S' end
      || ', '
      || abs(round(((regexp_split_to_array(coalesce(s.entered_sref, l.centroid_sref), '([NS](, |[, ]))|[EW]'))[2])::numeric, 5))::varchar
      || case when coalesce(s.entered_sref, l.centroid_sref) like '%E%' then 'E' else 'W' end
    else
      coalesce(s.entered_sref, l.centroid_sref)
  end AS entered_sref_full,

-- o.location_name, -- cached location name isn't usable as is missed on sensitive records
coalesce(l.name, s.location_name, lp.name, sp.location_name) as location_name,

vclocation.code AS vcn,
-- o.location_id,
-- snf.attr_biotope,
-- snf.attr_sample_method,
cttl.taxon AS taxon_name_entered,
cttl.preferred_taxon AS preferred_taxon_name,
-- cttl.default_common_name,
cttl.external_key AS taxon_external_key,
cttl.language AS taxon_language,

snf.recorders,
o.created_by_id,
snf.attr_full_name,

users.username,
users.person_id,

o.date_start,
o.date_end,
o.date_type,
o.created_on,
o.updated_on,

onf.comment,

o.zero_abundance,
o.external_key,

o.record_status,
o.record_substatus,

o.licence_id,
licence.code AS licence_code,

-- onf.media AS image_filename,
o.tracking,

(SELECT jsonb_agg(
jsonb_build_object(
   'occurrence_comments_id', occurrence_comments.id,
   'comment', occurrence_comments.comment,
   'created_by_id', occurrence_comments.created_by_id,
   'created_on', occurrence_comments.created_on,
   'anon_person_name', occurrence_comments.person_name,
   'user_id', occurrence_comments.created_by_id,
   'username', users.username,
   'user_firstname', people.first_name,
   'user_surname', people.surname,
   'auto_generated', occurrence_comments.auto_generated,
   'generated_by', occurrence_comments.generated_by,
   'generated_by_subtype', occurrence_comments.generated_by,
   'record_status', occurrence_comments.record_status,
   'record_substatus', occurrence_comments.record_substatus
) ORDER BY occurrence_comments.created_on ASC, occurrence_comments.id ASC) AS "commentsummary" FROM 
indicia.occurrence_comments
LEFT JOIN indicia.users ON (users.id = occurrence_comments.created_by_id)
LEFT JOIN indicia.people ON (users.person_id = people.id)
WHERE occurrence_comments.occurrence_id = o.id
   AND occurrence_comments.deleted = false
   AND confidential = false
    AND ((generated_by IS NULL) OR (generated_by NOT LIKE 'data\_cleaner\_%')) 
GROUP BY indicia.occurrence_comments.occurrence_id
) AS "annotations",

-- ---- sample attribute values
(SELECT jsonb_agg(
jsonb_build_object(
   'id', 
   sample_attribute_values.sample_attribute_id,
   'function',
   sample_attributes.system_function,
    'name',
    sample_attributes.caption,
   'value',
   CASE sample_attributes.data_type
      WHEN 'T' THEN jsonb_build_object('text', sample_attribute_values.text_value)
      WHEN 'L' THEN jsonb_build_object('term', indicia.terms.term)
      WHEN 'I' THEN jsonb_build_object('int', sample_attribute_values.int_value)
      WHEN 'F' THEN jsonb_build_object('float', sample_attribute_values.float_value)
      WHEN 'B' THEN jsonb_build_object('int', sample_attribute_values.int_value)
      WHEN 'D' THEN jsonb_build_object(
               'date_start', sample_attribute_values.date_start_value,
               'date_type', sample_attribute_values.date_type_value
             )
      WHEN 'V' THEN jsonb_build_object(
               'date_start', sample_attribute_values.date_start_value,
               'date_end', sample_attribute_values.date_end_value,
               'date_type', sample_attribute_values.date_type_value
             )
   END
)
) AS "sample_atts_summary"
FROM indicia.sample_attribute_values
JOIN indicia.sample_attributes ON (indicia.sample_attribute_values.sample_attribute_id = indicia.sample_attributes.id)
LEFT JOIN indicia.termlists_terms ON (
   termlists_terms.id = sample_attribute_values.int_value
   AND sample_attributes.data_type = 'L' -- termlist
)
LEFT JOIN indicia.terms ON (
   indicia.terms.id = termlists_terms.term_id
) 
WHERE sample_attribute_values.sample_id = o.sample_id
   AND NOT sample_attribute_values.deleted
   -- exclude full_name and sample_method as these are adequately collacesed in attr_fullname, attr_sample_method
   AND (sample_attributes.system_function IS NULL OR sample_attributes.system_function NOT IN ('email', 'full_name', 'sample_method'))
GROUP BY sample_attribute_values.sample_id) AS "sav",

-- ---- also need parent sample attribute values
(SELECT jsonb_agg(
jsonb_build_object(
   'id', 
   sample_attribute_values.sample_attribute_id,
   'function',
   sample_attributes.system_function,
    'name',
    sample_attributes.caption,
   'value',
   CASE sample_attributes.data_type
      WHEN 'T' THEN jsonb_build_object('text', sample_attribute_values.text_value)
      WHEN 'L' THEN jsonb_build_object('term', indicia.terms.term)
      WHEN 'I' THEN jsonb_build_object('int', sample_attribute_values.int_value)
      WHEN 'F' THEN jsonb_build_object('float', sample_attribute_values.float_value)
      WHEN 'B' THEN jsonb_build_object('int', sample_attribute_values.int_value)
      WHEN 'D' THEN jsonb_build_object(
               'date_start', sample_attribute_values.date_start_value,
               'date_type', sample_attribute_values.date_type_value
             )
      WHEN 'V' THEN jsonb_build_object(
               'date_start', sample_attribute_values.date_start_value,
               'date_end', sample_attribute_values.date_end_value,
               'date_type', sample_attribute_values.date_type_value
             )
   END
)
) AS "sample_atts_summary"
FROM indicia.sample_attribute_values
JOIN indicia.sample_attributes ON (indicia.sample_attribute_values.sample_attribute_id = indicia.sample_attributes.id)
LEFT JOIN indicia.termlists_terms ON (
   termlists_terms.id = sample_attribute_values.int_value
   AND sample_attributes.data_type = 'L' -- termlist
)
LEFT JOIN indicia.terms ON (
   indicia.terms.id = termlists_terms.term_id
) 
WHERE sample_attribute_values.sample_id = o.parent_sample_id
   AND NOT sample_attribute_values.deleted
   -- exclude full_name and sample_method as these are adequately collacesed in attr_fullname, attr_sample_method
   AND (sample_attributes.system_function IS NULL OR sample_attributes.system_function NOT IN ('email', 'full_name', 'sample_method'))
GROUP BY sample_attribute_values.sample_id) AS "psav",

-- ---- occurrance attribute values
(SELECT jsonb_agg(
jsonb_build_object(
   'id', 
   occurrence_attribute_values.occurrence_attribute_id, 
   'function',
   occurrence_attributes.system_function,
    'name',
    occurrence_attributes.caption,
   'value',
   CASE occurrence_attributes.data_type
      WHEN 'T' THEN jsonb_build_object('text', occurrence_attribute_values.text_value)
      WHEN 'L' THEN jsonb_build_object('term', indicia.terms.term)
      WHEN 'I' THEN jsonb_build_object('int', occurrence_attribute_values.int_value)
      WHEN 'F' THEN jsonb_build_object('float', occurrence_attribute_values.float_value)
      WHEN 'B' THEN jsonb_build_object('int', occurrence_attribute_values.int_value)
      WHEN 'D' THEN jsonb_build_object(
               'date_start', occurrence_attribute_values.date_start_value,
               'date_type', occurrence_attribute_values.date_type_value
             )
      WHEN 'V' THEN jsonb_build_object(
               'date_start', occurrence_attribute_values.date_start_value,
               'date_end', occurrence_attribute_values.date_end_value,
               'date_type', occurrence_attribute_values.date_type_value
             )
   END
)
) AS "occurrence_atts_summary"
FROM indicia.occurrence_attribute_values
JOIN indicia.occurrence_attributes ON (indicia.occurrence_attribute_values.occurrence_attribute_id = indicia.occurrence_attributes.id)
LEFT JOIN indicia.termlists_terms ON (
   termlists_terms.id = occurrence_attribute_values.int_value
   AND occurrence_attributes.data_type = 'L' -- termlist
)
LEFT JOIN indicia.terms ON (
   indicia.terms.id = termlists_terms.term_id
) 
WHERE occurrence_attribute_values.occurrence_id = o.id
   AND NOT occurrence_attribute_values.deleted
GROUP BY occurrence_attribute_values.occurrence_id) AS "oav",


-- images, join is needed to get the filename and license
(SELECT jsonb_agg(
jsonb_build_object(
   'id', 
   occurrence_media.id, 
        'path',
        occurrence_media.path,
        'caption',
        occurrence_media.caption,
   'licence_id',
   occurrence_media.licence_id,
   'licence_code',
   imagelicence.code,
   'external_details',
   occurrence_media.external_details,
   'media_type_id',
   occurrence_media.media_type_id -- keyed against termlist_terms
)
) AS "image_summary"
FROM indicia.occurrence_media
LEFT JOIN indicia.licences AS imagelicence ON (occurrence_media.licence_id = imagelicence.id)
WHERE occurrence_media.occurrence_id = o.id
  AND NOT occurrence_media.deleted 

GROUP BY occurrence_media.occurrence_id) AS "imagedetails"

-- ----

FROM indicia.cache_occurrences_functional o
     JOIN indicia.cache_occurrences_nonfunctional onf ON onf.id = o.id
     JOIN indicia.cache_samples_nonfunctional snf ON snf.id = o.sample_id
     JOIN indicia.samples s ON s.id = o.sample_id
     JOIN indicia.cache_taxa_taxon_lists cttl ON cttl.id = o.taxa_taxon_list_id

JOIN indicia.users AS users ON (o.created_by_id = users.id)
JOIN indicia.people AS people ON (users.person_id = people.id)

JOIN indicia.surveys ON (o.survey_id = indicia.surveys.id)

LEFT JOIN indicia.licences AS licence ON (o.licence_id = licence.id)

LEFT JOIN indicia.locations AS l ON (
l.id = s.location_id AND l.deleted = false
)

LEFT JOIN indicia.samples sp ON (sp.id = s.parent_id AND sp.deleted = false)

LEFT JOIN indicia.locations AS lp ON (
lp.id = sp.location_id AND lp.deleted = false
)

LEFT JOIN indicia.locations AS vclocation ON (
vclocation.id = snf.attr_linked_location_id
AND vclocation.location_type_id = 15
)

WHERE 
o.training = false 
-- AND o.updated_on >= timestamp '2019-03-01'

AND o.website_id IN (
   23, -- iRecord
   32, -- NPMS
   29 -- CEDaR
   -- 112 -- iNaturalist
   -- 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 16, 17, 23, 24, 25, 27, 28, 29, 30,32, 33, 34, 40, 41, 42, 43, 44, 47, 49, 51, 54, 59, 65, 68, 69, 71, 72, 73, 75, -- all websites sharing for verification 08.05.24
   -- 83, 87, 92, 97, 98, 101, 108, 109, 112, 115, 119, 120, 123, 124, 127, 128, 129, 131, 132, 133, 135, 139, 141, 142, 143, 145, 147, 148, 150, 151, 152, 155 
)

AND o.survey_id != 105 -- 'Rinse' (appears to be a Belgian project)

AND cttl.taxon_group_id in (
   78, -- clubmoss
   81, -- conifer
   87, -- fern
   57, -- Ferns
   21, -- Ferns & horsetails
   89, -- Flowering plant
   94, -- ginkgo
   23, -- Grasses, Rushes, Sedges
   99, -- horsetail
   3, -- Plants
   137, -- quillwort
   148, -- stonewort
   39, -- Trees, Shrubs, Climbers
   40 -- Wildflowers
)

GROUP BY
o.id,
o.sample_id,
-- snf.website_title,
-- snf.survey_title,
-- snf.group_title,
snf.public_entered_sref,
snf.entered_sref_system,
entered_sref_full,
snf.attr_sref_precision,
snf.privacy_precision,
o.confidential,
-- o.location_name,
coalesce(l.name, s.location_name, lp.name, sp.location_name),
vcn,
cttl.taxon,
cttl.preferred_taxon,
-- cttl.default_common_name,
cttl.external_key,
cttl.language,
snf.recorders,
o.created_by_id,
snf.attr_full_name,
-- people.email_address,
o.date_start,
o.date_end,
o.date_type,
o.created_on,
o.updated_on,
onf.comment,
-- onf.media,
-- snf.attrs_json::jsonb
users.username,
users.person_id,
o.survey_id,
surveys.title,
-- snf.attr_biotope,
snf.attr_sample_method,
licence.code,
o.tracking

ORDER BY o.id
-- LIMIT 500
;


\copy (SELECT * FROM v1) to 'C:\Users\samamy\Downloads\dev_warehouse_export_2024_05_07.csv' with ( FORMAT csv, ENCODING 'UTF-8', FORCE_QUOTE *, HEADER );

drop view v1;
