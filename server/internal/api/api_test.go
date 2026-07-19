package api_test

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/ametis70/launchscope/server/internal/api"
	"github.com/ametis70/launchscope/server/internal/apps"
	"github.com/ametis70/launchscope/server/internal/audio"
	"github.com/ametis70/launchscope/server/internal/config"
	"github.com/ametis70/launchscope/server/internal/events"
	"github.com/ametis70/launchscope/server/internal/process"
	"github.com/gorilla/websocket"

	"io"
	"log/slog"
)

// ── test fixtures ─────────────────────────────────────────────────────────  //

func newTestRouter(t *testing.T) (http.Handler, *process.Manager, *events.Bus) {
	t.Helper()
	dir := t.TempDir()

	// Config.
	os.WriteFile(filepath.Join(dir, "config.json"),
		[]byte(`{"api":{"port":8765,"api_key":"testkey"}}`), 0o644)
	cfgLoader := config.NewLoader(dir)
	if _, err := cfgLoader.Load(); err != nil {
		t.Fatal(err)
	}

	// Apps.
	appsJSON, _ := json.Marshal([]apps.App{
		{ID: "kodi", Name: "Kodi", Exec: "/bin/sh -c 'sleep 60'"},
	})
	os.WriteFile(filepath.Join(dir, "apps.json"), appsJSON, 0o644)
	appsLoader := apps.NewLoader(dir)
	if _, err := appsLoader.Load(); err != nil {
		t.Fatal(err)
	}

	bus := events.NewBus()
	log := slog.New(slog.NewTextHandler(io.Discard, nil))
	mgr := process.NewManager(appsLoader, "/bin/sh -c 'trap exit TERM; sleep 60 & wait'", bus, log)

	router := api.NewRouter(mgr, cfgLoader, appsLoader, bus, log)
	return router, mgr, bus
}

func get(t *testing.T, handler http.Handler, path, apiKey string) *httptest.ResponseRecorder {
	t.Helper()
	req := httptest.NewRequest(http.MethodGet, path, nil)
	if apiKey != "" {
		req.Header.Set("X-Api-Key", apiKey)
	}
	// Simulate remote address so auth is applied.
	req.RemoteAddr = "10.0.0.1:12345"
	w := httptest.NewRecorder()
	handler.ServeHTTP(w, req)
	return w
}

