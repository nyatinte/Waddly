let url = URL(fileURLWithPath: "/tmp/waddly-check")
try? (result: FileManager.default.removeItem(at: url))
