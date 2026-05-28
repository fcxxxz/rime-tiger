import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]


class SemicolonProcStaticTest(unittest.TestCase):
    def test_tiger_schema_wires_semicolon_processor_before_key_binder(self):
        schema = (ROOT / "tiger.schema.yaml").read_text(encoding="utf-8")

        space_proc = "lua_processor@*space_proc3"
        semicolon_proc = "lua_processor@*semicolon_proc"
        key_binder = "    - key_binder"

        self.assertIn(space_proc, schema)
        self.assertIn(semicolon_proc, schema)
        self.assertLess(schema.index(space_proc), schema.index(semicolon_proc))
        self.assertLess(schema.index(semicolon_proc), schema.index(key_binder))

    def test_semicolon_processor_checks_unique_candidate_before_commit(self):
        lua = (ROOT / "lua" / "semicolon_proc.lua").read_text(encoding="utf-8")

        self.assertIn('key_event:repr() ~= "semicolon"', lua)
        self.assertIn("key_event:shift()", lua)
        self.assertIn("seg.menu:prepare(2)", lua)
        self.assertIn("seg.menu:get_candidate_at(0)", lua)
        self.assertIn("seg.menu:get_candidate_at(1)", lua)
        self.assertIn("first.text == context.input", lua)
        self.assertIn("confirm_current_selection", lua)


if __name__ == "__main__":
    unittest.main()