func post(t *testing.T, handler http.Handler, path, body, apiKey string) *httptest.ResponseRecorder {
	t.Helper()
	req := httptest.NewRequest(http.MethodPost, path, strings.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	if apiKey != "" {
		req.Header.Set("X-Api-Key", apiKey)
	}
	req.RemoteAddr = "10.0.0.1:12345"
	w := httptest.NewRecorder()
	handler.ServeHTTP(w, req)
	return w
}

func fromLocalhost(t *testing.T, handler http.Handler, method, path, body string) *httptest.ResponseRecorder {
	t.Helper()
	var bodyR io.Reader
	if body != "" {
		bodyR = strings.NewReader(body)
	}
	req := httptest.NewRequest(method, path, bodyR)
	req.Header.Set("Content-Type", "application/json")
	req.RemoteAddr = "127.0.0.1:12345"
	w := httptest.NewRecorder()
	handler.ServeHTTP(w, req)
	return w
}

// ── auth middleware ───────────────────────────────────────────────────────  //

func TestAuth_RemoteWithoutKeyUnauthorized(t *testing.T) {
	router, _, _ := newTestRouter(t)
	w := get(t, router, "/api/status", "")
	if w.Code != http.StatusUnauthorized {
		t.Errorf("code = %d, want 401", w.Code)
	}
}

func TestAuth_RemoteWithWrongKeyUnauthorized(t *testing.T) {
	router, _, _ := newTestRouter(t)
	w := get(t, router, "/api/status", "wrongkey")
	if w.Code != http.StatusUnauthorized {
		t.Errorf("code = %d, want 401", w.Code)
	}
}

func TestAuth_RemoteWithCorrectKeyAllowed(t *testing.T) {
	router, _, _ := newTestRouter(t)
	w := get(t, router, "/api/status", "testkey")
	if w.Code != http.StatusOK {
		t.Errorf("code = %d, want 200", w.Code)
	}
}

func TestAuth_LocalhostBypassesKey(t *testing.T) {
	router, _, _ := newTestRouter(t)
	w := fromLocalhost(t, router, http.MethodGet, "/api/status", "")
	if w.Code != http.StatusOK {
		t.Errorf("code = %d, want 200", w.Code)
	}
}

func TestAuth_ApikeyQueryParam(t *testing.T) {
	router, _, _ := newTestRouter(t)
	req := httptest.NewRequest(http.MethodGet, "/api/status?apikey=testkey", nil)
	req.RemoteAddr = "10.0.0.1:12345"
	w := httptest.NewRecorder()
	router.ServeHTTP(w, req)
	if w.Code != http.StatusOK {
		t.Errorf("code = %d, want 200", w.Code)
	}
}

// ── GET /api/status ───────────────────────────────────────────────────────  //

func TestGetStatus_ReturnsJSON(t *testing.T) {
	router, _, _ := newTestRouter(t)
	w := fromLocalhost(t, router, http.MethodGet, "/api/status", "")
	if w.Code != http.StatusOK {
		t.Fatalf("code = %d", w.Code)
	}
	var resp map[string]any
	if err := json.NewDecoder(w.Body).Decode(&resp); err != nil {
		t.Fatalf("invalid JSON: %v", err)
	}
	if _, ok := resp["state"]; !ok {
		t.Error("response missing 'state' field")
	}
}

// ── GET /api/apps ─────────────────────────────────────────────────────────  //

func TestGetApps_ReturnsList(t *testing.T) {
	router, _, _ := newTestRouter(t)
	w := fromLocalhost(t, router, http.MethodGet, "/api/apps", "")
	if w.Code != http.StatusOK {
		t.Fatalf("code = %d", w.Code)
	}
	var list []map[string]any
	if err := json.NewDecoder(w.Body).Decode(&list); err != nil {
		t.Fatalf("invalid JSON: %v", err)
	}
	if len(list) != 1 {
		t.Errorf("expected 1 app, got %d", len(list))
	}
	if list[0]["id"] != "kodi" {
		t.Errorf("id = %v, want \"kodi\"", list[0]["id"])
	}
}

// ── POST /api/launch ──────────────────────────────────────────────────────  //

func TestPostLaunch_NotFoundReturns404(t *testing.T) {
	router, mgr, _ := newTestRouter(t)
	mgr.Start()
	waitState(t, mgr, process.StateUIRunning, 3*time.Second)
	defer mgr.Stop()

	w := fromLocalhost(t, router, http.MethodPost, "/api/launch/nonexistent", "")
	if w.Code != http.StatusNotFound {
		t.Errorf("code = %d, want 404", w.Code)
	}
}

func TestPostLaunch_BusyReturns409(t *testing.T) {
	router, _, _ := newTestRouter(t)
	// Manager not started — state is Starting (busy).
	w := fromLocalhost(t, router, http.MethodPost, "/api/launch/kodi", "")
	if w.Code != http.StatusConflict {
		t.Errorf("code = %d, want 409", w.Code)
	}
}

// ── GET /api/config ───────────────────────────────────────────────────────  //

func TestGetConfig_RedactsAPIKey(t *testing.T) {
	router, _, _ := newTestRouter(t)
	w := fromLocalhost(t, router, http.MethodGet, "/api/config", "")
	if w.Code != http.StatusOK {
		t.Fatalf("code = %d", w.Code)
	}
	var cfg map[string]any
	json.NewDecoder(w.Body).Decode(&cfg)
	apiSection, _ := cfg["api"].(map[string]any)
	if key, _ := apiSection["api_key"].(string); key != "" {
		t.Errorf("api_key should be redacted, got %q", key)
	}
}

func TestGetConfig_ReturnsPort(t *testing.T) {
	router, _, _ := newTestRouter(t)
	w := fromLocalhost(t, router, http.MethodGet, "/api/config", "")
	var cfg map[string]any
	json.NewDecoder(w.Body).Decode(&cfg)
	apiSection, _ := cfg["api"].(map[string]any)
	if port, _ := apiSection["port"].(float64); port != 8765 {
		t.Errorf("port = %v, want 8765", port)
	}
}

// ── POST /api/audio/volume ────────────────────────────────────────────────  //

func TestPostAudioVolume_MissingBody(t *testing.T) {
	router, _, _ := newTestRouter(t)
	w := fromLocalhost(t, router, http.MethodPost, "/api/audio/volume", "{}")
	// Neither value nor delta — 400.
	if w.Code != http.StatusBadRequest {
		t.Errorf("code = %d, want 400", w.Code)
	}
}

func TestPostAudioVolume_InvalidJSON(t *testing.T) {
	router, _, _ := newTestRouter(t)
	w := fromLocalhost(t, router, http.MethodPost, "/api/audio/volume", "not json")
	if w.Code != http.StatusBadRequest {
		t.Errorf("code = %d, want 400", w.Code)
	}
}

// ── POST /api/audio/mute ─────────────────────────────────────────────────  //

func TestPostAudioMute_MissingBody(t *testing.T) {
	router, _, _ := newTestRouter(t)
	w := fromLocalhost(t, router, http.MethodPost, "/api/audio/mute", "{}")
	if w.Code != http.StatusBadRequest {
		t.Errorf("code = %d, want 400", w.Code)
	}
}

// ── POST /api/system/power ────────────────────────────────────────────────  //

func TestPostPower_UnknownAction(t *testing.T) {
	router, _, _ := newTestRouter(t)
	w := fromLocalhost(t, router, http.MethodPost, "/api/system/power", `{"action":"fly"}`)
	if w.Code != http.StatusBadRequest {
		t.Errorf("code = %d, want 400", w.Code)
	}
}

func TestPostPower_InvalidJSON(t *testing.T) {
	router, _, _ := newTestRouter(t)
	w := fromLocalhost(t, router, http.MethodPost, "/api/system/power", "bad json")
	if w.Code != http.StatusBadRequest {
		t.Errorf("code = %d, want 400", w.Code)
	}
}

// ── POST /api/cec/* ───────────────────────────────────────────────────────  //

func TestPostCECActivate_DisabledReturns503(t *testing.T) {
	router, _, _ := newTestRouter(t)
	// CEC is not enabled in the test config.
	w := fromLocalhost(t, router, http.MethodPost, "/api/cec/activate", "")
	if w.Code != http.StatusServiceUnavailable {
		t.Errorf("code = %d, want 503", w.Code)
	}
}

func TestPostCECStandby_DisabledReturns503(t *testing.T) {
	router, _, _ := newTestRouter(t)
	w := fromLocalhost(t, router, http.MethodPost, "/api/cec/standby", "")
	if w.Code != http.StatusServiceUnavailable {
		t.Errorf("code = %d, want 503", w.Code)
	}
}

func TestPostCECPowerOn_DisabledReturns503(t *testing.T) {
	router, _, _ := newTestRouter(t)
	w := fromLocalhost(t, router, http.MethodPost, "/api/cec/power-on", "")
	if w.Code != http.StatusServiceUnavailable {
		t.Errorf("code = %d, want 503", w.Code)
	}
}

// ── WebSocket ─────────────────────────────────────────────────────────────  //

func TestWebSocket_Connect(t *testing.T) {
	router, _, _ := newTestRouter(t)
	srv := httptest.NewServer(router)
	defer srv.Close()

	url := "ws" + strings.TrimPrefix(srv.URL, "http") + "/ws"
	conn, _, err := websocket.DefaultDialer.Dial(url, nil)
	if err != nil {
		t.Fatalf("dial failed: %v", err)
	}
	defer conn.Close()
}

func TestWebSocket_ReceivesStateChangedEvent(t *testing.T) {
	dir := t.TempDir()
	os.WriteFile(filepath.Join(dir, "config.json"),
		[]byte(`{"api":{"port":8765,"api_key":"k"}}`), 0o644)
	cfgLoader := config.NewLoader(dir)
	cfgLoader.Load()

	os.WriteFile(filepath.Join(dir, "apps.json"), []byte(`[]`), 0o644)
	appsLoader := apps.NewLoader(dir)
	appsLoader.Load()

	bus := events.NewBus()
	log := slog.New(slog.NewTextHandler(io.Discard, nil))

	// Use a binary that stays alive so UI is in UIRunning and generates a StateChanged.
	mgr := process.NewManager(appsLoader, "/bin/sh -c 'trap exit TERM; sleep 60 & wait'", bus, log)

	router := api.NewRouter(mgr, cfgLoader, appsLoader, bus, log)
	srv := httptest.NewServer(router)
	defer srv.Close()

	url := "ws" + strings.TrimPrefix(srv.URL, "http") + "/ws"
	conn, _, err := websocket.DefaultDialer.Dial(url, nil)
	if err != nil {
		t.Fatalf("dial failed: %v", err)
	}
	defer conn.Close()
	conn.SetReadDeadline(time.Now().Add(5 * time.Second))

	// Start the manager — will publish StateChanged.
	mgr.Start()

	var msg map[string]any
	if err := conn.ReadJSON(&msg); err != nil {
		t.Fatalf("ReadJSON: %v", err)
	}
	if msg["type"] != "state_changed" {
		t.Errorf("type = %v, want \"state_changed\"", msg["type"])
	}

	// Cleanup.
	mgr.Stop()
}

func TestWebSocket_ReceivesAudioChangedEvent(t *testing.T) {
	dir := t.TempDir()
	os.WriteFile(filepath.Join(dir, "config.json"),
		[]byte(`{"api":{"port":8765,"api_key":"k"}}`), 0o644)
	cfgLoader := config.NewLoader(dir)
	cfgLoader.Load()

	os.WriteFile(filepath.Join(dir, "apps.json"), []byte(`[]`), 0o644)
	appsLoader := apps.NewLoader(dir)
	appsLoader.Load()

	bus := events.NewBus()
	log := slog.New(slog.NewTextHandler(io.Discard, nil))
	mgr := process.NewManager(appsLoader, exitBin, bus, log)
	router := api.NewRouter(mgr, cfgLoader, appsLoader, bus, log)

	srv := httptest.NewServer(router)
	defer srv.Close()

	url := "ws" + strings.TrimPrefix(srv.URL, "http") + "/ws"
	conn, _, err := websocket.DefaultDialer.Dial(url, nil)
	if err != nil {
		t.Fatalf("dial failed: %v", err)
	}
	defer conn.Close()
	conn.SetReadDeadline(time.Now().Add(3 * time.Second))

	// Publish an AudioChanged event directly.
	bus.Publish(events.AudioChanged, audio.State{Volume: 0.5, Muted: false, SinkName: "test"})

	var msg map[string]any
	if err := conn.ReadJSON(&msg); err != nil {
		t.Fatalf("ReadJSON: %v", err)
	}
	if msg["type"] != "audio_changed" {
		t.Errorf("type = %v, want \"audio_changed\"", msg["type"])
	}
}

func TestWebSocket_SubscriberCapRejects(t *testing.T) {
	dir := t.TempDir()
	os.WriteFile(filepath.Join(dir, "config.json"),
		[]byte(`{"api":{"port":8765,"api_key":"k"}}`), 0o644)
	cfgLoader := config.NewLoader(dir)
	cfgLoader.Load()

	os.WriteFile(filepath.Join(dir, "apps.json"), []byte(`[]`), 0o644)
	appsLoader := apps.NewLoader(dir)
	appsLoader.Load()

	bus := events.NewBus()
	log := slog.New(slog.NewTextHandler(io.Discard, nil))
	mgr := process.NewManager(appsLoader, exitBin, bus, log)
	router := api.NewRouter(mgr, cfgLoader, appsLoader, bus, log)
	srv := httptest.NewServer(router)
	defer srv.Close()

	url := "ws" + strings.TrimPrefix(srv.URL, "http") + "/ws"

	var conns []*websocket.Conn
	defer func() {
		for _, c := range conns {
			c.Close()
		}
	}()

	// Fill to cap (64).
	for i := 0; i < 64; i++ {
		c, _, err := websocket.DefaultDialer.Dial(url, nil)
		if err != nil {
			t.Fatalf("connection %d failed: %v", i, err)
		}
		conns = append(conns, c)
	}

	// Next connection must be rejected with 503.
	_, resp, err := websocket.DefaultDialer.Dial(url, nil)
	if err == nil {
		t.Error("expected dial to fail when cap is reached")
		return
	}
	if resp != nil && resp.StatusCode != http.StatusServiceUnavailable {
		t.Errorf("status = %d, want 503", resp.StatusCode)
	}
}

// ── context cancellation on websocket ────────────────────────────────────  //

func TestWebSocket_DisconnectCleans(t *testing.T) {
	router, _, bus := newTestRouter(t)
	srv := httptest.NewServer(router)
	defer srv.Close()

	url := "ws" + strings.TrimPrefix(srv.URL, "http") + "/ws"

	ctx, cancel := context.WithCancel(context.Background())
	dialer := websocket.Dialer{}
	conn, _, err := dialer.DialContext(ctx, url, nil)
	if err != nil {
		t.Fatalf("dial failed: %v", err)
	}

	// Close the connection and verify no panic or hang.
	conn.Close()
	cancel()

	// Give the server goroutine time to clean up.
	time.Sleep(100 * time.Millisecond)

	// Publish to the (now empty) bus — must not panic.
	bus.Publish(events.StateChanged, nil)
}

// ── helpers ───────────────────────────────────────────────────────────────  //

func waitState(t *testing.T, mgr *process.Manager, want process.State, timeout time.Duration) {
	t.Helper()
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		if mgr.CurrentState() == want {
			return
		}
		time.Sleep(50 * time.Millisecond)
	}
	t.Fatalf("timed out waiting for state %q, current = %q", want, mgr.CurrentState())
}

// exitBin is a shell command that exits immediately.
const exitBin = "/bin/sh -c 'exit 0'"
