"""Local research-only number-word marking; not a production grading endpoint."""
import unicodedata


def normalized_integer(text):
    value = unicodedata.normalize('NFKC', text).strip()
    if not value or not value.isdecimal():
        return None
    return int(value)


def correct_number(text, expected):
    return normalized_integer(text) == int(expected)
