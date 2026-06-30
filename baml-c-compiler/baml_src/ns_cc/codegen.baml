// Code generator — walk the AST and emit x86-64 assembly (AT&T syntax,
// System V ABI). A simple stack machine: every expression leaves its result in
// %rax; locals live at -N(%rbp); calls keep %rsp 16-byte aligned.

class Gen {
    text: string[],
    data: string[],
    locals: map<string, int>,
    frame: int,
    label_id: int,
    str_id: int,

    function emit(self, s: string) -> null {
        self.text.push(s);
        null
    }

    function new_label(self, base: string) -> string {
        let l = ".L" + base + string.from(self.label_id);
        self.label_id += 1;
        l
    }

    function add_string(self, raw: string) -> string {
        let label = ".LC" + string.from(self.str_id);
        self.str_id += 1;
        self.data.push(label + ":");
        self.data.push("    .string \"" + raw + "\"");
        label
    }

    function declare_local(self, name: string) -> null {
        if (!self.locals.has(name)) {
            self.frame += 8;
            self.locals.set(name, 0 - self.frame);
        };
        null
    }

    function offset_of(self, name: string) -> int throws CError {
        let o = self.locals.get(name) ?? 1;
        if (o >= 0) {
            throw CError { message: "use of undeclared variable '" + name + "'" };
        };
        o
    }
}

function set_instr(op: string) -> string {
    if (op == "==") {
        return "sete";
    };
    if (op == "!=") {
        return "setne";
    };
    if (op == "<") {
        return "setl";
    };
    if (op == "<=") {
        return "setle";
    };
    if (op == ">") {
        return "setg";
    };
    if (op == ">=") {
        return "setge";
    };
    "sete"
}

function gen_binop(op: string, gen: Gen) -> null {
    // lhs in %rax, rhs in %rcx; result left in %rax.
    if (op == "+") {
        gen.emit("    add %rcx, %rax");
        return null;
    };
    if (op == "-") {
        gen.emit("    sub %rcx, %rax");
        return null;
    };
    if (op == "*") {
        gen.emit("    imul %rcx, %rax");
        return null;
    };
    if (op == "/") {
        gen.emit("    cqo");
        gen.emit("    idiv %rcx");
        return null;
    };
    if (op == "%") {
        gen.emit("    cqo");
        gen.emit("    idiv %rcx");
        gen.emit("    mov %rdx, %rax");
        return null;
    };
    gen.emit("    cmp %rcx, %rax");
    gen.emit("    " + set_instr(op) + " %al");
    gen.emit("    movzbl %al, %eax");
    null
}

function arg_reg(i: int) -> string {
    if (i == 0) {
        return "%rdi";
    };
    if (i == 1) {
        return "%rsi";
    };
    if (i == 2) {
        return "%rdx";
    };
    if (i == 3) {
        return "%rcx";
    };
    if (i == 4) {
        return "%r8";
    };
    "%r9"
}

function gen_call(call: Call, gen: Gen) -> null throws CError {
    let n = call.args.length();
    // Evaluate args left-to-right into 16-byte stack slots (keeps %rsp aligned).
    for (let a in call.args) {
        gen_expr(a, gen);
        gen.emit("    sub $16, %rsp");
        gen.emit("    mov %rax, (%rsp)");
    }
    // Pop them off into the System V argument registers (rdi, rsi, rdx, ...).
    let j = n - 1;
    while (j >= 0) {
        gen.emit("    mov (%rsp), " + arg_reg(j));
        gen.emit("    add $16, %rsp");
        j -= 1;
    }
    // %al = number of vector registers used (0) for variadic callees like printf.
    gen.emit("    mov $0, %al");
    gen.emit("    call " + call.name + "@PLT");
    null
}

function gen_expr(e: Expr, gen: Gen) -> null throws CError {
    match (e) {
        let lit: IntLit => {
            gen.emit("    mov $" + string.from(lit.value) + ", %rax");
            null
        },
        let s: StrLit => {
            let label = gen.add_string(s.value);
            gen.emit("    lea " + label + "(%rip), %rax");
            null
        },
        let v: VarRef => {
            gen.emit("    mov " + string.from(gen.offset_of(v.name)) + "(%rbp), %rax");
            null
        },
        let a: Assign => {
            gen_expr(a.value, gen);
            gen.emit("    mov %rax, " + string.from(gen.offset_of(a.name)) + "(%rbp)");
            null
        },
        let un: UnaryOp => {
            gen_expr(un.operand, gen);
            gen.emit("    neg %rax");
            null
        },
        let bin: BinOp => {
            gen_expr(bin.lhs, gen);
            // Save lhs in a 16-byte slot so %rsp stays aligned across nested calls.
            gen.emit("    sub $16, %rsp");
            gen.emit("    mov %rax, (%rsp)");
            gen_expr(bin.rhs, gen);
            gen.emit("    mov %rax, %rcx");
            gen.emit("    mov (%rsp), %rax");
            gen.emit("    add $16, %rsp");
            gen_binop(bin.op, gen);
            null
        },
        let call: Call => {
            gen_call(call, gen);
            null
        },
    }
}

