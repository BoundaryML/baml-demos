// AST — expressions and statements are each a union of small node classes that
// the parser builds and the code generator pattern-matches with `match`.

class IntLit {
    value: int,
}

class StrLit {
    value: string,
}

class VarRef {
    name: string,
}

class Assign {
    name: string,
    value: Expr,
}

class UnaryOp {
    op: string,
    operand: Expr,
}

class BinOp {
    op: string,
    lhs: Expr,
    rhs: Expr,
}

class Call {
    name: string,
    args: Expr[],
}

type Expr = IntLit | StrLit | VarRef | Assign | UnaryOp | BinOp | Call;

class ReturnStmt {
    value: Expr,
}

class ExprStmt {
    expr: Expr,
}

class VarDecl {
    name: string,
    init: Expr,
}

class IfStmt {
    cond: Expr,
    then_body: Stmt[],
    else_body: Stmt[],
}

class WhileStmt {
    cond: Expr,
    body: Stmt[],
}

type Stmt = ReturnStmt | ExprStmt | VarDecl | IfStmt | WhileStmt;

class Function {
    name: string,
    params: string[],
    body: Stmt[],
}

class Program {
    funcs: Function[],
}
