// Lexer — turn C source text into a flat list of tokens.

enum TokKind {
    Int,
    Str,
    Ident,
    KwInt,
    KwReturn,
    KwVoid,
    KwIf,
    KwElse,
    KwWhile,
    Plus,
    Minus,
    Star,
    Slash,
    Percent,
    Assign,
    Eq,
    Ne,
    Lt,
    Le,
    Gt,
    Ge,
    LParen,
    RParen,
    LBrace,
    RBrace,
    Semi,
    Comma,
    Eof,
}

class Token {
    kind: TokKind,
    text: string,
    ival: int,
}

function tok(k: TokKind, t: string) -> Token {
    Token { kind: k, text: t, ival: 0 }
}

function keyword_kind(s: string) -> TokKind {
    if (s == "int") {
        return TokKind.KwInt;
    };
    if (s == "return") {
        return TokKind.KwReturn;
    };
    if (s == "void") {
        return TokKind.KwVoid;
    };
    if (s == "if") {
        return TokKind.KwIf;
    };
    if (s == "else") {
        return TokKind.KwElse;
    };
    if (s == "while") {
        return TokKind.KwWhile;
    };
    TokKind.Ident
}

function single_char_kind(c: string) -> TokKind throws CError {
    if (c == "+") {
        return TokKind.Plus;
    };
    if (c == "-") {
        return TokKind.Minus;
    };
    if (c == "*") {
        return TokKind.Star;
    };
    if (c == "/") {
        return TokKind.Slash;
    };
    if (c == "%") {
        return TokKind.Percent;
    };
    if (c == "=") {
        return TokKind.Assign;
    };
    if (c == "<") {
        return TokKind.Lt;
    };
    if (c == ">") {
        return TokKind.Gt;
    };
    if (c == "(") {
        return TokKind.LParen;
    };
    if (c == ")") {
        return TokKind.RParen;
    };
    if (c == "{") {
        return TokKind.LBrace;
    };
    if (c == "}") {
        return TokKind.RBrace;
    };
    if (c == ";") {
        return TokKind.Semi;
    };
    if (c == ",") {
        return TokKind.Comma;
    };
    throw CError { message: "unexpected character '" + c + "'" }
}

function tokenize(src: string) -> Token[] throws CError {
    let toks: Token[] = [];
    let n = src.char_count();
    let i = 0;
    while (i < n) {
        let c = src.char_at(i);
        if (c.is_ascii_whitespace()) {
            i += 1;
        } else if (c.is_ascii_numeric()) {
            let start = i;
            while (i < n && src.char_at(i).is_ascii_numeric()) {
                i += 1;
            }
            let text = src.substring(start, i);
            let value = int.parse(text) catch (e) {
                _ => 0
            };
            toks.push(Token { kind: TokKind.Int, text: text, ival: value });
        } else if (c.is_ascii_alphabetic() || c == "_") {
            let start = i;
            while (i < n && (src.char_at(i).is_ascii_alphanumeric() || src.char_at(i) == "_")) {
                i += 1;
            }
            let text = src.substring(start, i);
            toks.push(Token { kind: keyword_kind(text), text: text, ival: 0 });
        } else if (c == "\"") {
            i += 1;
            let parts: string[] = [];
            while (i < n && src.char_at(i) != "\"") {
                let ch = src.char_at(i);
                if (ch == "\\" && i + 1 < n) {
                    parts.push(ch);
                    parts.push(src.char_at(i + 1));
                    i += 2;
                } else {
                    parts.push(ch);
                    i += 1;
                }
            }
            if (i >= n) {
                throw CError { message: "unterminated string literal" };
            };
            i += 1;
            toks.push(Token { kind: TokKind.Str, text: parts.join(""), ival: 0 });
        } else {
            let two = if (i + 1 < n) {
                c + src.char_at(i + 1)
            } else {
                c
            };
            if (two == "==") {
                toks.push(tok(TokKind.Eq, "=="));
                i += 2;
            } else if (two == "!=") {
                toks.push(tok(TokKind.Ne, "!="));
                i += 2;
            } else if (two == "<=") {
                toks.push(tok(TokKind.Le, "<="));
                i += 2;
            } else if (two == ">=") {
                toks.push(tok(TokKind.Ge, ">="));
                i += 2;
            } else {
                toks.push(Token { kind: single_char_kind(c), text: c, ival: 0 });
                i += 1;
            };
        }
    }
    toks.push(Token { kind: TokKind.Eof, text: "", ival: 0 });
    toks
}
