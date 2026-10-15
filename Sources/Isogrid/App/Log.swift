import os

/// `log stream --predicate 'subsystem == "dev.isogrid.Isogrid"'` shows what Isogrid reports.
nonisolated let log = Logger(subsystem: "dev.isogrid.Isogrid", category: "app")
