// Parser — recursive descent with precedence climbing for expressions.
// Syntax errors surface as typed `throws CError`.

class Parser {
    toks: Token[],
    pos: int,

    function cur(self) -> Token {
        self.toks.at(self.pos) ?? Token { kind: TokKind.Eof, text: "", ival: 0 }
    }

    function peek(self, k: int) -> Token {
        self.toks.at(self.pos + k) ?? Token { kind: TokKind.Eof, text: "", ival: 0 }
    }

    function eat(self, k: TokKind) -> Token throws CError {
        let t = self.cur();
        if (t.kind != k) {
            throw CError { message: "syntax error: unexpected '" + t.text + "'" };
        };
        self.pos += 1;
        t
    }

    function parse_primary(self) -> Expr throws CError {
        let t = self.cur();
        if (t.kind == TokKind.Int) {
            self.pos += 1;
            return IntLit { value: t.ival };
        };
        if (t.kind == TokKind.Str) {
            self.pos += 1;
            return StrLit { value: t.text };
        };
        if (t.kind == TokKind.Minus) {
            self.pos += 1;
            return UnaryOp { op: "-", operand: self.parse_primary() };
        };
        if (t.kind == TokKind.LParen) {
            self.pos += 1;
            let inner = self.parse_expr();
            self.eat(TokKind.RParen);
            return inner;
        };
        if (t.kind == TokKind.Ident) {
            self.pos += 1;
            if (self.cur().kind == TokKind.LParen) {
                self.pos += 1;
                let args: Expr[] = [];
                while (self.cur().kind != TokKind.RParen && self.cur().kind != TokKind.Eof) {
                    args.push(self.parse_expr());
                    if (self.cur().kind == TokKind.Comma) {
                        self.pos += 1;
                    };
                }
                self.eat(TokKind.RParen);
                return Call { name: t.text, args: args };
            };
            return VarRef { name: t.text };
        };
        throw CError { message: "expected an expression, found '" + t.text + "'" }
    }

    function parse_mul(self) -> Expr throws CError {
        let lhs = self.parse_primary();
        while (true) {
            let k = self.cur().kind;
            if (k == TokKind.Star || k == TokKind.Slash || k == TokKind.Percent) {
                let op = self.cur().text;
                self.pos += 1;
                lhs = BinOp { op: op, lhs: lhs, rhs: self.parse_primary() };
            } else {
                break;
            };
        }
        lhs
    }

    function parse_add(self) -> Expr throws CError {
        let lhs = self.parse_mul();
        while (true) {
            let k = self.cur().kind;
            if (k == TokKind.Plus || k == TokKind.Minus) {
                let op = self.cur().text;
                self.pos += 1;
                lhs = BinOp { op: op, lhs: lhs, rhs: self.parse_mul() };
            } else {
                break;
            };
        }
        lhs
    }

    function parse_relational(self) -> Expr throws CError {
        let lhs = self.parse_add();
        while (true) {
            let k = self.cur().kind;
            if (k == TokKind.Lt || k == TokKind.Le || k == TokKind.Gt || k == TokKind.Ge) {
                let op = self.cur().text;
                self.pos += 1;
                lhs = BinOp { op: op, lhs: lhs, rhs: self.parse_add() };
            } else {
                break;
            };
        }
        lhs
    }

    function parse_equality(self) -> Expr throws CError {
        let lhs = self.parse_relational();
        while (true) {
            let k = self.cur().kind;
            if (k == TokKind.Eq || k == TokKind.Ne) {
                let op = self.cur().text;
                self.pos += 1;
                lhs = BinOp { op: op, lhs: lhs, rhs: self.parse_relational() };
            } else {
                break;
            };
        }
        lhs
    }

    function parse_assign(self) -> Expr throws CError {
        if (self.cur().kind == TokKind.Ident && self.peek(1).kind == TokKind.Assign) {
            let name = self.cur().text;
            self.pos += 2;
            return Assign { name: name, value: self.parse_assign() };
        };
        self.parse_equality()
    }

    function parse_expr(self) -> Expr throws CError {
        self.parse_assign()
    }

    function parse_block(self) -> Stmt[] throws CError {
        self.eat(TokKind.LBrace);
        let stmts: Stmt[] = [];
        while (self.cur().kind != TokKind.RBrace && self.cur().kind != TokKind.Eof) {
            stmts.push(self.parse_stmt());
        }
        self.eat(TokKind.RBrace);
        stmts
    }

    function parse_stmt(self) -> Stmt throws CError {
        let k = self.cur().kind;
        if (k == TokKind.KwReturn) {
            self.pos += 1;
            let e = self.parse_expr();
            self.eat(TokKind.Semi);
            return ReturnStmt { value: e };
        };
        if (k == TokKind.KwInt) {
            self.pos += 1;
            let name = self.eat(TokKind.Ident).text;
            self.eat(TokKind.Assign);
            let init = self.parse_expr();
            self.eat(TokKind.Semi);
            return VarDecl { name: name, init: init };
        };
        if (k == TokKind.KwIf) {
            self.pos += 1;
            self.eat(TokKind.LParen);
            let cond = self.parse_expr();
            self.eat(TokKind.RParen);
            let then_body = self.parse_block();
            let else_body: Stmt[] = [];
            if (self.cur().kind == TokKind.KwElse) {
                self.pos += 1;
                else_body = self.parse_block();
            };
            return IfStmt { cond: cond, then_body: then_body, else_body: else_body };
        };
        if (k == TokKind.KwWhile) {
            self.pos += 1;
            self.eat(TokKind.LParen);
            let cond = self.parse_expr();
            self.eat(TokKind.RParen);
            return WhileStmt { cond: cond, body: self.parse_block() };
        };
        let e = self.parse_expr();
        self.eat(TokKind.Semi);
        ExprStmt { expr: e }
    }

    function parse_function(self) -> Function throws CError {
        self.eat(TokKind.KwInt);
        let name = self.eat(TokKind.Ident).text;
        self.eat(TokKind.LParen);
        let params: string[] = [];
        if (self.cur().kind == TokKind.KwVoid) {
            self.pos += 1;
        } else {
            while (self.cur().kind != TokKind.RParen && self.cur().kind != TokKind.Eof) {
                self.eat(TokKind.KwInt);
                params.push(self.eat(TokKind.Ident).text);
                if (self.cur().kind == TokKind.Comma) {
                    self.pos += 1;
                };
            }
        };
        self.eat(TokKind.RParen);
        Function { name: name, params: params, body: self.parse_block() }
    }
}

function parse(toks: Token[]) -> Program throws CError {
    let p = Parser { toks: toks, pos: 0 };
    let funcs: Function[] = [];
    while (p.cur().kind != TokKind.Eof) {
        funcs.push(p.parse_function());
    }
    Program { funcs: funcs }
}
