# Shortcut editModeContext

A standalone macOS command-line tool that exports an unsigned Shortcut workflow
plist to Apple's native edit-mode Python, then appends self-contained `ref()`
catalog declarations in the same source format used by Shortpy IDE. It does
not depend on Shortpy IDE.

## Build and use

Requires Apple Silicon macOS with the private WorkflowKit, ShortcutsAgent, and
ShortcutsLanguage frameworks, plus Xcode command-line tools. Tested on macOS
27.0 (`26A5378n`). The private ABI is version-sensitive.

```sh
make
./shortcut-editmode-context input.plist output.py
make test
```

Input must be an unsigned workflow plist containing `WFWorkflowActions`.
Signed `AEA1` `.shortcut` files are not plist inputs. The command reads the
input, writes `output.py` atomically, and never saves or runs the workflow.
On failure it returns a nonzero status without replacing an existing output.

Example output:

```python
def shortcut() -> None:
    com_apple_shortcuts_open_app(app=ref(0xA198))


def ref(tag: int, /) -> CatalogRef:
    match tag:
        case 0xA198:
            return {'BundleIdentifier': 'com.apple.shortcuts',
                    'Name': 'Shortcuts',
                    'TeamIdentifier': '0000000000'}
```

Tags are assigned by the native exporter and can differ between runs. The
`ref` function is a declarative source representation. To feed this file back
to Apple's `pythonToShortcut`, a caller must remove the function and supply
its values as catalog metadata, as Shortpy IDE does.

The native helper calls `DescribeAShortcutAgent.editModeContext(for:)` on an
in-memory `WFWorkflow`. It reads the returned `WFPythonWorkflowProxy`'s
`pythonCode` and catalog; catalog entries are decoded from archived parameter
states before being formatted as Python literals. Unknown refs and unsupported
NSDate literals fail rather than producing an incomplete declaration.

A standalone host can still import some actions as `WFMissingAction`; the CLI
warns with their identifiers. Apple exporter failures also propagate. This
tool does not synthesize actions or modify Apple's output to hide such cases.
Treat input plists as code-like, locally trusted material because native
frameworks and keyed archives are involved.
