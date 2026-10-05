/// Bumped with the Makefile's VERSION at release time; `scripts/release-notes.sh` fails CI when the two differ.
enum Version {
    static let number = "0.4.0"
    #if DEBUG
        static let string = number + "-dev"
    #else
        static let string = number
    #endif
}
