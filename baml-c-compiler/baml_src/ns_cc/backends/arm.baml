// Code generator — AArch64 / Apple Silicon, targeting macOS (Mach-O, Darwin ABI).
// Same stack-machine shape as the x86-64 backend: every expression leaves its
// result in x0; locals live at negative offsets from the frame pointer x29; sp
// is kept 16-byte aligned at all times (the AArch64 ABI requires it).
//
// Differences from the Linux x86-64 backend: Mach-O `_`-prefixed symbols,
// `adrp`/`add @PAGE/@PAGEOFF` to address strings, `stp`/`ldp` frames, and Apple's
// variadic convention — for `printf(fmt, ...)` the fixed `fmt` goes in x0 but the
// variadic `%d` arguments are passed on the stack.

function a64_arg_reg(i: int) -> string {
    if (i == 0) {
        return "x0";
    };
    if (i == 1) {
        return "x1";
    };
    if (i == 2) {
        return "x2";
    };
    if (i == 3) {
        return "x3";
    };
    if (i == 4) {
        return "x4";
    };
    if (i == 5) {
        return "x5";
    };
    if (i == 6) {
        return "x6";
    };
    "x7"
}

function a64_cset_cond(op: string) -> string {
    if (op == "==") {
        return "eq";
    };
    if (op == "!=") {
        return "ne";
    };
    if (op == "<") {
        return "lt";
    };
    if (op == "<=") {
        return "le";
    };
    if (op == ">") {
        return "gt";
    };
    if (op == ">=") {
        return "ge";
    };
    "eq"
}

// Materialize a non-negative integer literal into x0 (movz + optional movk).
function a64_load_imm(n: int, gen: Gen) -> null {
    gen.emit("    mov x0, #" + string.from(n % 65536));
    let rest = n / 65536;
    if (rest != 0) {
        gen.emit("    movk x0, #" + string.from(rest % 65536) + ", lsl #16");
    };
    null
}

function a64_gen_binop(op: string, gen: Gen) -> null {
    // lhs in x0, rhs in x1; result left in x0.
    if (op == "+") {
        gen.emit("    add x0, x0, x1");
        return null;
    };
    if (op == "-") {
        gen.emit("    sub x0, x0, x1");
        return null;
    };
    if (op == "*") {
        gen.emit("    mul x0, x0, x1");
        return null;
    };
    if (op == "/") {
        gen.emit("    sdiv x0, x0, x1");
        return null;
    };
    if (op == "%") {
        gen.emit("    sdiv x2, x0, x1");
        gen.emit("    msub x0, x2, x1, x0");
        return null;
    };
    gen.emit("    cmp x0, x1");
    gen.emit("    cset x0, " + a64_cset_cond(op));
    null
}

// printf is variadic: fmt in x0, the rest on the stack (Apple arm64 rule).
function a64_gen_call_printf(call: Call, gen: Gen) -> null throws CError {
    let k = call.args.length() - 1;
    if (k <= 0) {
        a64_gen_expr(call.args.at(0) ?? IntLit { value: 0 }, gen);
        gen.emit("    bl _printf");
        return null;
    };
    let varspace = k * 8;
    if (varspace % 16 != 0) {
        varspace = varspace + (16 - varspace % 16);
    };
    gen.emit("    sub sp, sp, #" + string.from(varspace));
    let i = 1;
    while (i <= k) {
        a64_gen_expr(call.args.at(i) ?? IntLit { value: 0 }, gen);
        gen.emit("    str x0, [sp, #" + string.from((i - 1) * 8) + "]");
        i += 1;
    }
    a64_gen_expr(call.args.at(0) ?? IntLit { value: 0 }, gen);
    gen.emit("    bl _printf");
    gen.emit("    add sp, sp, #" + string.from(varspace));
    null
}

function a64_gen_call(call: Call, gen: Gen) -> null throws CError {
    if (call.name == "printf") {
        a64_gen_call_printf(call, gen);
        return null;
    };
    // Normal (non-variadic) call: arguments in x0..x7.
    let n = call.args.length();
    for (let a in call.args) {
        a64_gen_expr(a, gen);
        gen.emit("    str x0, [sp, #-16]!");
    }
    let j = n - 1;
    while (j >= 0) {
        gen.emit("    ldr " + a64_arg_reg(j) + ", [sp], #16");
        j -= 1;
    }
    gen.emit("    bl _" + call.name);
    null
}

