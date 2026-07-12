package process

import (
	"io"
	"log/slog"
)

// newNopLogger returns a logger that discards all output, used in tests.
func newNopLogger() *slog.Logger {
	return slog.New(slog.NewTextHandler(io.Discard, nil))
}
