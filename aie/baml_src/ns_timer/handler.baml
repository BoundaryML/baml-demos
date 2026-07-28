function with_timeout<T, E>(millis: int, f: () -> T throws E) -> T {
    let work = spawn {
        f()
    };
    let timer = spawn { 
        baml.sys.sleep(baml.time.Duration.from_milliseconds(millis));
        work.cancel();
        throw TimeoutError { message: `Operation timed out after ${millis} milliseconds` };
    };

    let result = baml.future.race<T, TimeoutError | E>([work, timer]);
    await result
}

class TimeoutError {
    message: string,

    implements baml.ToString {
        function to_string(self) -> string throws never {
            return self.message;
        }
    }
}

function exit() -> void {
    baml.sys.exit(0);
}

class Location {
    city: string?,
    country_code: string?,
    zip_code: string?,
    latitude: float?,
    longitude: float?,
    citation: string @description("exact quote in the text"),
}

function is_user_selecting_by_location(text: string) -> Location[] {
    client: "openai/gpt-4o-mini"
    prompt: `
        Is the user pruning location: ${text}?

        ${ctx.output_format}
    `
}
