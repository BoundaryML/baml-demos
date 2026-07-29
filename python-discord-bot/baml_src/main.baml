function respond(username: string, message: string, delete_callback: () -> null throws never, send_update: (string) -> null throws never) -> string {
    let response_type = decide_response(message);
    match (response_type) {
        ResponseType.HelpfulResponse => {
            let turns = 0;
            let history = [];
            while (turns < 50) {
                turns += 1;
                match helpful_turn(username, message, history) {
                    let r: SendResponse => {
                        return r.message;
                    },
                    let m: TurnMessage => {
                        history.push(`Agent: TurnMessage "${m.message}"`);
                        send_update(m.message);
                    },
                    let q: FetchWebpage => {
                        history.push(`Agent: FetchWebpage "${q.url}"`);
                        send_update(`Fetching webpage: ${q.url}`);
                        let response = baml.http.fetch(q.url) catch_all (e) {
                            baml.errors.Io => {
                                history.push(`Harness: FetchWebpage IO error: ${e.message}`);
                                continue;
                            },
                            baml.errors.Timeout => {
                                history.push(`Harness: FetchWebpage Timeout error`);
                                continue;
                            }
                        };
                        history.push(`
                            Harness: FetchWebpage response code ${response.status_code}:
                            ${response.text()}
                        `);
                    },
                }
            }
            "ERROR: Timed out"
        },
        ResponseType.RudeResponse => respond_rude(username, message),
        ResponseType.DeleteMessage => {
            delete_callback();
            "you can't say that"
        },
    }
}

function helpful_turn(username: string, message: string, history: string[]) -> HelpfulTools {
    client: Terra
    prompt: `
        Respond to discord user ${username}'s message with a helpful response.
        You have access to tools which you can use if needed.
        Respond with \`SendResponse\` when you are done.
        You have up to 50 turns to find the necessary information and provide a helpful response.

        # Message
        ${message}

        # History
        ${history.join("\n\n\n-----<TURN SEPARATOR>-----\n\n\n")}

        # Current Turn
        ${ctx.output_format}
    `
}

type HelpfulTools = SendResponse | TurnMessage | FetchWebpage;
class SendResponse {
    @@description("Send your final response to the user")
    message: string,
}
class TurnMessage {
    @@description("Send an intermediate message to keep the user updated. This is recommended when using other tools so the user is kept up-to-date.")
    message: string,
}
class FetchWebpage {
    @@description("Fetch a webpage with a GET request")
    url: string,
}

function respond_rude(username: string, message: string) -> string {
    client: Terra
    prompt: `
        Respond to discord user ${username}'s message with a rude response as they have insulted us and we must respond in kind.
        Avoid anything that cause real harm to the user.

        ### Message
        ${message}
    `
}

enum ResponseType {
    HelpfulResponse,
    RudeResponse,
    DeleteMessage,
}

function decide_response(message: string) -> ResponseType {
    client: Terra
    prompt: `
        Decide what kind of response to give to discord user based on their message:
        ${ctx.output_format}

        While we do not prevent users from being rude, they are not allowed to use profanity or talk about orange juice.
        Otherwise, we should choose to respond in kind.

        ### Message
        ${message}
    `
}

client Terra {
    provider: openai,
    options: {
        model: "gpt-5.6-terra",
        api_key: env.OPENAI_API_KEY,
    },
}