function gen_block(stmts: Stmt[], gen: Gen) -> null throws CError {
    for (let s in stmts) {
        gen_stmt(s, gen);
    }
    null
}

function gen_stmt(s: Stmt, gen: Gen) -> null throws CError {
    match (s) {
        let r: ReturnStmt => {
            gen_expr(r.value, gen);
            gen.emit("    mov %rbp, %rsp");
            gen.emit("    pop %rbp");
            gen.emit("    ret");
            null
        },
        let es: ExprStmt => {
            gen_expr(es.expr, gen);
            null
        },
        let vd: VarDecl => {
            gen_expr(vd.init, gen);
            gen.emit("    mov %rax, " + string.from(gen.offset_of(vd.name)) + "(%rbp)");
            null
        },
        let iff: IfStmt => {
            let else_l = gen.new_label("else");
            let end_l = gen.new_label("endif");
            gen_expr(iff.cond, gen);
            gen.emit("    cmp $0, %rax");
            gen.emit("    je " + else_l);
            gen_block(iff.then_body, gen);
            gen.emit("    jmp " + end_l);
            gen.emit(else_l + ":");
            gen_block(iff.else_body, gen);
            gen.emit(end_l + ":");
            null
        },
        let wh: WhileStmt => {
            let start_l = gen.new_label("while");
            let end_l = gen.new_label("endwhile");
            gen.emit(start_l + ":");
            gen_expr(wh.cond, gen);
            gen.emit("    cmp $0, %rax");
            gen.emit("    je " + end_l);
            gen_block(wh.body, gen);
            gen.emit("    jmp " + start_l);
            gen.emit(end_l + ":");
            null
        },
    }
}

function scan_locals(stmts: Stmt[], gen: Gen) -> null {
    for (let s in stmts) {
        match (s) {
            let vd: VarDecl => {
                gen.declare_local(vd.name);
                null
            },
            let iff: IfStmt => {
                scan_locals(iff.then_body, gen);
                scan_locals(iff.else_body, gen);
                null
            },
            let wh: WhileStmt => {
                scan_locals(wh.body, gen);
                null
            },
            _ => null,
        }
    }
    null
}

function gen_function(f: Function, gen: Gen) -> null throws CError {
    gen.locals = {};
    gen.frame = 0;
    // Parameters get the first local slots, in order.
    for (let p in f.params) {
        gen.declare_local(p);
    }
    scan_locals(f.body, gen);
    let frame = gen.frame;
    if (frame % 16 != 0) {
        frame = frame + (16 - frame % 16);
    };
    gen.emit("    .globl " + f.name);
    gen.emit(f.name + ":");
    gen.emit("    push %rbp");
    gen.emit("    mov %rsp, %rbp");
    if (frame > 0) {
        gen.emit("    sub $" + string.from(frame) + ", %rsp");
    };
    // Spill incoming argument registers into their parameter slots.
    let pi = 0;
    for (let p in f.params) {
        gen.emit("    mov " + arg_reg(pi) + ", " + string.from(gen.offset_of(p)) + "(%rbp)");
        pi += 1;
    }
    gen_block(f.body, gen);
    gen.emit("    mov $0, %rax");
    gen.emit("    mov %rbp, %rsp");
    gen.emit("    pop %rbp");
    gen.emit("    ret");
    null
}

function codegen(prog: Program) -> string throws CError {
    let gen = Gen { text: [], data: [], locals: {}, frame: 0, label_id: 0, str_id: 0 };
    gen.emit("    .text");
    for (let f in prog.funcs) {
        gen_function(f, gen);
    }
    let out: string[] = [];
    for (let l in gen.text) {
        out.push(l);
    }
    if (gen.data.length() > 0) {
        out.push("    .section .rodata");
        for (let d in gen.data) {
            out.push(d);
        }
    }
    out.join("\n") + "\n"
}
