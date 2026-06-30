// Shared code-generation context used by every backend: an assembly buffer
// (text + data sections), a per-function local-variable layout, and label /
// string-literal counters. The instruction-emitting methods cover both the
// GNU/ELF dialect (`add_string`, `new_label`) and the Mach-O dialect
// (`add_cstring`, `new_label_macho`).

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

    // Mach-O variant: `L`-prefixed local labels and a null-terminated `.asciz`.
    function new_label_macho(self, base: string) -> string {
        let l = "L" + base + string.from(self.label_id);
        self.label_id += 1;
        l
    }

    function add_cstring(self, raw: string) -> string {
        let label = "Lstr" + string.from(self.str_id);
        self.str_id += 1;
        self.data.push(label + ":");
        self.data.push("    .asciz \"" + raw + "\"");
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

// Walk a function body and assign a stack slot to each local variable
// declaration. Target-independent — both backends share the same frame layout.
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