function a64_gen_expr(e: Expr, gen: Gen) -> null throws CError {
    match (e) {
        let lit: IntLit => {
            a64_load_imm(lit.value, gen);
            null
        },
        let s: StrLit => {
            let label = gen.add_cstring(s.value);
            gen.emit("    adrp x0, " + label + "@PAGE");
            gen.emit("    add x0, x0, " + label + "@PAGEOFF");
            null
        },
        let v: VarRef => {
            gen.emit("    ldr x0, [x29, #" + string.from(gen.offset_of(v.name)) + "]");
            null
        },
        let a: Assign => {
            a64_gen_expr(a.value, gen);
            gen.emit("    str x0, [x29, #" + string.from(gen.offset_of(a.name)) + "]");
            null
        },
        let un: UnaryOp => {
            a64_gen_expr(un.operand, gen);
            gen.emit("    neg x0, x0");
            null
        },
        let bin: BinOp => {
            a64_gen_expr(bin.lhs, gen);
            gen.emit("    str x0, [sp, #-16]!");
            a64_gen_expr(bin.rhs, gen);
            gen.emit("    mov x1, x0");
            gen.emit("    ldr x0, [sp], #16");
            a64_gen_binop(bin.op, gen);
            null
        },
        let call: Call => {
            a64_gen_call(call, gen);
            null
        },
    }
}

function a64_gen_block(stmts: Stmt[], gen: Gen) -> null throws CError {
    for (let s in stmts) {
        a64_gen_stmt(s, gen);
    }
    null
}

function a64_gen_stmt(s: Stmt, gen: Gen) -> null throws CError {
    match (s) {
        let r: ReturnStmt => {
            a64_gen_expr(r.value, gen);
            gen.emit("    mov sp, x29");
            gen.emit("    ldp x29, x30, [sp], #16");
            gen.emit("    ret");
            null
        },
        let es: ExprStmt => {
            a64_gen_expr(es.expr, gen);
            null
        },
        let vd: VarDecl => {
            a64_gen_expr(vd.init, gen);
            gen.emit("    str x0, [x29, #" + string.from(gen.offset_of(vd.name)) + "]");
            null
        },
        let iff: IfStmt => {
            let else_l = gen.new_label_macho("else");
            let end_l = gen.new_label_macho("endif");
            a64_gen_expr(iff.cond, gen);
            gen.emit("    cbz x0, " + else_l);
            a64_gen_block(iff.then_body, gen);
            gen.emit("    b " + end_l);
            gen.emit(else_l + ":");
            a64_gen_block(iff.else_body, gen);
            gen.emit(end_l + ":");
            null
        },
        let wh: WhileStmt => {
            let start_l = gen.new_label_macho("while");
            let end_l = gen.new_label_macho("endwhile");
            gen.emit(start_l + ":");
            a64_gen_expr(wh.cond, gen);
            gen.emit("    cbz x0, " + end_l);
            a64_gen_block(wh.body, gen);
            gen.emit("    b " + start_l);
            gen.emit(end_l + ":");
            null
        },
    }
}

function a64_gen_function(f: Function, gen: Gen) -> null throws CError {
    gen.locals = {};
    gen.frame = 0;
    for (let p in f.params) {
        gen.declare_local(p);
    }
    scan_locals(f.body, gen);
    let frame = gen.frame;
    if (frame % 16 != 0) {
        frame = frame + (16 - frame % 16);
    };
    gen.emit("    .globl _" + f.name);
    gen.emit("    .p2align 2");
    gen.emit("_" + f.name + ":");
    gen.emit("    stp x29, x30, [sp, #-16]!");
    gen.emit("    mov x29, sp");
    if (frame > 0) {
        gen.emit("    sub sp, sp, #" + string.from(frame));
    };
    // Spill incoming argument registers into their parameter slots.
    let pi = 0;
    for (let p in f.params) {
        gen.emit("    str " + a64_arg_reg(pi) + ", [x29, #" + string.from(gen.offset_of(p)) + "]");
        pi += 1;
    }
    a64_gen_block(f.body, gen);
    gen.emit("    mov x0, #0");
    gen.emit("    mov sp, x29");
    gen.emit("    ldp x29, x30, [sp], #16");
    gen.emit("    ret");
    null
}

function codegen_arm64(prog: Program) -> string throws CError {
    let gen = Gen { text: [], data: [], locals: {}, frame: 0, label_id: 0, str_id: 0 };
    gen.emit("    .section __TEXT,__text,regular,pure_instructions");
    for (let f in prog.funcs) {
        a64_gen_function(f, gen);
    }
    let out: string[] = [];
    for (let l in gen.text) {
        out.push(l);
    }
    if (gen.data.length() > 0) {
        out.push("    .section __TEXT,__cstring,cstring_literals");
        for (let d in gen.data) {
            out.push(d);
        }
    }
    out.push("    .subsections_via_symbols");
    out.join("\n") + "\n"
}
