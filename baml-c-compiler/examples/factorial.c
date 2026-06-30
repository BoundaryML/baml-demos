int fact(int n) {
    if (n <= 1) {
        return 1;
    }
    return n * fact(n - 1);
}

int main(void) {
    int n = 1;
    while (n <= 10) {
        printf("%d! = %d\n", n, fact(n));
        n = n + 1;
    }
    return 0;
}
