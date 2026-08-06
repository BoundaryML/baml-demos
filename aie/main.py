import time
import baml_sdk as root


def main():
    equation = input("Enter a mathematical expression: ")
    result = root.math.calculate(equation)
    print(f"Result: {result}")




















async def main_async():
    equation = input("Enter a mathematical expression: ")
    result = await root.math.calculate_async(equation)
    print(f"Result: {result}")














def safe_python():
    def work() -> str:
        time.sleep(10)
        return "Done"

    # Set a timeout of 1000 milliseconds (1 second)
    result = root.timer.with_timeout(1000, work)
    print(f"Result: {result}")








def class_test(c: root.hello.Greeting):
    c.say_hi()
    c.say_hi_async()
    



class Demo(Exception):
    def __init__(self, name: str):
        self.name = name


class Decimal:
    def __init__(self, value: int):
        self.value = value

def call_me():
    # print(root.hello.d(Demo("scott")))
    def demo() -> str:
        obj = Demo("this is a bad error")
        print("id:", id(obj))
        raise obj
    o = root.hello.PythonObject(say_hi=demo)

    try:
        print(root.hello.call_me(o))
    except Demo as e:
        print("Caught exception:", e.name, "id:", id(e))






if __name__ == "__main__":
    call_me()