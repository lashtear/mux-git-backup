This is a backup script for archiving TinyMUX game state in a Git
repository.  This allows for fast, efficient, concise storage and
distribution of backup data, as well as retrieval of any past state.

In most mush environments, the script can run without any
configuration beyond what is present in the conf file.  Optionally, it
can use Brazil's OMEGA tool to extract attributes from the game
flatfile to verify the dump is not stale.

This tool is not yet designed to work on MUSH/MUD/MOO/MUCK types other
than TinyMUX, though certainly all of them could benefit for the same
reasons.  SQL inclusion is planned but not currently written.
