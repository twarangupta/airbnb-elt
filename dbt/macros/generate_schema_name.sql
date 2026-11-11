{#
  Decides which Snowflake schema each model is built in.

  dbt's built-in rule glues the profile schema and the folder schema together
  (SILVER + silver = SILVER_SILVER), which is not what we want. Our rule:
    - model has no custom schema      -> use the profile schema as-is
    - target is "ci"                  -> <profile schema>_<custom>, e.g. CI_GOLD,
                                         so CI never touches the real tables
    - any other target (dev)          -> exactly the custom schema, e.g. GOLD
#}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if custom_schema_name is none -%}
        {{ target.schema }}
    {%- elif target.name == 'ci' -%}
        {{ target.schema }}_{{ custom_schema_name | trim }}
    {%- else -%}
        {{ custom_schema_name | trim | upper }}
    {%- endif -%}
{%- endmacro %}
