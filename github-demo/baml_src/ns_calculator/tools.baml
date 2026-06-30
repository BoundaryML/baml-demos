class DivisionByZeroError {}

function add(a: int, b: int) -> int {
    return a + b;
}

function subtract(a: int, b: int) -> int {
    return a - b;
}

function multiply(a: int, b: int) -> int {
    return a * b;
}

function divide(a: int, b: int) -> int {
    if (b == 0) {
        throw DivisionByZeroError{};
    }

    return a / b;
}