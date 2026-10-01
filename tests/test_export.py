from pathlib import Path
import subprocess
import tempfile
import unittest

from shortcut_editmode_context import ExportError, render_python


ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "tests" / "fixtures"


class RenderTests(unittest.TestCase):
    def test_no_refs_keeps_native_python(self):
        source = "def shortcut() -> None:\n    pass\n"
        self.assertEqual(render_python({"python_code": source}), source)

    def test_ref_function_uses_decoded_state(self):
        result = render_python({
            "python_code": "def shortcut() -> None:\n    action(app=ref(0xA198))\n",
            "catalog": {"0xA198": {
                "parameterStateObject": {"Name": "Shortcuts", "TeamIdentifier": "0000000000"},
                "modelDescription": '{"Name":"wrong fallback"}',
            }},
        })
        self.assertIn("def ref(tag: int, /) -> CatalogRef:", result)
        self.assertIn("case 0xA198:", result)
        self.assertIn("'TeamIdentifier': '0000000000'", result)
        self.assertNotIn("wrong fallback", result)

    def test_missing_catalog_ref_fails(self):
        with self.assertRaisesRegex(ExportError, "no entry for 0xA198"):
            render_python({"python_code": "ref(0xA198)\n", "catalog": {}})


class IntegrationTests(unittest.TestCase):
    def test_empty_workflow(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "out.py"
            completed = subprocess.run(
                [str(ROOT / "shortcut-editmode-context"),
                 str(FIXTURES / "empty.plist"), str(output)],
                capture_output=True, text=True,
            )
            self.assertEqual(completed.returncode, 0, completed.stderr)
            self.assertEqual(output.read_text(), "def shortcut() -> None:\n    pass\n")

    def test_text_workflow(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "out.py"
            completed = subprocess.run(
                [str(ROOT / "shortcut-editmode-context"),
                 str(FIXTURES / "text.plist"), str(output)],
                capture_output=True, text=True,
            )
            self.assertEqual(completed.returncode, 0, completed.stderr)
            self.assertIn('com_apple_shortcuts_text(text="hello")', output.read_text())

    def test_catalog_ref_workflow(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "out.py"
            completed = subprocess.run(
                [str(ROOT / "shortcut-editmode-context"),
                 str(FIXTURES / "open-app.plist"), str(output)],
                capture_output=True, text=True,
            )
            self.assertEqual(completed.returncode, 0, completed.stderr)
            source = output.read_text()
            self.assertRegex(source, r"app=ref\(0x[0-9A-F]{4}\)")
            self.assertRegex(source, r"case 0x[0-9A-F]{4}:")
            self.assertIn("'TeamIdentifier': '0000000000'", source)

    def test_failure_does_not_replace_output(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "out.py"
            output.write_text("unchanged")
            completed = subprocess.run(
                [str(ROOT / "shortcut-editmode-context"),
                 str(FIXTURES / "invalid.plist"), str(output)],
                capture_output=True, text=True,
            )
            self.assertNotEqual(completed.returncode, 0)
            self.assertEqual(output.read_text(), "unchanged")


if __name__ == "__main__":
    unittest.main()
