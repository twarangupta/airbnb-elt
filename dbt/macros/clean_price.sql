{#
  Turn a price stored as text ('$1,234.50') into a number (1234.50).
  Removes the dollar sign and thousands commas, then TRY_TO_NUMBER, which
  returns NULL instead of failing if the text is not a number.
  Usage: {{ clean_price('price') }}
#}
{% macro clean_price(column_name) -%}
    TRY_TO_NUMBER(REPLACE(REPLACE({{ column_name }}, '$', ''), ',', ''), 12, 2)
{%- endmacro %}
