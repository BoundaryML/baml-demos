class Greeting {
    name: string,

    function say_hi(self) -> string {
        return `hi ${self.name} from 🐑 baml`;
    }
}

class ScrapeResult {
    url: string,
    content: string,
}

function retry<T>(max_attempts: int, f: () -> T) -> T {
    let last_error = null;
    while (max_attempts > 0) {
        f() catch (e) {
            _ => {
                max_attempts = max_attempts - 1;

                if (max_attempts == 0) {
                    throw e
                };
                baml.sys.sleep(baml.time.Duration.from_milliseconds(1000)) catch (e) {
                    _ => {}
                }
            }
        }
    }

    baml.sys.panic("unreachable code");
}

function test_retry() -> void {
    retry(3, do_something);
}

class InvalidNumber {
    value: int,
}

function do_something() -> int {
    let x = int.random(0, 10) catch (e) {
        _ => 0
    };
    if (x < 5) {
        return 5;
    }

    throw InvalidNumber { value: x };
}

function process_url(url: string) -> ScrapeResult throws never {
    let counter = int.random(0, 500) catch (e) {
        _ => 50
    };
    log.info(`processing ${url} with delay ${1000 + counter}`);
    baml.sys.sleep(baml.time.Duration.from_milliseconds(1000 + counter)) catch (e) {
        _ => {}
    };
    ScrapeResult { url: url, content: `my content for ${url}` }
}

function scrape_urls(urls: string[]) -> void {
    let group = baml.spawn.TaskGroup.new(5);

    let results = urls.map((url) -> {
        spawn { process_url(url) }
    });

    baml.sys.sleep(baml.time.Duration.from_milliseconds(1400));
    results[1].cancel();

    let result = await baml.future.all(results);
    for (let r in result) {
        log.info(`result: ${r.url} with content: ${r.content}`);
    }
}

function main() -> void {
    scrape_urls(["https://www.google.com", "https://www.yahoo.com", "https://www.bing.com"]);
}

class PythonObject {
    say_hi: () -> string throws never,
}

function call_me(o: PythonObject) -> string {
    `hi ${o.say_hi()} from baml`
}

function d(d: unknown) -> string {
    return `hi ${d} from baml`;
}
