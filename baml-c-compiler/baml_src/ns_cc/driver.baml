// Driver — the entry points. `compile` returns assembly text; `emit` prints it;
// `run` assembles + links it with gcc and runs the result.

function compile_inner(src: string) -> string throws CError {
    let toks = tokenize(src);
    let prog = parse(toks);
    codegen(prog)
}

function compile_source(src: string) -> string {
    compile_inner(src) catch (e) {
        CError => "// compile error: " + e.message + "\n"
    }
}

function compile(path: string) -> string {
    let src = baml.fs.read(path) catch (e) {
        _ => ""
    };
    if (src.char_count() == 0) {
        return "// error: could not read " + path + "\n";
    };
    compile_source(src)
}

// Compile `src` (a .c path) and write the raw assembly to `dst` (a .s path).
function compile_to(src: string, dst: string) -> string {
    let asm = compile(src);
    let written = baml.fs.write(dst, asm) catch (e) {
        _ => 0 - 1
    };
    if (written < 0) {
        return "error: could not write " + dst;
    };
    "wrote " + string.from(written) + " bytes of assembly to " + dst
}

// The full pipeline in one shot: compile `src` to assembly, assemble + link it
// with the system `gcc`, run the resulting binary, and report what happened.
function build_and_run(src: string) -> string {
    let asm = compile(src);
    let s_path = "/tmp/baml_cc_out.s";
    let bin_path = "/tmp/baml_cc_out";
    baml.fs.write(s_path, asm) catch (e) {
        _ => 0
    };
    let build = baml.sys.shell("gcc " + s_path + " -o " + bin_path, null);
    if (!build.ok()) {
        return "assemble/link failed:\n" + build.stderr.to_string();
    };
    let run = baml.sys.shell(bin_path, null);
    "--- program output ---\n"
        + run.stdout.to_string()
        + "--- exit code: "
        + string.from(run.exit_code)
        + " ---\n"
}

// Print the x86-64 assembly our compiler emits for a C source file.
function emit(path: string) -> null {
    baml.io.print(compile(path));
    null
}

// Compile a C file, assemble + link it with gcc, run it, print its output.
function run(path: string) -> null {
    baml.io.print(build_and_run(path));
    null
}
