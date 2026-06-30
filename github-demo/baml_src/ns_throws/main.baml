function main(full_name: string) -> string {
    //# Get the first and last name
    let name_parts = child(full_name) catch (e) {
        string => {throw "error"}
    }

    //# Return greeting
    return "Hello, " + name_parts[0] + ". Your full name is " + full_name + "!";
}

function child(full_name: string) -> string[] throws string{
    //# Extract name parts
    let name_parts = full_name.split(" ");
    //# Check name_parts
    if (name_parts.length() != 2) {
        //# throw: names too big
        throw "Full name must have exactly two parts";
    } else {
        return name_parts;
    }
}

