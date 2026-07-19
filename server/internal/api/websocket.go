package api

import (
	"fmt"
	"log/slog"
	"net/http"

	"github.com/ametis70/launchscope/server/internal/audio"
	"github.com/ametis70/launchscope/server/internal/events"
	"github.com/ametis70/launchscope/server/internal/process"
	"github.com/gorilla/websocket"
)

// upgrader accepts WebSocket upgrades from any origin. This is intentional:
// the server is a local HTPC daemon and the auth middleware already enforces
// API-key authentication for all non-localhost connections. Restricting the
// Origin header would add no real security benefit in this context.
var upgrader = websocket.Upgrader{
	CheckOrigin: func(r *http.Request) bool { return true },
}

type wsMessage struct {
	Type    string `json:"type"`
	Payload any    `json:"payload"`
}

type wsHandler struct {
	bus *events.Bus
}

func (ws *wsHandler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	// Check subscriber cap before upgrading — http.Error cannot be sent after
	// the WebSocket handshake has been written to the connection.
	ch := ws.bus.Subscribe()
	if ch == nil {
		slog.Warn("ws: subscriber cap reached, rejecting connection")
		http.Error(w, "too many subscribers", http.StatusServiceUnavailable)
		return
	}
	defer ws.bus.Unsubscribe(ch)

	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		slog.Warn("ws upgrade failed", "err", err)
		return
	}
	defer conn.Close()

	// Read loop: detect client disconnect (we don't expect client messages).
	disconnected := make(chan struct{})
	go func() {
		defer close(disconnected)
		for {
			if _, _, err := conn.ReadMessage(); err != nil {
				return
			}
		}
	}()

	for {
		select {
		case <-disconnected:
			return
		case ev, ok := <-ch:
			if !ok {
				return
			}
			msg, err := eventToMessage(ev)
			if err != nil {
				slog.Error("ws: dropping malformed event", "err", err)
				continue
			}
			if err := conn.WriteJSON(msg); err != nil {
				return
			}
		}
	}
}

func eventToMessage(ev events.Event) (wsMessage, error) {
	switch ev.Type {
	case events.StateChanged:
		p, ok := ev.Payload.(process.StatePayload)
		if !ok {
			return wsMessage{}, fmt.Errorf("StateChanged: unexpected payload type %T", ev.Payload)
		}
		var cur *appSummary
		if p.CurrentApp != nil {
			cur = &appSummary{ID: p.CurrentApp.ID, Name: p.CurrentApp.Name}
		}
		return wsMessage{
			Type: "state_changed",
			Payload: map[string]any{
				"state":       p.State,
				"current_app": cur,
			},
		}, nil

	case events.AudioChanged:
		st, ok := ev.Payload.(audio.State)
		if !ok {
			return wsMessage{}, fmt.Errorf("AudioChanged: unexpected payload type %T", ev.Payload)
		}
		return wsMessage{
			Type: "audio_changed",
			Payload: audioResponse{
				Volume:   st.Volume,
				Muted:    st.Muted,
				SinkName: st.SinkName,
			},
		}, nil

	default:
		return wsMessage{Type: "unknown", Payload: nil}, nil
	}
}
