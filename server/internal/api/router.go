package api

import (
	"bufio"
	"fmt"
	"log/slog"
	"net"
	"net/http"
	"strings"
	"time"

	"github.com/ametis70/launchscope/server/internal/apps"
	"github.com/ametis70/launchscope/server/internal/cec"
	"github.com/ametis70/launchscope/server/internal/config"
	"github.com/ametis70/launchscope/server/internal/events"
	"github.com/ametis70/launchscope/server/internal/process"
)

// NewRouter wires all API routes and returns an http.Handler.
func NewRouter(
	mgr *process.Manager,
	cfgLoader *config.Loader,
	appsLoader *apps.Loader,
	bus *events.Bus,
	log *slog.Logger,
) http.Handler {
	apiKey := cfgLoader.Current().API.APIKey

	h := &handlers{mgr: mgr, cfgLoader: cfgLoader, appsLoader: appsLoader, log: log}
	ws := &wsHandler{bus: bus}

	// Build CEC client if enabled.
	var cecClient *cec.Client
	if cfgLoader.Current().CEC.Enabled {
		cecClient = cec.New()
	}

	mux := http.NewServeMux()

	// Status
	mux.HandleFunc("GET /api/status", h.getStatus)

	// Apps
	mux.HandleFunc("GET /api/apps", h.getApps)

	// Process control
	mux.HandleFunc("POST /api/launch/{id}", h.postLaunch)
	mux.HandleFunc("POST /api/stop", h.postStop)

	// Audio
	mux.HandleFunc("GET /api/audio", h.getAudio)
	mux.HandleFunc("POST /api/audio/volume", h.postAudioVolume)
	mux.HandleFunc("POST /api/audio/mute", h.postAudioMute)

	// CEC
	mux.HandleFunc("POST /api/cec/activate",   makeCECActivateHandler(cecClient, log))
	mux.HandleFunc("POST /api/cec/power-on",   makeCECPowerOnHandler(cecClient, log))
	mux.HandleFunc("POST /api/cec/set-source", makeCECSetSourceHandler(cecClient, log))
	mux.HandleFunc("POST /api/cec/standby",    makeCECStandbyHandler(cecClient, log))

	// Daemon config (read-only; API key is redacted)
	mux.HandleFunc("GET /api/config", h.getConfig)

	// System
	mux.HandleFunc("POST /api/system/power", h.postPower)

	// WebSocket
	mux.HandleFunc("GET /ws", ws.ServeHTTP)

	// Middleware chain (outermost first): logging → auth → mux
	return loggingMiddleware(log, authMiddleware(apiKey, mux))
}

// responseRecorder wraps http.ResponseWriter to capture the status code.
// It also forwards Hijack calls so WebSocket upgrades work through the
// logging middleware.
type responseRecorder struct {
	http.ResponseWriter
	status int
}

func (rr *responseRecorder) WriteHeader(code int) {
	rr.status = code
	rr.ResponseWriter.WriteHeader(code)
}

func (rr *responseRecorder) Write(b []byte) (int, error) {
	if rr.status == 0 {
		rr.status = http.StatusOK
	}
	return rr.ResponseWriter.Write(b)
}

// Hijack implements http.Hijacker by delegating to the underlying
// ResponseWriter. Required for WebSocket upgrades through the logging
// middleware.
func (rr *responseRecorder) Hijack() (net.Conn, *bufio.ReadWriter, error) {
	h, ok := rr.ResponseWriter.(http.Hijacker)
	if !ok {
		return nil, nil, fmt.Errorf("underlying ResponseWriter does not implement http.Hijacker")
	}
	return h.Hijack()
}

func loggingMiddleware(log *slog.Logger, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		rr := &responseRecorder{ResponseWriter: w}
		next.ServeHTTP(rr, r)
		status := rr.status
		if status == 0 {
			status = http.StatusOK
		}
		// Use Debug for the high-frequency status poll to avoid log noise,
		// Info for everything else.
		logFn := log.Info
		if r.URL.Path == "/api/status" {
			logFn = log.Debug
		}
		logFn("http",
			"method", r.Method,
			"path", r.URL.Path,
			"status", status,
			"remote", r.RemoteAddr,
			"duration", time.Since(start),
		)
	})
}

func authMiddleware(apiKey string, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if isLocalhost(r) {
			next.ServeHTTP(w, r)
			return
		}
		key := r.Header.Get("X-Api-Key")
		if key == "" {
			key = r.URL.Query().Get("apikey")
		}
		if key != apiKey {
			jsonError(w, "unauthorized", http.StatusUnauthorized)
			return
		}
		next.ServeHTTP(w, r)
	})
}

// isLocalhost reports whether the request originated from the loopback
// interface. It strips the port from r.RemoteAddr (format "host:port" for TCP,
// "[::1]:port" for IPv6) before comparing. This bypasses API-key authentication
// for processes on the same machine (the UI, system scripts, etc.).
//
// Note: r.RemoteAddr reflects the TCP peer address. It is not spoofable in a
// direct connection, but may show a proxy's address in reverse-proxy setups —
// in that case all proxied requests would bypass auth. Do not put this server
// behind a reverse proxy without adding explicit auth at the proxy layer.
func isLocalhost(r *http.Request) bool {
	addr := r.RemoteAddr
	if idx := strings.LastIndex(addr, ":"); idx != -1 {
		addr = addr[:idx]
	}
	addr = strings.TrimPrefix(addr, "[")
	addr = strings.TrimSuffix(addr, "]")
	return addr == "127.0.0.1" || addr == "::1"
}
