// Deterministic tests — no LLM, no tokens. Run with `baml test`.

test "return_42" {
    let asm = compile_source("int main(void) { return 42; }");
    assert.contains(asm, "$42");
    assert.contains(asm, "ret");
}

test "arithmetic_precedence" {
    let asm = compile_source("int main(void) { return 2 * (3 + 4) - 5; }");
    assert.contains(asm, "imul");
    assert.contains(asm, "add");
    assert.contains(asm, "sub");
}

test "unary_minus" {
    let asm = compile_source("int main(void) { return -7; }");
    assert.contains(asm, "neg");
}

test "hello_world_uses_printf" {
    let asm = compile_source("int main(void) { printf(\"hi\\n\"); return 0; }");
    assert.contains(asm, "printf@PLT");
    assert.contains(asm, ".string");
}

test "while_and_compare" {
    let asm = compile_source("int main(void) { int i = 0; while (i < 3) { i = i + 1; } return i; }");
    assert.contains(asm, "setl");
    assert.contains(asm, "je ");
    assert.contains(asm, "jmp ");
}

test "if_else_branches" {
    let asm = compile_source("int main(void) { int x = 5; if (x > 3) { return 1; } else { return 0; } }");
    assert.contains(asm, "setg");
}

test "recursion_and_params" {
    let asm = compile_source(
        "int fib(int n) { if (n < 2) { return n; } return fib(n - 1) + fib(n - 2); } int main(void) { return fib(10); }",
    );
    assert.contains(asm, "call fib@PLT");
    assert.contains(asm, "mov %rdi,");
}
