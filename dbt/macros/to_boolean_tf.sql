{#
  Inside Airbnb writes booleans as 't' / 'f'. Map them to TRUE / FALSE;
  anything else (including NULL) becomes NULL.
  Usage: {{ to_boolean_tf('host_is_superhost') }}
#}
{% macro to_boolean_tf(column_name) -%}
    CASE LOWER({{ column_name }}) WHEN 't' THEN TRUE WHEN 'f' THEN FALSE END
{%- endmacro %}
