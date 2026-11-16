"""Lint-only stand-ins for dbt_utils macros.

sqlfluff's jinja templater renders dbt SQL without dbt, so it does not know
package macros like dbt_utils.generate_surrogate_key. .sqlfluff points
library_path here, and these functions return simple, valid SQL with the same
shape. dbt itself never imports this module.
"""


def generate_surrogate_key(field_list):
    return "MD5(CONCAT_WS('-', " + ", ".join(str(f) for f in field_list) + "))"


def date_spine(datepart, start_date, end_date):
    return f"SELECT DATEADD('{datepart}', SEQ4(), {start_date}) AS date_day FROM TABLE(GENERATOR(ROWCOUNT => 10))"
