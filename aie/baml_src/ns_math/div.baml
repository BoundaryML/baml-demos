function divide(a: int, b: int) -> int {
    if (b == 0) {
        throw DivisionByZeroError2 { numerator: a }
    }
    return a / b;
}

class DivisionByZeroError {
    numerator: int,

    implements baml.ToString {
        function to_string(self) -> string throws never {
            return `Division by zero error: cannot divide ${self.numerator} by zero.`;
        }
    }
}

class DivisionByZeroError2 {
    numerator: int,

    implements baml.ToString {
        function to_string(self) -> string throws never {
            return `Division by zero error: cannot divide ${self.numerator} by zero.`;
        }
    }
}
