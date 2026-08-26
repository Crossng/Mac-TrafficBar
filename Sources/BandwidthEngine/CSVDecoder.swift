import Foundation

enum CSVDecoder {
    static func fields(in line: Substring) -> [String] {
        var output: [String] = []
        var field = ""
        var quoted = false
        var characters = line.makeIterator()

        while let character = characters.next() {
            if character == "\"" {
                if quoted, let next = characters.next() {
                    if next == "\"" {
                        field.append("\"")
                    } else {
                        field.append("\"")
                        field.append(next)
                    }
                } else {
                    quoted.toggle()
                }
            } else if character == "," && !quoted {
                output.append(field)
                field.removeAll(keepingCapacity: true)
            } else {
                field.append(character)
            }
        }

        output.append(field)
        return output
    }
}
