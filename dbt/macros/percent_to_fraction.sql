{#
  '95%' -> 0.95. NULL or 'N/A' -> NULL.
  Usage: {{ percent_to_fraction('host_response_rate') }}
#}
{% macro percent_to_fraction(column_name) -%}
    TRY_TO_NUMBER(REPLACE({{ column_name }}, '%', ''), 5, 2) / 100
{%- endmacro %}
