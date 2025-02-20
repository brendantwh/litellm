import json
import os
import sys

import pytest

sys.path.insert(
    0, os.path.abspath("../../..")
)  # Adds the parent directory to the system path

from litellm.litellm_core_utils.safe_json_dumps import safe_dumps


def test_primitive_types():
    # Test basic primitive types
    assert safe_dumps("test") == '"test"'
    assert safe_dumps(123) == "123"
    assert safe_dumps(3.14) == "3.14"
    assert safe_dumps(True) == "true"
    assert safe_dumps(None) == "null"


def test_nested_structures():
    # Test nested dictionaries and lists
    data = {"name": "test", "numbers": [1, 2, 3], "nested": {"a": 1, "b": 2}}
    result = json.loads(safe_dumps(data))
    assert result["name"] == "test"
    assert result["numbers"] == [1, 2, 3]
    assert result["nested"] == {"a": 1, "b": 2}


def test_circular_reference():
    # Test circular reference detection
    d = {}
    d["self"] = d
    result = json.loads(safe_dumps(d))
    assert result["self"] == "CircularReference Detected"


def test_max_depth():
    # Test maximum depth handling
    deep_dict = {}
    current = deep_dict
    for i in range(15):
        current["deeper"] = {}
        current = current["deeper"]

    result = json.loads(safe_dumps(deep_dict, max_depth=5))
    assert "MaxDepthExceeded" in str(result)


def test_default_max_depth():
    # Test that default max depth still prevents infinite recursion
    deep_dict = {}
    current = deep_dict
    for i in range(1000):  # Create a very deep dictionary
        current["deeper"] = {}
        current = current["deeper"]

    result = json.loads(safe_dumps(deep_dict))  # No max_depth parameter provided
    assert "MaxDepthExceeded" in str(result)


def test_complex_types():
    # Test handling of sets and tuples
    data = {"set": {1, 2, 3}, "tuple": (4, 5, 6)}
    result = json.loads(safe_dumps(data))
    assert result["set"] == [1, 2, 3]  # Sets are converted to sorted lists
    assert result["tuple"] == [4, 5, 6]  # Tuples are converted to lists


def test_unserializable_object():
    # Test handling of unserializable objects
    class TestClass:
        def __str__(self):
            raise Exception("Cannot convert to string")

    obj = TestClass()
    result = json.loads(safe_dumps(obj))
    assert result == "Unserializable Object"
