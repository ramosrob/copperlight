import Foundation

/// The open source Copperlight is built with. Their MIT licenses ask for their notices in the app, so Settings › About
/// shows each one's copyright line with the license below them. A new package needs a line here (a test checks).
struct Acknowledgement: Identifiable {
    let package: String
    let copyright: String
    let url: URL
    var id: String { package }
}

let acknowledgements = [
    Acknowledgement(package: "KeyboardShortcuts", copyright: "Copyright (c) Sindre Sorhus <sindresorhus@gmail.com> (https://sindresorhus.com)",
                    url: URL(string: "https://github.com/sindresorhus/KeyboardShortcuts")!),
    Acknowledgement(package: "Expression", copyright: "Copyright (c) 2016 Nick Lockwood",
                    url: URL(string: "https://github.com/nicklockwood/Expression")!),
    Acknowledgement(package: "TOMLKit", copyright: "Copyright (c) 2024 Jeff Lebrun",
                    url: URL(string: "https://github.com/LebJe/TOMLKit")!),
    Acknowledgement(package: "toml++", copyright: "Copyright (c) Mark Gillard <mark.gillard@outlook.com.au>", // inside TOMLKit
                    url: URL(string: "https://github.com/marzer/tomlplusplus")!),
    Acknowledgement(package: "GRDB", copyright: "Copyright (C) 2015-2025 Gwendal Roué",
                    url: URL(string: "https://github.com/groue/GRDB.swift")!),
]

/// The MIT License, the same text for all of them.
let mitLicense = """
    Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated \
    documentation files (the "Software"), to deal in the Software without restriction, including without limitation \
    the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to \
    permit persons to whom the Software is furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all copies or substantial portions of \
    the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE \
    WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS \
    OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR \
    OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
    """
