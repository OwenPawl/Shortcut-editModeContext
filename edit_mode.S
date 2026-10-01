.text
.globl _bridge_describe_edit_mode_context_nil
_bridge_describe_edit_mode_context_nil:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    mov x8, x0
    mov x0, x1
    mov x1, xzr
    mov x2, xzr
    mov x21, xzr
    bl _$s14ShortcutsAgent017DescribeAShortcutB0V15editModeContext3forAC04EditfG0VSo10WFWorkflowC_tKFZ
    mov x0, x21
    ldp x29, x30, [sp], #16
    ret
