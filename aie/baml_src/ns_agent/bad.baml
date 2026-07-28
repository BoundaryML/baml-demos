// class Data {
//     result: string | null,
//     tool: Tool1 | Tool2
// }

// class Tool1 {
//     paramA: string,
//     paramB: string
// }

// class Tool2 {
//     paramA: string,
//     paramB: string
// }

// function llm_thing(input: string) -> Data {
//     throw baml.errors.InvalidArgument{}
// }

// function update(d: Data) -> void {
//     d.result = null
// }

// function do_stuff(input: string) -> void {
//     let x = llm_thing(input);
//     let Data { result: let result: string, tool} = x else {
//         return;
//     }
//     while (result) {
//         update(x);
//         let y = result;
//     }
// }

// function do_stuff(x: Data[]) -> void {
//     while (x[0].result) {
//         let y = x[0].result;
//     }
// }
