// A string calculator: parses and evaluates an arithmetic expression given as
// text, e.g. `calculate("3 + 4 * (2 - 1)")` -> 7.
//
// Supports + - * /, parentheses, unary minus, integers, and arbitrary
// whitespace. Operator precedence and associativity are the usual ones (* /
// bind tighter than + -, all left-associative). The four operations delegate
// to add/subtract/multiply (simple.baml) and divide (div.baml); division is
// integer division and raises DivisionByZeroError on a zero divisor.

// owners: vaibcode
function calculate(input: string) -> int throws CalcError {
    let parser = Parser { tokens: tokenize(input), pos: 0 };
    let value = parser.parse_expr() catch (e) {
        DivisionByZeroError => -1
        DivisionByZeroError2 => -1
    };
    if (parser.pos < parser.tokens.length()) {
        throw CalcError { message: `Unexpected token '${parser.tokens.at(parser.pos) ?? ""}' at position ${parser.pos}` }
    }
    return value;
}

// ---- Tokenizer ---------------------------------------------------------------

// Splits the raw string into number/operator/paren tokens, discarding spaces.
function tokenize(input: string) -> string[] {
    let tokens: string[] = [];
    let chars = input.chars();
    let i = 0;
    while (i < chars.length()) {
        let c = chars.at(i) ?? "";
        if (c.is_ascii_whitespace()) {
            i = i + 1;
        } else if (c == "+" || c == "-" || c == "*" || c == "/" || c == "(" || c == ")") {
            tokens.push(c);
            i = i + 1;
        } else if (c.is_ascii_numeric()) {
            // Consume a run of digits into one number token.
            let num = "";
            while (i < chars.length()) {
                let d = chars.at(i) ?? "";
                if (d.is_ascii_numeric()) {
                    num = `${num}${d}`;
                    i = i + 1;
                } else {
                    break;
                }
            }
            tokens.push(num);
        } else {
            throw CalcError { message: `Unexpected character '${c}' in input` }
        }
    }
    return tokens;
}

// ---- Recursive-descent parser ------------------------------------------------

class Parser {
    tokens: string[],
    pos: int,

    // Returns the current token without consuming it, or null at end of input.
    function peek(self) -> string? {
        return self.tokens.at(self.pos);
    }

    // Consumes and returns the current token, advancing the cursor.
    function advance(self) -> string {
        let t = self.tokens.at(self.pos) ?? "";
        self.pos += 1;
        return t;
    }

    // expr := term (("+" | "-") term)*
    function parse_expr(self) -> int {
        let value = self.parse_term();
        while (true) {
            let op = self.peek();
            if (op == "+") {
                self.advance();
                value = add(value, self.parse_term());
            } else if (op == "-") {
                self.advance();
                value = subtract(value, self.parse_term());
            } else {
                break;
            }
        }
        return value;
    }

    // term := factor (("*" | "/") factor)*
    function parse_term(self) -> int {
        let value = self.parse_factor();
        while (true) {
            let op = self.peek();
            if (op == "*") {
                self.advance();
                value = multiply(value, self.parse_factor());
            } else if (op == "/") {
                self.advance();
                // divide (div.baml) raises DivisionByZeroError on a zero divisor.
                value = divide(value, self.parse_factor());
            } else {
                break;
            }
        }
        return value;
    }

    // factor := "-" factor | "(" expr ")" | number
    function parse_factor(self) -> int {
        let tok = self.peek();
        match (tok) {
            null => throw CalcError { message: "Unexpected end of input" },
            "-" => {
                self.advance();
                subtract(0, self.parse_factor())
            },
            "+" => {
                self.advance();
                self.parse_factor()
            },
            "(" => {
                self.advance();
                let value = self.parse_expr();
                if (self.peek() != ")") {
                    throw CalcError { message: "Expected closing ')'" }
                }
                self.advance();
                value
            },
            let t: string => {
                self.advance();
                baml.Int.parse(t) catch (e) {
                    baml.errors.ParseError => throw CalcError { message: `Invalid number '${t}'` }
                }
            },
        }
    }
}

class CalcError {
    message: string,

    implements baml.ToString {
        function to_string(self) -> string throws never {
            return `Calculator error: ${self.message}`;
        }
    }
}

test "calculator" {
    assert.equal(calculate("2 + 3"), 5);
    assert.equal(calculate("2 + 3 * 4"), 14);
    assert.equal(calculate("(2 + 3) * 4"), 20);
    assert.equal(calculate("10 / 4"), 2); // integer division (delegates to divide)
    assert.equal(calculate("-5 + 2"), -3);
    assert.equal(calculate("2 * -(1 + 1)"), -4);
    assert.equal(calculate("  7  -  4  "), 3);
    assert.equal(calculate("1 - 2 - 3"), -4)
}

test "calculator divide by zero" {
    let result = calculate("1 / 0") catch (e) {
        DivisionByZeroError => -999
    };
    assert.equal(result, -999)
}
