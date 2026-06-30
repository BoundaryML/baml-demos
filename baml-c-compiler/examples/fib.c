int fib(int n) {
    if (n < 2) {
        return n;
    }
    return fib(n - 1) + fib(n - 2);
}

int main(void) {
    int i = 0;
    while (i <= 10) {
        printf("fib(%d) = %d\n", i, fib(i));
        i = i + 1;
    }
    return 0;
}
